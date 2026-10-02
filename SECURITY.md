# Home Security & Alerting — System Reference

Complete documentation of the home security setup: state model, sensors, cameras,
speaker alerting, and per-automation logic. Entity IDs are real — search the config
to trace anything.

Last updated: 2026-10-02 (after front-door alert rework).

---

## 1. House state model

The system's behavior is driven by a small set of helpers:

| Entity | Type | Values | Purpose |
|---|---|---|---|
| `input_select.house_mode` | select | `None` / `Home` / `Away` / `Sleep` / `Holiday` | Master state. Set by Presence Detection automations from person trackers. `Sleep` entered manually/automatically at night; `House Mode - Morning motion ends Sleep` exits it. `Holiday` prompted after prolonged Away. |
| `input_boolean.guest_mode` | bool | on/off | Guests in the house — suppresses speaker alerts and CDS behaviors that would confuse them. |
| `input_boolean.housesitter_mode` | bool | on/off | Someone house-sitting while we're away — suppresses correlated person alerts in Away/Holiday. |
| `input_boolean.speaker_alerts` | bool | on/off | **Master kill switch for ALL speaker output** through `cast_media_with_no_chime`. Currently **OFF** while testing. |
| `input_boolean.resident_outside` | bool | on/off | Set during Sleep when a resident exits (e.g. letting the cat out) so their return doesn't trip the alarm. |
| `timer.resident_outside_window` | timer | | Countdown window for the resident-outside flow. |
| `input_boolean.cds_alarm` | bool | on/off | Cat Deterrent System armed flag. |
| `input_boolean.watchman` | bool | on/off | Dog geofence monitor (Watchman). |
| `input_boolean.bedtime` | bool | on/off | Night context flag used by lighting/security. |
| `alarm_control_panel.alarmo` | alarm | disarmed / armed_night / pending / triggered | Alarmo panel — the actual siren/flood escalation path used by Night Security. |

### Mode transitions

- `person.adam_smith` / `person.madeleine_moloney` → **Presence Detection** automations set `house_mode` to `Home`/`Away` per resident; combined logic resolves both away → `Away`.
- Prolonged Away → **Holiday Prompt** automations offer Holiday mode (light simulation at night).
- `Sleep` is entered via bedtime/mode setting; **House Mode - Morning motion ends Sleep** exits it on morning motion.
- `housesitter_mode` toggled via the Housesitter automations when a sitter stays.

---

## 2. Presence detection

| Person | Trackers | Notes |
|---|---|---|
| `person.adam_smith` | `device_tracker.pixel_6` (+ `pixel_6_2`; several stale `pixel_6_*` variants unavailable) | Drives Away/Home logic for Adam. |
| `person.madeleine_moloney` | `device_tracker.sm_a556e`, `sm_g973f`, `sm_g991n` | Drives Away/Home logic for Mads. |

Used by alert routing (`Sleep + both home` → bedroom speaker) and by mode transitions.

---

## 3. Perimeter sensors & cameras

### Cameras — all Reolink, on-device AI classification

Each camera exposes `binary_sensor.<cam>_motion|_person|_pet|_vehicle` plus a
`camera.<cam>_fluent` stream. **Only the classified sensors (person/pet) are used
for alerting — raw `_motion` pixel sensors are not** (wind, glass-door bleed).

| Camera | Sensor prefix | Notes |
|---|---|---|
| Front Door | `front_door_*` | Mounted high — person class needs a reasonably face-visible view. **Non-detection zone painted over street/footpath** — camera-side filtering, so HA never sees street pedestrians. |
| Doorbell | `doorbell_*_2` | Head-height — the most reliable person detector for the approach. |
| Front Balcony | `front_balcony_*` | Upper-floor outlook. |
| Garage | `garage_*` | Garage interior. |
| Side | `side_*` | Side of house. |
| Rear | `rear_*` | Backyard. |
| Patio | `camera1_*_3` | Patio (Camera 1 second channel). |
| Studio | `camera1_*` | **Currently unavailable** (camera offline). |
| E1 Pro | `e1_pro_*` | Indoor PTZ — used by CDS as a supplemental alarm. |

### Physical motion sensors (PIR)

| Entity | Location | Notes |
|---|---|---|
| `binary_sensor.motion_7` ("Front Courtyard") | Outdoor, front courtyard | **Outdoor-only** — used by front-door alert + floodlight. Aqara sensor, ~60s dwell. |
| `binary_sensor.hue_outdoor_motion_sensor_1_motion` | Backyard (Shed) | Feeds `input_datetime.last_pir_shed`. |
| `binary_sensor.hue_outdoor_motion_sensor_2_motion` | Backyard (House) | Feeds `input_datetime.last_pir_house`. |
| `binary_sensor.front_entry` | **INSIDE — front hallway** | ⚠️ Interior sensor; fires when residents approach the door from inside. **Deliberately NOT used** in any outdoor detection logic. |
| Interior PIRs | `den_motion`, `kitchen`, `hallway_1/2`, `bathroom`, `ensuite`, `motion_*` (laundry/garage/pantry etc.) | Room occupancy + motion lighting. Some currently `unavailable` (see §8). |

### Door/window contacts

| Entity | Covers |
|---|---|
| `binary_sensor.lumi_lumi_sensor_magnet_opening` | Front Door |
| `binary_sensor.lumi_lumi_sensor_magnet_b586cf03_on_off` | Back Door |
| `binary_sensor.lumi_lumi_sensor_magnet_opening_3` | Garage Rollerdoor (drives arming beep + away alerts) |
| `binary_sensor.lumi_lumi_sensor_magnet_opening_4` | Downstairs Door |
| `binary_sensor.door_sensor_7_iaszone` / `_8` / `_10` / `_13` | Den / Guestroom / Living sliding doors etc. |
| `binary_sensor.lumi_lumi_sensor_magnet_opening_2` | Front Gate — **unavailable** |
| `binary_sensor.perimeter_doors` | Group — any perimeter door open |

---

## 4. Speaker alert infrastructure

### `script.cast_media_with_no_chime` — the single choke point

Every audible alert goes through this script. Sequence:

1. **Gate**: exits silently unless `input_boolean.speaker_alerts` is on.
2. **Snapshot**: `orig_vol`, `orig_muted`, `orig_state` captured into script variables.
3. **Warm path** (speaker `idle` + `app_name == Default Media Receiver`):
   play `silence.wav` → once playing, `volume_set` to alert level → play alert.
4. **Cold path** (off / other app / dead session):
   mute → `silence.wav` primer (wakes the speaker; the cast-connection ding plays
   while muted) → `volume_set` during primer playback → unmute → play alert.
5. **Wait** for `playing` then `not playing` (bounded timeouts).
6. **Restore**: play `silence.wav` again → `volume_set` back to `orig_vol` during
   playback → restore mute → `turn_off` if it was originally off.

`mode: parallel` — required so den+kitchen+bedroom can fire simultaneously.

### Why the silence mask matters (empirically verified)

- Google/Nest speakers play a **volume-feedback tick on every `volume_set` — but only
  while idle**. During active playback the change is silent. All volume changes in the
  script are timed to land while a silent 2s WAV is playing → no audible ticks.
- `mute` does **not** suppress the tick on this hardware (tested); playback masking does.
- `scene.create`/`scene.turn_on` was tried and abandoned: `scene.turn_on` also restores
  `media_content_id`, which restarts the previous stream — a separate blip. Variables
  snapshot only what we actually want back (volume/mute/power).
- Known limitation: if a speaker was mid-music when an alert fires, the music is
  interrupted and **not** resumed (volume/mute/power are restored only).

### Cast keep-alive

`automation.cast_keep_alive_notification_speakers` plays `silence.wav` every 4 min —
**only** while the speaker is `idle` AND running `Default Media Receiver`. Google's
cast session expires after ~10 min idle; keep-alive holds it open so alerts take the
instant warm path (no wake ding, ~1s latency). Covers Den, Kitchen Display, Bedroom.

### Media URLs

Files live in `/config/www/` and are served as
`https://parkplace.duckdns.org:8123/local/<file>` — **the external URL is required**:
the cast speakers sit on the IoT VLAN and can't reach HA's LAN IP.

| File | Sound | Used by |
|---|---|---|
| `person-alert.wav` | Soft two-note ding | Front-door person alerts |
| `arm-click.wav` | Two short percussive clicks | Garage door arming beep |
| `arm-beep.wav` | Earlier piezo double-beep | Unused (superseded) |
| `cat-meow.ogg` | Real cat meow | Cat-location rocker |
| `cat-meow-alt.ogg` | Backup meow | Unused |
| `silence.wav` | 2s silence | Primer/mask/keep-alive |
| `barking-dog.mp3` | Dog bark | CDS alarm sequence |

### Alert speakers

| Entity | Room |
|---|---|
| `media_player.living_room_speaker` | Den |
| `media_player.bedroom_speaker_2` | Bedroom |
| `media_player.kitchen_display` | Upstairs kitchen (Nest Hub) |
| `media_player.upstairs` / `downstairs` / `whole_house` | Groups/others available |

### Room occupancy

`binary_sensor.den_occupied` (template, `template.yaml`) — on when `den_motion`
OR `device_tracker.desktop_9qq42c7_2` online OR a Den TV is playing. Gates whether
a Home-mode alert rings just the den or the whole house.

---

## 5. Automation logic reference

### Front door — primary path

**`Security - Front Door Person Alert`** (`security_front_door_person_alert`)

Triggers (OR): `front_door_person`, `doorbell_person_2`, `motion_7` (front courtyard PIR)
— all outdoor-only sensors, `off → on`.
Cooldown: 60s via `last_triggered` (kills sensor-flap double chimes).

Routing (`choose`, first match wins):

| Condition | Action |
|---|---|
| `house_mode` ∈ {Away, Holiday} | `camera.snapshot` → `www/frontdoor-snapshot.jpg` → push to Pixel 6 with image + "View Live Feed" (`app://com.mcu.reolink`) |
| `guest_mode` on | Quiet push to Pixel 6 — no speaker sound |
| `Sleep` + Adam & Mads home | `person-alert.wav` @ 1.0 on `bedroom_speaker_2` |
| `Home` + `den_occupied` on | `person-alert.wav` @ 1.0 on `living_room_speaker` |
| `Home` + den empty | Parallel: same alert on den + kitchen + bedroom |

`mode: single`. Volumes currently **1.0 for testing** — drop to ~0.5 after tuning.

**`Front Door - Person Floodlight`** (`front_door_person_floodlight`)

Triggers: `front_door_person` + `front_door_pet` + `doorbell_person_2` + `motion_7`.
On: floodlight on. Off: only when **all** sensors are `off` (PIR dwell keeps it lit
while someone lingers). `mode: restart`.

### Perimeter person detection — Away/Holiday

**`Security - Correlated person detection`** — the heavy alert.

Triggers: `side_person`, `camera1_person` (shed), `rear_person`, `camera1_person_3` (patio).
Condition: `house_mode` ∈ {Away, Holiday} + `housesitter_mode` off.

Logic: stamp `input_datetime.last_person_<cam>` → count stamps within 3 min →
**≥2 cameras = confirmed intrusion** → snapshot → push "Person confirmed by N cameras: …"
with image + Reolink deep link → reset all stamps (each alert needs a fresh pair).

**`Security - <zone> person detected`** (garage / patio / side / rear) —
single-camera notifications when away.

**`Security - <door> opened while away`** (front door / back door / garage roller /
sliding doors) — contact-sensor push alerts.

### Night security (Sleep mode + Alarmo)

**`Night Security - Person event evaluation`** — every camera person event during Sleep:

- Stamps the camera's `last_person_<cam>` datetime.
- ≥2 distinct cameras within 3 min → **confirmed**: floodlight on + snapshot + alert.
- camera + backyard PIR (`last_pir_shed`/`last_pir_house`) within 3 min → **possible**: floodlight + alert.
- single camera → quiet, throttled alert (`input_datetime.night_alert_last_sent`).

Skipped while `resident_outside` is on (that's the resident, not an intruder).

**Resident exit/return flow** — lets a resident step outside during Sleep without
tripping the alarm: `Resident exit detected` sets `resident_outside` + starts
`timer.resident_outside_window` → `Resident return`/`Resident window expired`/
`Resident arrives home` clear or escalate it.

**Alarmo chain** — `Alarm pending` (entry delay) → `Alarm triggered` (all
floodlights + den light 100% + push "ALARM TRIGGERED" to both phones) →
`Disarm`/`Re-arm` notification actions → `Arm verification`.

Other night automations: `PIR stamp`, `Shed door opened`, `Entry with person
sighting`, `Person inside garage`.

### CDS — Cat Deterrent System

`input_boolean.cds_alarm` armed via `CDS Alarm - Auto Enable (Cat Location)` /
`(Doors)`, cleared by `Auto Disable` / `Disable CDS (Morning)` / Guest Mode.

`cds_alarm_sequence` script: `scene.create` snapshot (den light + den speaker) →
parallel: front floodlight 2min, den light 100% 3min then restore, dog-bark
sequence, mains patio switch, plus1pm den switch — then `scene.den_before_alarm`
restore.

Supplements: `CDS - Rear Camera Spotlight`, `CDS - Side Camera Floodlight`,
`CDS - E1 Supplemental Alarm` (E1 Pro PTZ wails). `Cat Alarm - Light on Animal
Detection`, `Animal Detection Notification - Rear/Side/Patio`.

### Watchman — dog geofence

`input_boolean.watchman` + stored lat/long (`NFC - Set watchman`,
`Watchman - Set Location`). `Watchman - Location breach alert` → Level 1/2/3
warning pushes as the dog strays further. `Watchman - Flash` feedback on toggle.

### Notifications & beeps

- `Garage Door - Arming Beep` — `arm-click.wav` on den speaker, garage roller open/close.
- `Rocker 1 - Toggle Cat Location` — right button → `toggle_cat_location` + `cat-meow.ogg`.
- `Notification - Front Gate` / `Doorbell` / `Garage Door` — push notifications.
- `PC Notification - *` — browser/desktop variants.

### Housekeeping / watchdogs

- `Cast Keep-Alive - Notification Speakers` — see §4.
- `Shelly Device Offline Watchdog`, `IKEA Plug Offline Watchdog` — 5-min unavailable → push; recovery notice.
- `Sensor Offline Notification`, `Battery Low Notification` — 15-min unavailability threshold; `sensor_offline_notified` dedup flag.
- `Holiday - *` light simulation (front light sunset→sunrise, random evening lights till 10pm).

---

## 6. Edge cases & gotchas (learned the hard way)

1. **`binary_sensor.front_entry` is INDOOR.** It covers the hallway approach — it
   fires when residents walk to the door from inside. Never use it for perimeter logic.
2. **`binary_sensor.front_door_motion` is unreliable** — wind triggers it and it sees
   movement through the glass door (interior). Only person/pet classes are used.
3. **High-mounted camera + person class = face problem.** `front_door_person` can
   miss people who never look up. `doorbell_person_2` (head height) + courtyard PIR
   cover the gap.
4. **Sensor flap → double chimes.** Person sensors toggle on/off rapidly; all alert
   automations need cooldowns (60s on front door) or `for:`/stamp-correlation.
5. **Cast session expiry ≈ 10 min.** Without keep-alive, every alert cold-starts
   (~4s + wake ding). Keep-alive pings silence every 4 min while idle.
6. **Volume ticks only fire while idle.** Wrap every `volume_set` inside a playing
   silent file; mute alone does NOT suppress them on Nest hardware.
7. **IoT VLAN isolation.** Cast targets cannot fetch `http://192.168.0.78:8123/local/...`
   — always use the DuckDNS external URL.
8. **`mode: parallel` required** on `cast_media_with_no_chime` — `mode: single` would
   silently drop the 2nd/3rd speaker in the whole-house branch.
9. **`scene.turn_on` resumes media.** Don't snapshot media players you don't want
   auto-resumed — snapshot state into script variables instead.
10. **`speaker_alerts` is OFF right now** — flip it on when testing resumes
    (Settings → Helpers → "Speaker Alerts").
11. **`reolink_chime_*` can't be triggered on demand** — ringtones bind to doorbell-cam
    event classes only; use `siren.doorbell_siren_2` / camera sirens for escalation.

---

## 7. Currently unavailable / dead devices (known gaps)

- Cameras: `camera1_*` (Studio — person/pet/vehicle/motion all unavailable)
- PIRs: `living_room`, `dining` (occupancy_9), `motion_8` (bedroom), `motion_4`/`motion_5` (Side Garage/Walkway), `motion_studio`, `camera1_motion`
- Door contacts: `door_sensor_6` (Bedroom), `door_sensor_9`/`_11`/`_12`/`_15` (Garage Entry/Laundry/Garage Side), `front_gate`
- Speakers: `bathroom_speaker`, `kitchen_speaker_3`, `chromecast4224/6881`, `den_tv`
- `withings_in_bed_adam`, several `pixel_6_*` tracker duplicates

Zigbee context: network on channel 25 via ZHA (`socket://192.168.0.77:6638`).
IKEA plugs are routers — Plug 3 going down previously orphaned Aqara end devices
(now watchdogged).

---

## 8. Operational rules

- **Never restart HA without asking.** Use reloads (`automation.reload`,
  `script.reload`, `input_boolean.reload`, `template.reload`) + `config/core/check_config`.
- Config is edited locally (`C:\Users\adam\*.yaml`), deployed to `/config` on HAOS
  via SSH (`scp -P 22222 -i ~/.ssh/ha_access_key root@192.168.0.78:/config/`).
- `/config` is a git repo → `github.com:gnorm1011a/home-assistant` (branches:
  `main` = `cleanup`, both at latest).
- Lovelace dashboards are UI-managed → change via `.storage/lovelace.*` carefully or
  the WebSocket API; `.storage/` is gitignored except `lovelace.adam_ui`.
- Snapshot images land in `www/` and are served publicly via DuckDNS — they're
  ephemeral runtime artifacts (safe to commit, expected to churn).
