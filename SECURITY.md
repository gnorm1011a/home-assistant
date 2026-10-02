# Home Security & Alerting — System Reference

Complete documentation of the home security setup: state model, sensor/camera
coverage by attack surface, speaker alerting, and per-automation logic.
Entity IDs are real — search the config to trace anything.

Last updated: 2026-10-02.

---

## 1. House state model

| Entity | Type | Values | Purpose |
|---|---|---|---|
| `input_select.house_mode` | select | `None` / `Home` / `Away` / `Sleep` / `Holiday` | Master state. Set by Presence Detection automations from person trackers. `Sleep` entered at night; `House Mode - Morning motion ends Sleep` exits it. `Holiday` offered after prolonged Away. |
| `input_boolean.guest_mode` | bool | on/off | Guests staying — **security speaker alerts are suppressed** (alerts become quiet pushes instead of audible chimes). Non-security sounds (door beeps, miscellaneous notifications) are NOT affected. |
| `input_boolean.housesitter_mode` | bool | on/off | Someone house-sitting while we're away — suppresses correlated person alerts in Away/Holiday. |
| `input_boolean.speaker_alerts` | bool | on/off | **Master kill switch for ALL speaker output** through `cast_media_with_no_chime`. Currently **OFF** while testing. |
| `input_boolean.resident_outside` | bool | on/off | Set during Sleep when a resident exits (e.g. letting a pet out) so their return doesn't trip the alarm. |
| `timer.resident_outside_window` | timer | | Countdown window for the resident-outside flow. |
| `input_boolean.bedtime` | bool | on/off | Night context flag. |
| `alarm_control_panel.alarmo` | alarm | disarmed / armed_night / pending / triggered | Alarmo panel — the escalation path used by Night Security. |

### Mode transitions

- `person.adam_smith` / `person.madeleine_moloney` → Presence Detection automations set `house_mode` per resident; both away → `Away`.
- Prolonged Away → Holiday Prompt automations offer Holiday mode (light simulation).
- `housesitter_mode` toggled via the Housesitter automations.

## 2. Presence detection

| Person | Trackers |
|---|---|
| `person.adam_smith` | `device_tracker.pixel_6` (+ `pixel_6_2`; several stale `pixel_6_*` variants unavailable) |
| `person.madeleine_moloney` | `device_tracker.sm_a556e`, `sm_g973f`, `sm_g991n` |

Drives house-mode transitions and alert routing (`Sleep + both home` → bedroom speaker).

---

## 3. Attack surfaces & coverage

The property's realistic entry vectors, and what currently covers each. **Gaps are
marked ⚠️** — dead sensors or missing coverage are called out in §6.

### A. Front door / walkway approach

Most likely vector — straight up the walkway.

| Layer | Coverage |
|---|---|
| Detection | `binary_sensor.motion_7` (courtyard PIR — outdoor, catches anyone in the courtyard regardless of facing), `binary_sensor.doorbell_person_2` (head-height camera — reliable person class), `binary_sensor.front_door_person` (high camera — zone-filtered, street excluded) |
| Contact | `binary_sensor.lumi_lumi_sensor_magnet_opening` (Front Door) |
| Response | Front-door alert routing (see §5) + `light.front_door_floodlight` |

Camera-side non-detection zone painted over street/footpath — the camera itself
filters out pedestrians, so no street false-positives.

### B. Balcony climb → upper floor / main bedroom

Climb to the front balcony, enter via the upstairs bedroom.

| Layer | Coverage |
|---|---|
| Detection | `binary_sensor.front_balcony_person` / `_pet` / `_motion` (Front Balcony camera) |
| Light | `light.front_balcony_floodlight` |
| Contact | Bedroom door/window contact — ⚠️ `binary_sensor.door_sensor_5_iaszone` ("Bed") and `motion_8` (Bedroom) are **unavailable** |

⚠️ **Known weakness:** the balcony camera's field of view also picks up street
pedestrians — it has **no non-detection zone painted yet** (unlike the front-door
cam). Its person sensor will false-positive on passers-by until a zone is drawn
in the Reolink app.

### C. Side gate → side garage door → garage → house door

Jump the side gate, use the garage as the entry path.

| Layer | Coverage |
|---|---|
| Detection | `binary_sensor.side_person` / `_pet` / `_motion` (Side camera), ⚠️ `binary_sensor.motion_4` (Side Garage PIR — **unavailable**) |
| Contact | ⚠️ `binary_sensor.door_sensor_12_iaszone` (Garage Side Door — **unavailable**), `binary_sensor.lumi_lumi_sensor_magnet_opening_3` (Garage Rollerdoor), ⚠️ `binary_sensor.door_sensor_9_iaszone` (Garage Entry Door to house — **unavailable**) |
| Detection (inside) | `binary_sensor.garage_person` (Garage camera, covers interior) |

⚠️ **This is the weakest surface** — the side-garage PIR and both garage door
contacts are dead. Currently covered only by the Side + Garage cameras.

### D. Side gate → side walkway → backyard

Jump the side gate, continue down the side path to the backyard.

| Layer | Coverage |
|---|---|
| Detection | ⚠️ `binary_sensor.motion_5` (Side Walkway PIR — **unavailable**), `binary_sensor.side_person` (Side camera) |
| Detection (rear) | `binary_sensor.rear_person` (Rear camera), `binary_sensor.hue_outdoor_motion_sensor_2_motion` (Backyard House PIR) |

⚠️ The walkway PIR is dead — the side camera is the only sensor on this path.

### E. Back fences (4 adjacent yards) → backyard → house entries

Fences are jumpable from four neighbouring yards; then the intruder can reach the
den door, back door, guestroom door, or the side path.

| Layer | Coverage |
|---|---|
| Detection | `binary_sensor.rear_person` / `_pet` (Rear camera), `binary_sensor.camera1_person_3` / `_pet_2` (Patio camera), `binary_sensor.hue_outdoor_motion_sensor_1_motion` (Backyard Shed PIR) + `_2` (Backyard House PIR), `binary_sensor.garden_motion` |
| Contact | `binary_sensor.door_sensor_7_iaszone` (Den Sliding Door), `binary_sensor.door_sensor_8_iaszone` (Guestroom Sliding Door), `binary_sensor.door_sensor_10_iaszone` (Living Sliding Door), `binary_sensor.lumi_lumi_sensor_magnet_b586cf03_on_off` (Back Door) |
| Detection (side path) | `binary_sensor.side_person` (Side camera) |

Best-covered surface — two cameras, two outdoor PIRs, and every rear entry has a
contact sensor.

---

## 4. Sensor location map

Every security-relevant sensor by physical location. **Interior sensors can never
discriminate a visitor from a resident** — only outdoor-facing sensors are valid
alert triggers.

### Outdoor — valid alert triggers

| Entity | Type | Location | Used in alerts? |
|---|---|---|---|
| `binary_sensor.motion_7` | PIR | Front courtyard | ✅ Front-door alert + floodlight |
| `binary_sensor.front_door_person` / `_pet` | Camera class | Front door (high mount, zone-filtered) | ✅ Alert + floodlight |
| `binary_sensor.doorbell_person_2` / `_pet_2` | Camera class | Doorbell (head height) | ✅ Alert + floodlight |
| `binary_sensor.front_balcony_person` / `_pet` / `_motion` | Camera | Front balcony | Floodlight zone only — street noise ⚠️ |
| `binary_sensor.side_person` / `_pet` / `_motion` | Camera | Side of house | Correlated detection + night eval |
| `binary_sensor.rear_person` / `_pet` / `_motion` | Camera | Rear | Correlated detection + night eval |
| `binary_sensor.camera1_person_3` / `_pet_2` | Camera | Patio | Correlated detection + night eval |
| `binary_sensor.garage_person` / `_pet` | Camera | Garage interior | Away person alerts + night eval |
| `binary_sensor.hue_outdoor_motion_sensor_1_motion` | PIR | Backyard (shed side) | Night eval stamps (`last_pir_shed`) |
| `binary_sensor.hue_outdoor_motion_sensor_2_motion` | PIR | Backyard (house side) | Night eval stamps (`last_pir_house`) |
| `binary_sensor.garden_motion` | PIR | Garden | — |

### Contacts (entry points)

| Entity | Door | Surface |
|---|---|---|
| `binary_sensor.lumi_lumi_sensor_magnet_opening` | Front Door | A |
| `binary_sensor.lumi_lumi_sensor_magnet_b586cf03_on_off` | Back Door | E |
| `binary_sensor.door_sensor_7_iaszone` | Den Sliding Door | E |
| `binary_sensor.door_sensor_8_iaszone` | Guestroom Sliding Door | E |
| `binary_sensor.door_sensor_10_iaszone` | Living Sliding Door | E |
| `binary_sensor.lumi_lumi_sensor_magnet_opening_3` | Garage Rollerdoor | C |
| `binary_sensor.lumi_lumi_sensor_magnet_opening_4` | Downstairs Door | — |
| `binary_sensor.perimeter_doors` | Group: any perimeter door | All |

### Indoor — occupancy only, NEVER alert triggers

| Entity | Location |
|---|---|
| `binary_sensor.front_entry` | Front hallway (sees residents approaching from inside) |
| `binary_sensor.den_motion` + `lumi_..._occupancy_5` | Den |
| `binary_sensor.kitchen` + `lumi_..._occupancy_7` | Kitchen |
| `binary_sensor.hallway_1/2` + `lumi_..._occupancy_10/3` | Hallways |
| `binary_sensor.bathroom`, `ensuite`, `motion_1/3/6` | Bathroom, ensuite, laundry, garage interior, pantry |

### Deliberately excluded from alerting

| Entity | Why excluded |
|---|---|
| `binary_sensor.front_door_motion` | Pixel motion — wind + sees through the glass door (interior movement) |
| `binary_sensor.doorbell_motion_2` | Same class of noise |
| `binary_sensor.front_entry` | Indoor sensor — fires on resident approach |
| `binary_sensor.mains_front_courtyard_input_0_input` | Shelly light-circuit input, not a motion sensor (name is misleading) |

---

## 5. Speaker alert infrastructure

### `script.cast_media_with_no_chime` — the single choke point

Every audible alert goes through this script. Sequence:

1. **Gate**: exits silently unless `input_boolean.speaker_alerts` is on.
2. **Snapshot**: `orig_vol`, `orig_muted`, `orig_state` captured into variables.
3. **Warm path** (`idle` + `app_name == Default Media Receiver`): play
   `silence.wav` → `volume_set` alert level during playback → play alert.
4. **Cold path** (off / other app / dead session): mute → `silence.wav` primer
   (wake ding plays muted) → `volume_set` during primer → unmute → play alert.
5. **Wait** `playing` → `not playing` (bounded timeouts).
6. **Restore**: `silence.wav` again → `volume_set` back to `orig_vol` during
   playback → restore mute → `turn_off` if originally off.

`mode: parallel` — required for simultaneous den+kitchen+bedroom alerts.

### Why the silence mask (empirically verified)

- Google/Nest speakers tick on every `volume_set` — **only while idle**. During
  playback, volume changes are silent. All volume changes land inside a playing
  2s silent WAV → no audible ticks.
- `mute` does NOT suppress the tick on this hardware; playback masking does.
- `scene.create`/`turn_on` was abandoned: it restores `media_content_id` and
  resumes the previous stream. Variables snapshot only volume/mute/power.
- Limitation: a speaker mid-music gets interrupted and is NOT resumed
  (volume/mute/power restored only).

### Cast keep-alive

`automation.cast_keep_alive_notification_speakers` plays `silence.wav` every 4 min,
only while `idle` + Default Media Receiver. Cast sessions die after ~10 min idle;
keep-alive holds them warm so alerts take the instant path. Covers Den, Kitchen
Display, Bedroom.

### Media

Served via `https://parkplace.duckdns.org:8123/local/...` — the **external URL is
required**: speakers on the IoT VLAN can't reach HA's LAN IP.

| File | Sound | Used by |
|---|---|---|
| `person-alert.wav` | Soft two-note ding | Front-door person alerts |
| `arm-click.wav` | Two percussive clicks | Garage door arming beep |
| `silence.wav` | 2s silence | Primer/mask/keep-alive |

### Alert speakers

| Entity | Room |
|---|---|
| `media_player.living_room_speaker` | Den |
| `media_player.bedroom_speaker_2` | Bedroom |
| `media_player.kitchen_display` | Upstairs kitchen (Nest Hub) |
| `media_player.upstairs` / `downstairs` / `whole_house` | Additional targets |

`binary_sensor.den_occupied` (template) — `den_motion` OR desktop online OR Den TV
playing; gates whether Home-mode alerts ring just the den or all three speakers.

---

## 6. Automation logic reference

### Front door — primary path

**`Security - Front Door Person Alert`** (`security_front_door_person_alert`)

Triggers (OR): `front_door_person`, `doorbell_person_2`, `motion_7`. Cooldown: 60s.

| Condition | Action |
|---|---|
| `house_mode` ∈ {Away, Holiday} | Snapshot → `www/frontdoor-snapshot.jpg` → push to Pixel 6 + "View Live Feed" (Reolink deep link) |
| `guest_mode` on | Quiet push — no speaker sound |
| `Sleep` + Adam & Mads home | `person-alert.wav` @ 1.0 → bedroom speaker |
| `Home` + `den_occupied` on | `person-alert.wav` @ 1.0 → den speaker |
| `Home` + den empty | Parallel → den + kitchen + bedroom |

`mode: single`. Volumes at **1.0 during testing** — retune after.

**`Front Door - Person Floodlight`** — on when any of `front_door_person`,
`front_door_pet`, `doorbell_person_2`, `motion_7` fires; off only when ALL clear.
`mode: restart`.

### Perimeter person detection — Away/Holiday

**`Security - Correlated person detection`**: `side`/`shed`/`rear`/`patio` person
sensors → stamps `input_datetime.last_person_<cam>` → **≥2 distinct cameras within
3 min** = confirmed → snapshot + push "Person confirmed by N cameras" + Reolink
link → resets stamps. Requires Away/Holiday + housesitter off.

**`Security - <zone> person detected`** (garage/patio/side/rear) — single-camera
push notifications while away.

**`Security - <door> opened while away`** (front/back/garage roller/sliding) —
contact push alerts.

### Night security (Sleep + Alarmo)

**`Night Security - Person event evaluation`** — each camera person event during
Sleep (skipped while `resident_outside`):

- stamp `last_person_<cam>`
- ≥2 cameras in 3 min → **confirmed**: floodlight + snapshot + alert
- camera + backyard PIR in 3 min → **possible**: floodlight + alert
- single camera → quiet throttled alert (`night_alert_last_sent` throttle)

**Resident exit/return flow** — `Resident exit detected` sets `resident_outside`
+ `timer.resident_outside_window`; `Resident return` / `Resident window expired` /
`Resident arrives home` clear or escalate. Lets a resident step out during Sleep
without tripping the alarm.

**Alarmo chain** — `Alarm pending` (entry delay) → `Alarm triggered` (all
floodlights + den 100% + "ALARM TRIGGERED" push to both phones) → `Disarm` /
`Re-arm` from notification actions → `Arm verification`.

Also: `PIR stamp`, `Shed door opened`, `Entry with person sighting`,
`Person inside garage`, `Morning motion ends Sleep`.

### Notifications

- `Garage Door - Arming Beep` — `arm-click.wav` on den speaker, roller door open/close.
- `Notification - Front Gate` / `Doorbell` / `Garage Door` — pushes.
- `PC Notification - *` — desktop variants.
- `Holiday - *` — light simulation (presence mimicry while away).

---

## 7. Edge cases & gotchas

1. **Pixel motion sensors are unreliable for alerts** — wind and through-glass
   visibility cause false positives. Only classified person/pet sensors and
   outdoor PIRs drive alerts.
2. **High-mounted cameras need face-ish views** for person class — cover gaps
   with a second (lower) camera or an outdoor PIR.
3. **Camera non-detection zones filter at the source** — painted in the Reolink
   app, invisible to HA. Front door done; front balcony still needs one (street
   in view).
4. **Sensor flap → double alerts.** Classified sensors toggle rapidly; every
   alert path needs a cooldown or stamp-correlation.
5. **Cast sessions expire ≈10 min** — keep-alive or every alert is a cold start
   (~4s + muted wake ding).
6. **Volume ticks only fire while idle** — `volume_set` inside playing silence
   is silent; mute alone does NOT suppress ticks on Nest hardware.
7. **IoT VLAN isolation** — cast targets need the DuckDNS external URL, not the
   HA LAN IP.
8. **`mode: parallel`** on the shared script — `mode: single` silently drops
   simultaneous speaker calls.
9. **`scene.turn_on` resumes prior media** — use variables for surgical
   volume/mute/power restore.
10. **`speaker_alerts` currently OFF** — flip on when testing resumes.
11. **Reolink chime can't be triggered on demand** — ringtones bind to camera
    event classes; `siren.doorbell_siren_2`/camera sirens exist for escalation.

---

## 8. Coverage gaps — dead devices

| Gap | Surface | Impact |
|---|---|---|
| `motion_4` (Side Garage PIR) | C | No PIR on garage side door path |
| `door_sensor_12` (Garage Side Door) | C | No contact on garage side entry |
| `door_sensor_9` (Garage Entry Door) | C | No contact on garage→house door |
| `motion_5` (Side Walkway PIR) | D | No PIR on side walkway |
| `door_sensor_5` ("Bed") + `motion_8` (Bedroom) | B | No contact/PIR upstairs |
| `camera1_*` (Studio cam + sensors) | — | Whole camera offline |
| `front_gate` contact | A/D | Front gate unmonitored |
| `living_room`, `dining`, `motion_studio` | interior | Interior motion-light gaps (not security-critical) |
| Front balcony zone | B | Balcony cam sees street — needs non-detection zone |

**Priority for hardware attention:** surface C (garage path — three dead sensors)
and surface B (balcony cam zone + bedroom contacts).

Zigbee context: channel 25 via ZHA (`socket://192.168.0.77:6638`). IKEA plugs are
routers — Plug 3 dropping previously orphaned Aqara end devices.

---

## 9. Operational rules

- **Never restart HA without asking.** Use reloads + `config/core/check_config`.
- Config edited locally (`C:\Users\adam\*.yaml`), deployed to `/config` on HAOS
  via SSH (`scp -P 22222 -i ~/.ssh/ha_access_key root@192.168.0.78:/config/`).
- `/config` is a git repo → `github.com:gnorm1011a/home-assistant` (`main` and
  `cleanup` at same head).
- Lovelace dashboards are UI-managed — change via WebSocket API, not file edits
  (`.storage/` gitignored except `lovelace.adam_ui`).
- Snapshot images in `www/` are ephemeral runtime artifacts, served publicly via
  DuckDNS — expected to churn.
