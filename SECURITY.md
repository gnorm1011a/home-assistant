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
| `input_boolean.enable_alarm` | bool | on/off | **Master toggle for the security system.** Gates every alerting automation (Away door/person alerts, correlated detection, front-door alert, night-security alerts, pending announcement, sensor watchdog). State-tracking automations (direction stamps, person/PIR stamps, resident exit/return) keep running so re-enabling doesn't leave stale state. Alarmo itself is NOT blocked — disarm/arm still work. |
| `input_boolean.resident_outside` | bool | on/off | Set during Sleep when a resident exits (e.g. letting a pet out) so their return doesn't trip the alarm. |
| `timer.resident_outside_window` | timer | | Countdown window for the resident-outside flow. |
| `input_datetime.last_house_departure` | datetime | | Stamp set by Door direction detection when a door opens with interior-side activity in the prior 60s. Front-door alerts suppress for 120s after a departure. |
| `input_datetime.last_house_arrival` | datetime | | Stamp set when a door opens with exterior-side activity in the prior 60s. |
| `input_boolean.bedtime` | bool | on/off | Night context flag. |
| `alarm_control_panel.alarmo` | alarm | disarmed / armed_away / armed_night / pending / triggered | Alarmo panel. Entry delay (pending): **60s armed_away**, 45s armed_home/night, 0 armed_vacation. |

### Mode transitions

- `person.adam_smith` / `person.madeleine_moloney` → Presence Detection automations set `house_mode` per resident; both away → `Away`.
- Prolonged Away → Holiday Prompt automations offer Holiday mode (light simulation).
- `housesitter_mode` toggled via the Housesitter automations.

## 2. Presence detection

| Person | Trackers | Sources |
|---|---|---|
| `person.adam_smith` | `device_tracker.pixel_6`, `device_tracker.pixel_6_2` | HA companion-app GPS + UniFi router (WiFi) |
| `person.madeleine_moloney` | `device_tracker.sm_a556e`, `device_tracker.galaxy_a55_5g` | HA companion-app GPS + UniFi router (WiFi) |

**Rules that matter:**

- A person is `home` if **any** tracker reports home; `not_home` requires **all**
  trackers not_home. Dual-source means WiFi loss alone (e.g. phone doze) cannot
  mark someone away — GPS still reports the home zone. Conversely a GPS flap
  while away cannot mark them home — the router tracker must also see them.
- UniFi `detection_time` is **120s** (was 300): the router tracker marks a phone
  away ~2 min after it leaves WiFi range. It is the slow leg of away-detection.
- `house_mode → Away` has two paths per person:
  - **Normal:** person `not_home` for **5 min** (absorbs transient glitches).
  - **Departure fast path:** that person's GPS tracker `not_home` for 3 min
    within 5 min of `input_datetime.last_house_departure` — a physical door
    exit corroborates the GPS, bypassing the router timeout entirely.
  Both still require the **other** person `not_home` before Away sets — a
  departure can't be misattributed to the wrong resident.
- `person → home` sets `house_mode → Home` immediately and disarms Alarmo —
  digital arrival is instant once a tracker sees the phone.
- `device_tracker.windows_home_assistant` (Adam's PC) is deliberately NOT a
  person tracker: it holds `home` while the PC is awake, which would silently
  block Away-detection whenever the PC is left on. Available as a soft signal only.
- GPS accuracy is ~100 m — tight arrival zones are meaningless; physical
  sensors (courtyard PIR, doorbell cam) are the true "someone is at the door" layer.

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

## 4. Sensor location map & trust model

**The core rule that prevents false alarms:** a camera sensor can only be an
*independent* alert trigger if its field of view cannot see public space, or a
non-detection zone is painted in the Reolink app excluding it. A camera that
sees the street will classify passersby as "person" — it is only ever a
**corroborating** sensor, never a trigger on its own. The same discrimination
problem applies, reversed, to indoor sensors (cannot tell resident from
visitor — never alert triggers).

Three trust classes:

| Class | Rule | Sensors |
|---|---|---|
| **Independent trigger** | Outdoor-facing AND street-excluded (PIR aimed at private space, or camera with painted zone) | `motion_7` (courtyard PIR), `front_door_person` (zone painted) |
| **Corroboration-only** | Sees public space, no painted zone — only fires alongside an independent trigger | `doorbell_person_2` (sees street — gated on `motion_7` ±20s), `front_balcony_person` (sees street — not a trigger at all) |
| **Occupancy only** | Indoor — cannot discriminate resident vs visitor | `front_entry`, `den_motion`, `kitchen`, all interior PIRs |

### Outdoor sensors — field of view

| Entity | Type | Location | Sees public space? | Used in alerts? |
|---|---|---|---|---|
| `binary_sensor.motion_7` | PIR | Front courtyard | No — aimed at courtyard | ✅ Independent trigger + floodlight |
| `binary_sensor.front_door_person` / `_pet` | Camera class | Front door (high mount) | Porch only + sliver of neighbour driveway — street **excluded by painted zone** | ✅ Independent trigger + floodlight |
| `binary_sensor.doorbell_person_2` / `_pet_2` | Camera class | Doorbell (head height) | **Yes — wide fisheye, whole street + parked cars; barely sees walkway** | ⚠️ Corroboration only — gated on `motion_7` ±20s for alert/floodlight/stamp |
| `binary_sensor.front_balcony_person` / `_pet` / `_motion` | Camera | Front balcony | **Yes — ~80% street/footpath; sees front gate + courtyard edge** | ❌ Never a trigger (stats + watchdog only) |
| `binary_sensor.side_person` / `_pet` / `_motion` | Camera | Side of house | No — narrow side walkway view, verified private | Correlated detection + night eval |
| `binary_sensor.rear_person` / `_pet` / `_motion` | Camera | Rear | No — backyard only (neighbour rooflines over fence) | Correlated detection + night eval |
| `binary_sensor.camera1_person_3` / `_pet_2` | Camera | Patio | No — backyard only (⚠️ cam offline) | Correlated detection + night eval |
| `binary_sensor.garage_person` / `_pet` | Camera | Garage interior | No | Away person alerts + night eval |
| `binary_sensor.hue_outdoor_motion_sensor_1_motion` | PIR | Backyard (shed side) | No | Night eval stamps (`last_pir_shed`) |
| `binary_sensor.hue_outdoor_motion_sensor_2_motion` | PIR | Backyard (house side) | No | Night eval stamps (`last_pir_house`) |
| `binary_sensor.garden_motion` | PIR | Garden | No | — |

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

### Voice + TTS (bypasses the cast script)

| Piece | Detail |
|---|---|
| `tts.home_assistant_cloud` | Nabu Casa TTS — used for the alarm-pending announcement on `media_player.kitchen_display`. TTS leaves the display on a black cast screen — every TTS call site ends with `media_player.turn_off` to return it to ambient |
| `switch.alarm` ("Alarm") | Template switch exposed to Google. State mirrors Alarmo (self-resets after each command). `turn_off` → `script.alarm_cancel`. Voice arming deliberately not supported |
| `script.alarm_cancel` ("Alarm Cancel") | The voice flow: only valid while `pending`. First call → "Are you sure? Say 'turn off the alarm' again within 30 seconds" + opens `alarm_cancel_confirm`/`timer.alarm_cancel_confirm_window`. Second call inside the window → disarm + "Alarm disarmed". A triggered or fully armed alarm can never be voice-cancelled |
| `Security - Alarm cancel confirm window expired` | Clears the confirm flag when the window lapses — a stale request can't be confirmed against a future pending |
| Google Assistant | Via Nabu Casa cloud. **Native phrases**: "ok google, **turn off the alarm**" (×2 = request + confirm), "ok google, **turn on alarm cancel**" (scene fallback). Arbitrary custom phrases ("cancel alarm") would need a Google Home routine — not currently configured |

---

## 6. Automation logic reference

### Front door — primary path

**`Security - Front Door Person Alert`** (`security_front_door_person_alert`)

Triggers (OR): `front_door_person`, `doorbell_person_2`, `motion_7`. Cooldown: 60s.
**`doorbell_person_2` is corroboration-gated**: its event only passes when
`motion_7` is on or fired within 20s (it sees the street, no zone painted).
Same gate applied to the floodlight `detected` trigger and the doorbell
night-eval stamp. Restore it as an independent trigger once a non-detection
zone is painted in the Reolink app.

| Condition | Action |
|---|---|
| `house_mode` ∈ {Away, Holiday} | Snapshot → `www/frontdoor-snapshot.jpg` → push to Pixel 6 + "View Live Feed" (Reolink deep link) |
| `guest_mode` on | Quiet push — no speaker sound |
| `Sleep` + Adam & Mads home | `person-alert.wav` @ 1.0 → bedroom speaker |
| `Home` + `den_occupied` on | `person-alert.wav` @ 1.0 → den speaker |
| `Home` + den empty | Parallel → den + kitchen + bedroom |

`mode: single`. Volumes at **1.0 during testing** — retune after.

**Departure suppression:** all speaker branches + the guest push are gated on
`input_datetime.last_house_departure` — no chime for 120s after a detected
departure (a resident leaving shouldn't alert on themselves). Unknown/ambiguous
direction still alerts.

**`Front Door - Person Floodlight`** — on when any of `front_door_person`,
`front_door_pet`, `doorbell_person_2`, `motion_7` fires; off only when ALL clear.
`mode: restart`.

### Direction detection — arrivals vs departures

**`Security - Door direction detection`** (`security_door_direction_detection`)

When a door opens, classifies by which side saw activity in the prior 60s:

| Door | Interior evidence | Exterior evidence | Verdict |
|---|---|---|---|
| Front door | `front_entry` PIR | `motion_7`, `front_door_person`, `doorbell_person_2` | interior-first → **departure**; exterior-first → **arrival** |
| Garage roller | `motion_3`, `garage_person`, `garage_vehicle`, `garage_motion` | *(none — roller is interior-side)* | interior → **departure** (covers car AND on-foot exits); nothing → **arrival** |

Only runs in `Home` / `Sleep` / `None` — in `Away`, interior-activity-then-door is
an intruder leaving, not a resident departing, so nothing is stamped.

Stamps `input_datetime.last_house_departure` / `last_house_arrival`. Used by the
front-door alert's 120s departure suppression. **Known gap:** leaving on foot via
the garage side door can't be detected (dead sensor `door_sensor_12`) — such a
departure won't stamp and the person may chime themselves crossing the courtyard.

### Front lights

| Automation | Behaviour |
|---|---|
| `Lighting - Front lights (on)` | Sunset −15min → `light.front_3` at **80% / 3000K** (warm ambient scene) |
| `Lighting - Front lights (off)` | 23:59 → off (skipped in Holiday) |
| `Motion Light Toggle - Sunset/Sunrise` | Arms `input_boolean.front_motion_lights` at sunset −30min; disarms at sunrise +60min + sweeps leftover lights |
| `Motion Lights - Front turn on` | `motion_7` while toggle armed → `scene.create` snapshot → `light.front_3` at **100% / 5000K** (bright white pop) |
| `Motion Lights - Front turn off` | PIR clear 2min → `scene.turn_on` restores snapshot (30s transition); handles stale snapshots across the scheduled ON/OFF boundaries |
| `Holiday - Front light on/off` | Holiday-only version of the ambient scene |

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

**Alarmo chain** — `Alarm pending` (entry delay, 60s for armed_away) → `Alarm
triggered` (all floodlights + den 100% + "ALARM TRIGGERED" push to both phones) →
`Disarm` / `Re-arm` from notification actions → `Arm verification`.

**Pending window (armed_away entry):** 60s. On `alarmo → pending`:

- `Security - Alarm pending announcement` — primes the kitchen speaker with a
  silence mask (suppresses Google's cold-start beep), then repeats "Warning.
  Alarm pending." via TTS every ~4s until pending ends, and turns the display
  off afterward so it returns to ambient (gated by `enable_alarm`)
- `Night Security - Alarm pending` — waits 10s (so a resident exit that
  auto-disarms doesn't alert), then pushes a Disarm action to both phones
- Voice cancel: "ok google, activate cancel alarm" → `script.cancel_pending_alarm` →
  disarms only while pending
- If a person's tracker flips `home` during the window, `Presence Detection -
  Home` disarms — the pending period is the grace for GPS to catch up with a
  physically-arrived resident

**Sensor health watchdog** — `Security - Sensor health watchdog` fires if any
critical perimeter/detection/camera entity is `unavailable` for >10 min, plus a
daily 09:00 sweep listing everything still dead (catches entities that died
before the watchdog existed). So a dead contact can't silently open a gap.

Also: `PIR stamp`, `Shed door opened`, `Entry with person sighting`,
`Person inside garage`, `Morning motion ends Sleep`.

### Notifications

- `Garage Door - Arming Beep` — `arm-click.wav` on den speaker, roller door open/close.
- `Notification - Front Gate` / `Doorbell` / `Garage Door` — pushes.
- `PC Notification - *` — desktop variants.
- `Holiday - *` — light simulation (presence mimicry while away).

---

## 7. Edge cases & gotchas

1. **A camera that sees public space is never an independent trigger** — it
   will classify passersby. Either paint a Reolink non-detection zone (front
   door cam: done) or gate the sensor behind a private-space corroborator
   (doorbell: gated on courtyard PIR). This is the #1 false-alarm source.
2. **Pixel motion sensors are unreliable for alerts** — wind and through-glass
   visibility cause false positives. Only classified person/pet sensors and
   outdoor PIRs drive alerts.
3. **High-mounted cameras need face-ish views** for person class — cover gaps
   with a second (lower) camera or an outdoor PIR.
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
12. **Physical arrival precedes digital presence** — GPS can lag minutes behind
    someone walking to the door. The pending window + direction classifier are
    the bridge: the door contact + courtyard PIR detect arrival physically while
    trackers catch up. In Away mode a resident arriving gets: pending → phone
    push with Disarm → tracker flips home → auto-disarm.
13. **Presence is fail-safe toward "home"** — any-tracker-home wins, so the
    system errs toward not alarming on residents; the corresponding risk is
    false-home if a tracker sticks (why the PC tracker was detached).
14. **Departure suppression is conservative** — 120s window, front-door alerts
    only; Away-mode pushes are never suppressed (a departure stamp can't exist
    in Away since classification doesn't run there).
15. **A dead sensor can't be told apart from a quiet sensor** — the watchdog
    covers `unavailable` state, but a physically-blocked or mis-zoned sensor
    stays "alive" while blind. Alarmo per-sensor `auto_bypass` exists as config
    if arming should tolerate dead contacts (not enabled deliberately).

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
- **Before adding any camera sensor as an alert trigger, check §4's field-of-view
  column** — if it sees public space it is corroboration-only until a
  non-detection zone is painted in the Reolink app. Update the column when zones
  change.
- **Never add deterrent actions (floodlights, sirens, brightening) to alarm
  triggers without explicit request** — alerts notify; they don't perform.
