#!/bin/sh
# SurePetcare API sensor - queries the SurePetcare API for accurate cat flap data
# Output: JSON for HA command_line sensor
#
# Data provided:
#   - entries: cat entries today (direction=1)
#   - exits: cat exits today (direction=0)
#   - looked_through: times cat looked through flap (direction=2)
#   - last_entry: timestamp of last entry
#   - position: "inside" or "outside"
#   - position_since: timestamp since current position
#   - time_outside_today: total seconds outside today
#   - time_outside_today_mins: total minutes outside today (rounded)
#   - outside_trips_today: number of outside trips today

USERNAME=$(cat /config/.storage/core.config_entries | jq -r '.data.entries[] | select(.domain == "surepetcare") | .data.username')
PASSWORD=$(cat /config/.storage/core.config_entries | jq -r '.data.entries[] | select(.domain == "surepetcare") | .data.password')

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "last_entry": "null", "position": "unknown", "position_since": "null", "time_outside_today": 0, "time_outside_today_mins": 0, "outside_trips_today": 0, "error": "no_credentials"}'
  exit 0
fi

# Authenticate
AUTH_RESP=$(curl -s -X POST "https://app-api.production.surehub.io/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email_address\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"device_id\":\"0\"}" 2>/dev/null)

TOKEN=$(echo "$AUTH_RESP" | jq -r '.data.token' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "last_entry": "null", "position": "unknown", "position_since": "null", "time_outside_today": 0, "time_outside_today_mins": 0, "outside_trips_today": 0, "error": "auth_failed"}'
  exit 0
fi

# Get household and pet IDs
HH_RESP=$(curl -s "https://app-api.production.surehub.io/api/household" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)
HH_ID=$(echo "$HH_RESP" | jq -r '.data[0].id' 2>/dev/null)

PETS_RESP=$(curl -s "https://app-api.production.surehub.io/api/household/$HH_ID/pet" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)
PET_ID=$(echo "$PETS_RESP" | jq -r '.data[0].id' 2>/dev/null)

if [ -z "$HH_ID" ] || [ "$HH_ID" = "null" ] || [ -z "$PET_ID" ] || [ "$PET_ID" = "null" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "last_entry": "null", "position": "unknown", "position_since": "null", "time_outside_today": 0, "time_outside_today_mins": 0, "outside_trips_today": 0, "error": "no_household_or_pet"}'
  exit 0
fi

# Calculate midnight AEST in UTC (AEST = UTC+10)
YESTERDAY=$(date -u +%Y-%m-%d -d "@$(($(date -u +%s) - 86400))" 2>/dev/null)
MIDNIGHT_UTC="${YESTERDAY}T14:00:00+00:00"

# 1. Get pet status (current position)
PET_RESP=$(curl -s "https://app-api.production.surehub.io/api/pet/$PET_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

WHERE=$(echo "$PET_RESP" | jq -r '.data.position.where' 2>/dev/null)
POSITION_SINCE=$(echo "$PET_RESP" | jq -r '.data.position.since' 2>/dev/null)

# where: 1=inside, 2=outside
if [ "$WHERE" = "1" ]; then
  POSITION="inside"
elif [ "$WHERE" = "2" ]; then
  POSITION="outside"
else
  POSITION="unknown"
fi

# 2. Get timeline for entry/exit counts
TL_RESP=$(curl -s "https://app-api.production.surehub.io/api/timeline/household/$HH_ID?page_size=50" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

ENTRIES=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 1) | select(.created_at >= $midnight)] | length' 2>/dev/null)
EXITS=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 0) | select(.created_at >= $midnight)] | length' 2>/dev/null)
LOOKED=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 2) | select(.created_at >= $midnight)] | length' 2>/dev/null)
LAST_ENTRY=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 1) | select(.created_at >= $midnight)] | sort_by(.created_at) | last | .created_at' 2>/dev/null)

# 3. Get aggregate report for time outside today
# URL-encode the + in the timestamp
MIDNIGHT_ENCODED=$(echo "$MIDNIGHT_UTC" | sed 's/+/%2B/g')
NOW_ENCODED=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" | sed 's/+/%2B/g')

AGG_RESP=$(curl -s "https://app-api.production.surehub.io/api/v2/report/household/$HH_ID/pet/$PET_ID/aggregate?from=$MIDNIGHT_ENCODED&to=$NOW_ENCODED" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

TIME_OUTSIDE=$(echo "$AGG_RESP" | jq -r '[.data.movement.datapoints[] | .duration] | add // 0' 2>/dev/null)
TIME_OUTSIDE_MINS=$(echo "$TIME_OUTSIDE" | awk '{printf "%d", $1 / 60}' 2>/dev/null)
OUTSIDE_TRIPS=$(echo "$AGG_RESP" | jq -r '.data.movement.datapoints | length' 2>/dev/null)

# Output JSON
echo "{\"entries\": ${ENTRIES:-0}, \"exits\": ${EXITS:-0}, \"looked_through\": ${LOOKED:-0}, \"last_entry\": \"${LAST_ENTRY:-null}\", \"position\": \"${POSITION}\", \"position_since\": \"${POSITION_SINCE:-null}\", \"time_outside_today\": ${TIME_OUTSIDE:-0}, \"time_outside_today_mins\": ${TIME_OUTSIDE_MINS:-0}, \"outside_trips_today\": ${OUTSIDE_TRIPS:-0}, \"midnight_aest\": \"${MIDNIGHT_UTC}\"}"
