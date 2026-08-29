#!/bin/sh
# SurePetcare flap entry counter
# Queries the SurePetcare API timeline and counts cat entries (direction=1) since midnight local time
# Output: JSON for HA command_line sensor

USERNAME=$(cat /config/.storage/core.config_entries | jq -r '.data.entries[] | select(.domain == "surepetcare") | .data.username')
PASSWORD=$(cat /config/.storage/core.config_entries | jq -r '.data.entries[] | select(.domain == "surepetcare") | .data.password')

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "error": "no_credentials"}'
  exit 0
fi

AUTH_RESP=$(curl -s -X POST "https://app-api.production.surehub.io/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email_address\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"device_id\":\"0\"}" 2>/dev/null)

TOKEN=$(echo "$AUTH_RESP" | jq -r '.data.token' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "error": "auth_failed"}'
  exit 0
fi

HH_RESP=$(curl -s "https://app-api.production.surehub.io/api/household" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

HH_ID=$(echo "$HH_RESP" | jq -r '.data[0].id' 2>/dev/null)

if [ -z "$HH_ID" ] || [ "$HH_ID" = "null" ]; then
  echo '{"entries": 0, "exits": 0, "looked_through": 0, "error": "no_household"}'
  exit 0
fi

# Calculate midnight AEST in UTC using jq
# AEST = UTC+10, so midnight AEST today = 14:00 UTC yesterday
# Use jq to calculate yesterday's date in UTC, then add 14 hours
MIDNIGHT_UTC=$(jq -n 'now | todaysdate = (.- 86400) | strftime("%Y-%m-%d") | . + "T14:00:00+00:00"' 2>/dev/null)

# Fallback: use date with seconds offset
if [ -z "$MIDNIGHT_UTC" ] || [ "$MIDNIGHT_UTC" = "null" ]; then
  # Get current UTC time, subtract 1 day, extract date
  YESTERDAY_UTC=$(date -u +%Y-%m-%d -d "@$(($(date -u +%s) - 86400))" 2>/dev/null)
  if [ -z "$YESTERDAY_UTC" ]; then
    # Try busybox date
    YESTERDAY_UTC=$(date -u -D %s +%Y-%m-%d $(($(date -u +%s) - 86400)) 2>/dev/null)
  fi
  MIDNIGHT_UTC="${YESTERDAY_UTC}T14:00:00+00:00"
fi

TL_RESP=$(curl -s "https://app-api.production.surehub.io/api/timeline/household/$HH_ID?page_size=50" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

ENTRIES=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 1) | select(.created_at >= $midnight)] | length' 2>/dev/null)
EXITS=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 0) | select(.created_at >= $midnight)] | length' 2>/dev/null)
LOOKED=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 2) | select(.created_at >= $midnight)] | length' 2>/dev/null)

LAST_ENTRY=$(echo "$TL_RESP" | jq -r --arg midnight "$MIDNIGHT_UTC" '[.data[] | select(.movements != null) | .movements[] | select(.direction == 1) | select(.created_at >= $midnight)] | sort_by(.created_at) | last | .created_at' 2>/dev/null)

echo "{\"entries\": ${ENTRIES:-0}, \"exits\": ${EXITS:-0}, \"looked_through\": ${LOOKED:-0}, \"last_entry\": \"${LAST_ENTRY:-null}\", \"midnight_aest\": \"${MIDNIGHT_UTC}\"}"
