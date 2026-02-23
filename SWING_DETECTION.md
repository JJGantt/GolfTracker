# Swing Detection Feature

This document describes the automatic swing detection system implemented in `SwingDetectionManager.swift` (Watch only).

---

## Detection Modes

The system supports three modes via the `DetectionMode` enum:

| Mode | Description |
|------|-------------|
| `off` | Detection disabled |
| `naiveDetect` | Fires when rotation AND acceleration both exceed configurable thresholds simultaneously |
| `smartDetect` | Runs putt shape detection in parallel with naive detect on every sample |

**Persistence:** `detectionMode` is saved to `UserDefaults` key `"swingDetectionMode"` on every change and restored at app init. The mode survives app relaunches.

---

## Sampling

### Device Motion (~50Hz)

- Requested at **100Hz** (`updateInterval = 0.01`)
- CoreMotion delivers approximately **~50Hz** in practice (~20ms between samples)
- All timing uses `data.timestamp` (CMDeviceMotion sensor time — seconds since device boot), NOT wall clock. This is critical: CMBatchedSensorManager batches arrive in bursts, so wall-clock `Date()` cannot be used for duration accumulation.
- 15 channels per sample: userAccel XYZ+Mag, rotation XYZ+Mag, gravity XYZ, pitch/roll/yaw

### Raw Accelerometer (800Hz)

- **Primary:** `CMBatchedSensorManager` @800Hz — batched delivery once/second, runs continuously when smart detect is active
- **Fallback:** `CMMotionManager.startAccelerometerUpdates` @100Hz on devices that don't support `CMBatchedSensorManager`
- Shares a single stream that feeds both the putt impact detector and the manual recording buffer
- `CMBatchedSensorManager` requires an `HKWorkoutSession` in `.running` state to deliver data during screen-off

### HKWorkoutSession Dependency

When `startMonitoring()` is called and no workout is already active, `WorkoutManager.shared.startWorkout()` is called. The batched accelerometer is not started until the `onSessionRunning` callback fires — i.e., CMBatchedSensorManager only starts once the workout session is `.running`.

### Core Motion Authorization

- `checkAndRequestMotionAuthorization()` is called at app init and every time the scene becomes active
- If authorization is `.denied` or `.restricted`, the watch app shows a blocking `MotionAuthDeniedView` instead of the normal content view
- `.notDetermined` triggers the system permission dialog via a brief `CMMotionActivityManager.startActivityUpdates` call

### Extended Runtime Session

- `WKExtendedRuntimeSession` is started when monitoring begins (or recording begins)
- Required to deliver haptic feedback when the watch screen is off
- `playFeedback()` is called directly from `motionQueue` (background thread) — NOT dispatched to main thread. Dispatching to main causes deferred haptics when the wrist is down.
- Auto-restarts when expiring

---

## Naive Detect

**Location:** `runNaiveDetect(rMag:uaMag:now:)` — called for `naiveDetect` mode AND in parallel during `smartDetect`

### Logic

1. Rotation above threshold opens a detection window
2. Within that window, acceleration must also exceed its threshold
3. Both must be above threshold for their respective required durations
4. When both conditions are met simultaneously → `detectSwing()` fires
5. 0.5s debounce between detections

### Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `accelerationThreshold` | 2.0 G | Min userAccelMag to trigger |
| `accelTimeThreshold` | 0.0 s | Duration above accel threshold required |
| `rotationThreshold` | **1150 deg/s** | Min rotMag to trigger (converted to rad/s internally) |
| `rotationTimeThreshold` | 0.0 s | Duration above rotation threshold required |

Note: `rotationThreshold` is stored in **degrees/second** and converted to rad/s via `rotationThreshold * .pi / 180.0` before comparison with CMDeviceMotion rotation data.

---

## Smart Detect — Routing

In `smartDetect` mode, **every device motion sample** triggers both:
1. `runPuttDetection(...)` — the putt shape state machine
2. `runNaiveDetect(...)` — the naive threshold detector

There is no club-gating. Putt detection and naive detection run simultaneously for all clubs. The naive detect acts as a safety net for full swings while putt detection runs its more precise shape algorithm.

---

## Smart Detect — Putt Detection

**Location:** `runPuttDetection(pitch:roll:rotX:rotY:rotZ:rotMag:uaMag:now:sensorTime:)`

### State Machine

5-state linear machine. Timing uses `sensorTime` (CMDeviceMotion sensor timestamp), not wall clock.

```
idle
 │ inBounds (pitch & roll in range) AND rotMag ≤ ceiling (0.15 rad/s)?
 ▼
accumulating
 │ Must stay inBounds AND underCeiling
 │ When sensorTime - stableStartTime ≥ puttMinDurationS (0.3s):
 ▼
qualified
 │ Must stay inBounds
 │ When rotMag leaves ceiling:
 │   check rotY > 0 AND |rotY| > |rotX| AND |rotY| > |rotZ| (RotY dominant?)
 │   NO → reset to idle
 ▼
inBackstroke
 │ Track running max rotY (most positive value)
 │ Capture pre-stroke orientation from 50ms lookback buffer
 │ Transition: rotY ≤ 0 (direction change = top of backswing)
 │   Record bsTopPitch, bsTopRoll
 ▼
inForwardStroke
 │ Track running min rotY (most negative value), its rotX, rotZ, and sensorTime
 │ Transition: rotY ≥ 0 (forward stroke complete)
 │   Evaluate:
 │     ratio = |fsPeakRotY| / |bsPeakRotY|
 │     rotYDom = |fsPeakRotY| > |fsPeakRotX| AND |fsPeakRotY| > |fsPeakRotZ|
 │     rzOk   = |fsPeakRotZ| < puttRotZCeiling (1.5 rad/s)
 │     ratOk  = ratio in [puttMinFSBSRatio (1.25), puttMaxFSBSRatio (4.0)]
 │   ALL pass → SHAPE DETECTED: build ShapeEvent with fsPeakTime
 │   ANY fail → reset to idle
 ▼
SHAPE DETECTED
 (awaits CONTACT_CONFIRMED via bidirectional correlation — see below)
```

Any bounds/ceiling violation or failed check resets to **idle**.

### State Descriptions in UI

`puttStateDescription` (shown in AccelTestView as "State: ..."):

| Internal State | UI Label |
|----------------|----------|
| `.idle` | "idle" |
| `.accumulating` | "setup" |
| `.qualified` | "ready" |
| `.inBackstroke` | "backstroke" |
| `.inForwardStroke` | "forward" |

### Putt Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `puttPitchMinDeg` | -25.0° | Pitch range min for orientation gate |
| `puttPitchMaxDeg` | 0.0° | Pitch range max |
| `puttRollMinDeg` | 85.0° | Roll range min |
| `puttRollMaxDeg` | 135.0° | Roll range max |
| `puttSetupRotMagCeiling` | 0.15 rad/s | Max rotMag during setup accumulation |
| `puttMinDurationS` | 0.3 s | Min time in stable setup before exit allowed |
| `puttMinFSBSRatio` | 1.25× | Min |FS rotY| / |BS rotY| (forward must be larger than backstroke) |
| `puttMaxFSBSRatio` | 4.0× | Max |FS rotY| / |BS rotY| |
| `puttRotZCeiling` | 1.5 rad/s | Max |RotZ| at forward stroke peak (rejects off-axis motions) |

All parameters are adjustable in AccelTestView when smart detect is selected.

### Orientation Rationale

The ranges [-25°, 0°] pitch / [85°, 135°] roll cover the putting address wrist position. Observed from 7 putt recordings:
- Putting address: pitch -6.6° to -10.7°, roll 113.0° to 116.7°
- Full swing address: pitch -14.7° to -18.4°, roll 97.4° to 102.9°

Both stroke types fall within these broad ranges. The RotY dominance check at setup exit is the key discriminator against non-putt motions.

### RotY Dominance — Physical Basis

For a putting stroke, the primary wrist rotation is around the arm's long axis (RotY in device frame), producing the characteristic pendulum arc. The dominance check (`|rotY| > |rotX|` and `|rotY| > |rotZ|`) ensures the motion that exits setup is actually a rotational putt stroke, not a bump or lift. Backstroke is **positive RotY**; forward stroke is **negative RotY**.

---

## Contact Detection (Impact via Raw Accel)

**Location:** `runImpactDetection(z:t:)` — runs on `rawAccelQueue`, called from `feedRawAccelSample()`

Contact detection runs whenever `rawAccelRunningForPuttCapture == true`, which is true whenever `detectionMode == .smartDetect`.

### Impact State Machine

4-state machine on the raw Z accelerometer channel:

```
stable
 │ Accumulate stabilityN samples (0.075s window at 800Hz ≈ 60 samples)
 │ Check: trailing std dev of history (all but last) < 0.025
 │ Compute baseline = mean of last baselineN samples (10ms ≈ 8 samples)
 │ Guard: baseline ∈ [0.20, 0.65] (putting orientation Z range)
 │ When current Z > baseline + 0.050:
 ▼
bump
 │ Track max Z (impactBumpPeakZ)
 │ Timeout: maxImpN samples (0.150s)
 │ When Z < baseline - 0.150:
 ▼
trough
 │ Track min Z (impactTroughMin)
 │ Timeout: maxImpN samples
 │ When Z > baseline + 0.120:
 ▼
peak
 │ Track max Z (impactReboundMax)
 │ Accumulate settleN samples (0.015s ≈ 12 samples)
 │ Timeout: maxImpN samples
 │ When std dev of settleN < 0.030:
 ▼
CONTACT DETECTED
 → Build ContactEvent with bumpT, baseline, bumpPeakZ, troughMin, reboundPeak
 → Scan shapeEvents for a match (see Bidirectional Correlation)
 → Transition back to stable (using settle buffer as new history)
```

### Baseline Guard Rationale

The `[0.20, 0.65]` baseline range corresponds to the raw Z accelerometer value when the watch is in a putting address orientation (wrist slightly supinated, face roughly downward-facing). At baseline Z ≈ -0.97 (screen face-up, user looking at watch), the guard rejects. `STABLE_REJECT` entries with baseline ≈ -0.97 in logs are **expected** — they fire between putts when the user raises their wrist to look at the screen.

### Impact Parameters (not user-tunable)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `impactStabilityWindowSec` | 0.075 s | Duration of quiet required before impact can register |
| `impactBaselineWindowSec` | 0.010 s | Window at end of stable period used for baseline mean |
| `impactSettleWindowSec` | 0.015 s | Window to confirm re-stabilisation after rebound |
| `impactMaxImpulseSec` | 0.150 s | Max time from bump start to settle (timeout) |
| `impactStableStdThresh` | 0.025 | Max Z std to qualify as stable |
| `impactBaselineMin` | 0.20 | Min plausible baseline Z (putting orientation) |
| `impactBaselineMax` | 0.65 | Max plausible baseline Z |
| `impactBumpThresh` | 0.050 | Min rise above baseline for contact |
| `impactTroughThresh` | 0.150 | Min drop below baseline for trough |
| `impactPeakThresh` | 0.120 | Min rise above baseline for rebound |
| `impactSettleStdThresh` | 0.030 | Max Z std to confirm settled after rebound |

---

## Bidirectional Correlation (Shape + Contact → Detection)

**Location:** `shapeEvents` / `contactEvents` arrays, protected by `eventsLock: NSLock`

Detection only fires when **both** a shape event and a contact event are confirmed within the correlation window. Shape alone or contact alone does not fire `detectSwing()`.

### Event Structs

**`ShapeEvent`** (built on motionQueue when putt shape qualifies):
- `fsPeakT`: sensor time of forward stroke peak rotY
- Pre-stroke pitch/roll, BS peak rotX/Y/Z, BS top pitch/roll, FS peak rotX/Y/Z
- `rotYDom`, `rzOk`, `ratOk` — shape evaluation results
- `uaMag`, `rotMag` — passed to `detectSwing()` on confirmation
- `matchedContactT` — set when matched

**`ContactEvent`** (built on rawAccelQueue when impact confirmed):
- `bumpT`: sensor time of the bump onset
- `baseline`, `bumpPeakZ`, `troughMin`, `reboundPeak`
- `matchedFSPeakT` — set when matched

### Correlation Logic

**Correlation window:** contact bump must occur within `[-75ms, +25ms]` of the shape's `fsPeakT`.

When a **shape** completes (on `motionQueue`):
1. Scan `contactEvents` backwards for a `bumpT` within the window
2. If found → `contactEvents[i].matchedFSPeakT = peakT`, `ev.matchedContactT = bumpT` → call `detectSwing()`

When a **contact** completes (on `rawAccelQueue`):
1. Scan `shapeEvents` backwards for an `fsPeakT` within the window
2. If found → `shapeEvents[i].matchedContactT = bumpT`, `cEv.matchedFSPeakT = sEv.fsPeakT` → call `detectSwing()`

Both paths are protected by `eventsLock`. The `contactWindowBefore = 0.075s` / `contactWindowAfter = 0.025s` window allows for the inherent ~50ms latency between the 50Hz shape peak and the 800Hz batch arrival.

---

## Auto-Capture Buffers & Data Transfer

### Circular Buffers

Two 5-second rolling buffers are maintained whenever `rawAccelRunningForPuttCapture` is true:

- **`puttEventMotionBuffer`**: device motion samples (@~50Hz, up to ~250 samples), on `motionQueue`
- **`puttEventRawAccelBuffer`**: raw accel samples (@800Hz, up to ~4000 samples), protected by `puttBufferLock`, on `rawAccelQueue`

### On Reset (any attempt that got past `qualified`)

`sendPuttAttemptData(outcome:finalState:)` is called on reset/detection:
- Sends device motion CSV (`putt_event_*.csv` or `putt_fail_*.csv`) to iPhone via `WCSession.transferFile`
- Diagnostic log included in file metadata
- For **detected** putts: raw accel CSV is sent **deferred** — waits until 1s past the contact window has been buffered, then sends the snapshot (avoids the batch latency problem)
- For **failed** putts: raw accel CSV sent immediately with current buffer

### Continuous Log

A text log (`continuous_log_*.txt`) accumulates the entire time smart detect is active:
- Written from both `motionQueue` (shape events) and `rawAccelQueue` (contact/batch events)
- Thread-safe via `continuousLogLock: NSLock`
- Log entries: `[SHAPE ...]`, `[CONTACT_BUMP ...]`, `[CONTACT ...]`, `[CONTACT_CONFIRMED ...]`, `[BATCH #N ...]`, `[RAW_TICK ...]`, `[RESET reason=...]`
- Sent to iPhone when smart detect is disabled or monitoring stops
- `continuousLogCount` published for UI display in AccelTestView

### Diagnostic Log

Per-attempt log of shape state transitions (from `diagLog()`), sent to iPhone via WatchConnectivity message (`type: "puttDiagnosticLog"`) for any attempt that got past setup qualification. Used for debugging transition failures.

---

## Smart Detect — Full Swing Detection

**Location:** `full_swing_samples/visualize.py` (Python analysis/simulation)
**Status:** Shape detection algorithm in active development — not yet ported to Swift.

Full swings already fire naive detect reliably. The goal of this state machine is to add a **setup qualifier + shape verification** so that:
1. False positives (arm bumps, dropping the watch, etc.) are rejected
2. Detailed characterization is possible (backswing extent, swing speed, etc.)

### Setup Orientation

From analysis of full swing recordings in `full_swing_samples/`:

| File | Pitch (approx) | Roll (approx) |
|------|---------------|---------------|
| `1767821420` | -15° to -20° | 100–106° |
| `1767821496` | -15° to -20° | 101–106° |
| `1767821580` | -15° to -22° | 99–106° |
| `1767821594` | -15° to -22° | 99–106° |
| `1767821605` | -15° to -22° | 100–108° |

**Aggregate full swing address:** pitch ≈ -15° to -20°, roll ≈ 99° to 107°.

The same broad orientation constraints [-25°, 0°] pitch / [85°, 135°] roll cover both putts and full swings.

Key difference from putting: **RotX dominates** the full swing. The backstroke produces a large positive RotX peak (~+4–6 rad/s, wrist cocking upward); the downswing produces a very large negative RotX (~-10 to -35 rad/s, wrist uncocking at impact).

### Full Swing State Machine

6-state machine modelling the physical sequence of a full golf swing:

```
idle
 │ pitch & roll in valid range AND rotMag ≤ 1.0 rad/s?
 ▼
accumulating
 │ Hold in range + under ceiling for ≥ 0.20s
 ▼
qualified
 │ rotMag leaves ceiling AND rotX > 0 AND rotX dominant (|rotX| > |rotY|, |rotX| > |rotZ|)
 ▼
inBackstroke
 │ Track running max rotX (positive peak)
 │ Transition: rotX ≤ 0 (top of backswing / direction change)
 │   Check at BS peak:
 │     bsPeakRotX ≥ 3.0 rad/s
 │     bsPeakRotY < 0
 │     bsPeakRotZ < 0
 │   Record bsPeakRotMag (reference for FS ratio check)
 ▼
inForwardStroke
 │ Track running max rotMag (fsPeakRotMag)
 │ Transition: fsPeakRotMag ≥ bsPeakRotMag × 2.0 AND current rotMag fallen back to ≤ bsPeakRotMag
 │   Check: ratio = fsPeakRotMag / bsPeakRotMag in [2.0×, 8.0×]
 ▼
postImpact
 │ Wait for rotX to go positive (follow-through arm rise)
 │ Then: rotX crosses 0 from positive → negative (follow-through deceleration)
 ▼
STROKE DETECTED
```

Any failed check at any state resets to **idle**.

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `SWING_SETUP_ROT_MAG_CEILING` | 1.0 rad/s | Max rotMag during setup accumulation |
| `SWING_MIN_DURATION_S` | 0.20 s | Min quiet time in address before backswing can begin |
| `SWING_BS_ROT_X_MIN` | 3.0 rad/s | Min rotX at BS peak to confirm actual backswing |
| `SWING_FS_ROTMAG_RATIO_MIN` | 2.0× | Min FS rotMag peak relative to BS rotMag |
| `SWING_FS_ROTMAG_RATIO_MAX` | 8.0× | Max FS rotMag peak relative to BS rotMag |

Pitch/roll orientation bounds are shared with putt detection: pitch [-25°, 0°], roll [85°, 135°].

### Analysis Tooling

**Location:** `full_swing_samples/visualize.py`

Stitches all CSV recordings into a single timeline (1s gap between files) and produces an interactive HTML plot (`stitched.html`) showing:
- RotX (primary trace, bold blue), RotY, RotZ, RotMag
- Pitch / Roll with valid-range shading
- UserAccel X/Y/Z / Mag
- Annotated state machine events with per-condition pass/fail labels

Imports parse helpers and orientation constants from `putts_samples/detect.py`. Full-swing-specific constants override locally at the top of the script.

### Known Issues / Open Questions

- **postImpact rotX crossing**: Still being validated against data — need to confirm the follow-through rotX pattern is consistent across all recordings.
- **Parameters not yet tuned to real detections**: Current values are initial estimates from visual inspection.
- **Not yet ported to Swift**: All logic currently in Python simulation only.
- **No raw accel for these samples**: Full swing samples contain only 50Hz device motion; impact contact detection is not available for these recordings.

---

## CSV Analysis — Putt Rotation Patterns

**Source:** 7 putt recordings in `/Users/jaredgantt/Projects/SwingDetect/CSVs/putts/`

Analysis scripts in `/Users/jaredgantt/Projects/SwingDetect/`:
- `proper_analysis2.py` — main analysis using actual CSV timestamps (authoritative)
- `find_all_setups.py` — finds all valid setup periods per file

### Setup Periods

| File | Setup Start | Setup End | Duration | Ref Pitch | Ref Roll |
|------|-------------|-----------|----------|-----------|----------|
| `512` | 3.47s | 6.76s | 3.29s | -9.2° | 113.0° |
| `529` | 3.49s | 7.06s | 3.57s | -10.7° | 116.0° |
| `543` | 1.69s | 4.82s | 3.13s | -7.9° | 116.3° |
| `566` | 2.06s | 5.80s | 3.73s | -9.0° | 116.7° |
| `583` | 2.34s | 5.05s | 2.71s | -6.6° | 115.1° |
| `602` | 2.25s | 4.78s | 2.53s | -7.5° | 116.5° |
| `613` | 0.84s | 4.46s | 3.61s | -10.1° | 113.8° |

**Aggregate:** Pitch: -6.6° to -10.7°. Roll: 113.0° to 116.7°.

### Backstroke / Forward Stroke Analysis

| File | BS RotY | BS RotMag | FS RotY | FS RotMag | FS/BS Ratio |
|------|---------|-----------|---------|-----------|-------------|
| `512` | +0.675 | 0.700 | -1.476 | 1.730 | 2.47× |
| `529` | +0.681 | 0.735 | -1.380 | 1.724 | 2.35× |
| `543`* | +0.280 | 0.280 | -0.598 | 0.639 | ~2.28× |
| `566` | +0.832 | 0.945 | -1.954 | 2.330 | 2.47× |
| `583` | +0.534 | 0.600 | -1.114 | 1.306 | 2.18× |
| `602` | +0.603 | 0.630 | -1.291 | 1.451 | 2.30× |
| `613` | +0.770 | 0.845 | -1.458 | 1.671 | 1.98× |

*File 543 is a very gentle ("tiny") putt.

### Key Findings

**1. Dominant rotation axis: RotY**
RotY is dominant in both backstroke and forward stroke. |RotY/RotX| ratio at peak ranges from 1.4× to 4.2× (BS) and 1.4× to 2.0× (FS).

**2. Consistent sign pattern**
- Backstroke: RotY **positive**, RotX **positive**
- Forward stroke: RotY **negative**, RotX **negative**

**3. Forward stroke always larger than backstroke**
FS/BS |RotY| ratio: **1.98× - 2.47×** (mean 2.29×). Current `puttMinFSBSRatio = 1.25` is a comfortable margin below the smallest observed (1.98×). Current `puttMaxFSBSRatio = 4.0` guards against one-directional spikes.

**4. RotZ ceiling**
RotZ at peaks is small relative to RotY. `puttRotZCeiling = 1.5 rad/s` rejects motions where the off-axis rotation is too large.

---

## Testing Infrastructure

**Location:** `GolfWatch Watch App/Views/AccelTestView.swift`

**Access:** Watch Home Page > Motion Test button

Real-time UI displaying:
- Live acceleration magnitude and X/Y/Z components
- Rotation rate magnitude and components
- Device attitude (pitch, roll, yaw)
- Gravity vector
- Min/max tracking with freeze/reset
- **Putt state machine state** ("State: idle/setup/ready/backstroke/forward")
- Continuous log entry count

Controls:
- Detection mode picker (Off / Naive / Smart)
- Naive mode: adjust accel/rotation thresholds and time windows
- Smart mode: adjust all putt detection parameters
- Record full motion sessions to CSV

### Motion Data Recording

**Dual-rate recording:**
- Device Motion at ~50Hz (requested 100Hz): 15 channels
- Raw Accelerometer at 800Hz: 4 channels (raw accel XYZ + mag)

**Data Flow:**
1. Watch records during session
2. `stopRecording()` drains `rawAccelQueue` then `motionQueue` to capture all in-flight samples
3. CSV exported via `WCSession.transferFile` to iPhone
4. iPhone saves to `Documents/MotionTests/`
5. Files viewable/shareable in iPhone app's "Tests" tab

---

## Integration with Round Tracking

**Location:** `GolfWatch Watch App/Views/ActiveRoundView.swift`

**User flow during play:**
1. Detection mode must be enabled (set in Motion Test view, persisted)
2. Selected club is pushed to `SwingDetectionManager.selectedClubTypeName`
3. When a swing is detected (`lastDetectedSwing` set):
   - Watch vibrates (haptic: `.click` + `.notification`)
   - Cyan golf icon appears in center of button area
4. User taps the golf icon to add the detected stroke
5. Stroke recorded with GPS, club, and peak acceleration
6. Syncs to iPhone via WatchConnectivity

**Aim direction capture:**
- A blue button in the active round view lets the user set `capturedAimDirection` before a swing
- This heading is stored in `DetectedSwing.trajectoryHeading` at detection time

---

## Architecture

```
┌───────────────────────────────────────────────┐
│              Sensor Sources                   │
│                                               │
│  CMMotionManager (device motion @ ~50Hz)      │
│  CMBatchedSensorManager (raw accel @ 800Hz)   │
│  [fallback: CMMotionManager @ 100Hz]          │
└──────────────┬──────────────────┬─────────────┘
               │                  │
          motionQueue         rawAccelQueue
               │                  │
               ▼                  ▼
┌──────────────────────┐  ┌────────────────────────┐
│  processDeviceMotion  │  │  feedRawAccelSample()  │
│  - calc magnitudes    │  │  - append to buffers   │
│  - UI publish (gated) │  │  - runImpactDetection  │
│  - record if active   │  │  - deferred raw saves  │
│  - buffer for capture │  └────────────┬───────────┘
└──────┬───────────────┘               │
       │                               │
       ▼                               ▼
┌────────────────────┐      ┌─────────────────────────────┐
│  Route by mode:    │      │  Impact State Machine        │
│                    │      │  stable→bump→trough→peak     │
│  off:   nothing    │      │  On CONTACT:                 │
│  naive: naive()    │      │  - scan shapeEvents          │
│  smart: naive()    │      │  - if match → detectSwing()  │
│         putt()     │      └──────────┬──────────────────┘
└──────┬─────────────┘                 │ (eventsLock)
       │                               │
       ▼                               │
┌─────────────────────────────────┐    │
│  Putt State Machine              │    │
│  idle→accum→qualified→           │    │
│  inBackstroke→inForwardStroke    │    │
│  On SHAPE:                       │    │
│  - scan contactEvents            │    │
│  - if match → detectSwing()      │────┘
└──────────────────────────────────┘

Both paths call detectSwing() only on CONTACT_CONFIRMED.
Naive detect calls detectSwing() directly on threshold breach.

              ▼
       detectSwing()
       - 0.5s debounce
       - requires GPS location
       - sets lastDetectedSwing
       - playFeedback() from current thread (no main dispatch)
              │
              ▼
       [User taps cyan icon]
              │
              ▼
       Create Stroke with GPS, club, peakAcceleration
       Sync to iPhone via WatchConnectivity
```

### Key Files

| File | Purpose |
|------|---------|
| `SwingDetectionManager.swift` | Core: DetectionMode, naive, putt state machine, contact detection, bidirectional correlation, recording |
| `AccelTestView.swift` | Testing/calibration UI — mode picker, live values, all tunable parameters, log count |
| `ActiveRoundView.swift` | Integrates detection into play flow, pushes selected club, renders swing icon |
| `GolfWatchApp.swift` | Checks motion authorization, shows blocking `MotionAuthDeniedView` if denied |
| `WorkoutManager.swift` | Manages HKWorkoutSession — required for CMBatchedSensorManager delivery |
| `WatchConnectivityManager.swift` / `DataStore.swift` | Receive CSV files and diagnostic logs on iPhone side |
| `TestFilesView.swift` | iPhone-side motion data file management |

---

## What Works

- [x] Device motion at ~50Hz (requested 100Hz, delivered ~50Hz)
- [x] 800Hz raw accelerometer via CMBatchedSensorManager (fallback: 100Hz CMMotionManager)
- [x] Detection mode persisted to UserDefaults, survives app restart
- [x] Core Motion authorization check + blocking UI if denied
- [x] HKWorkoutSession management for screen-off CoreMotion delivery
- [x] WKExtendedRuntimeSession for screen-off haptic delivery
- [x] Haptic feedback from background thread (no deferred haptic bug)
- [x] Off / Naive / Smart detection modes
- [x] Naive detect: both accel and rotation threshold gates (1150 deg/s default)
- [x] Smart detect: putt state machine running in parallel with naive for all clubs
- [x] Putt state machine: idle → accumulating → qualified → inBackstroke → inForwardStroke
- [x] Setup qualification using sensor-time timestamps (fixes the wall-clock burst bug)
- [x] RotY dominance exit from setup
- [x] Backstroke peak tracking, transition on rotY=0 crossing
- [x] Forward stroke peak tracking, evaluation on rotY=0 return
- [x] FS/BS ratio check (1.25–4.0×)
- [x] RotZ ceiling check at FS peak (1.5 rad/s)
- [x] ShapeEvent + ContactEvent bidirectional correlation
- [x] Contact detection: stable→bump→trough→peak→CONTACT on raw Z
- [x] Baseline Z guard [0.20, 0.65] (rejects watch-looking orientation)
- [x] Detection fires only on CONTACT_CONFIRMED (shape + contact must both match)
- [x] Continuous log written during smart detect; sent to iPhone on disable
- [x] Per-attempt diagnostic log sent to iPhone for qualified attempts
- [x] Auto-capture: 5s rolling buffers of device motion + raw accel
- [x] Deferred raw accel CSV send (waits 1s past contact window for batch to arrive)
- [x] Full motion recording to dual CSV (device motion + raw accel)
- [x] CSV transfer to iPhone via WatchConnectivity
- [x] puttStateDescription updated in real time for AccelTestView
- [x] Min/max tracking with freeze/reset in AccelTestView
- [x] Simulate swing for testing in simulator
- [x] Golf icon appears when swing detected; tap to add stroke
- [x] Stroke stored with GPS, club, and peak acceleration

---

## Known Issues

### 1. CMBatchedSensorManager gaps during screen-off (active investigation)
The 800Hz batched sensor data stops arriving during screen-off periods (when the watch goes dark). This causes the contact detector to have no data during actual putts, preventing CONTACT_CONFIRMED. The continuous log shows this as large gaps between `[BATCH #N ...]` entries. The shape machine may fire correctly but contact correlation fails.

### 2. Detection requires CONTACT_CONFIRMED — no fallback for failed contacts
If the 800Hz stream has a gap at the exact moment of a putt, the shape event is built but no contact event arrives, so `detectSwing()` never fires. Currently there is no timeout-based fallback to fire on shape alone.

### 3. No intermediate haptic for state transitions
The only user feedback is the final detection haptic. No feedback when setup qualifies, when backstroke is detected, etc. User cannot tell if the state machine is progressing without watching AccelTestView.

### 4. Tiny/gentle putt handling
Very gentle putts (file 543) have FS rotY ≈ 0.598 rad/s and BS rotY ≈ 0.280 rad/s. The current `puttMinDurationS = 0.3s` setup requirement may exclude these if they're too brief. The ratio of 2.28× is within range. Needs live testing.

### 5. No debug feedback for failed shape transitions
When a state machine attempt fails (wrong rotY dominant, ratio out of range, etc.), the only record is in the continuous log or per-attempt diagnostic log sent to iPhone. There is no real-time display of why detection failed.

---

## Next Steps

- **Fix CMBatchedSensorManager screen-off delivery gap** — This is the critical blocker for production reliability. Possible approaches: investigate HKWorkoutSession state at gap times, test `WKExtendedRuntimeSession` interaction, consider shape-only fallback with configurable timeout.
- **Port full swing state machine to Swift** — Once the Python simulation validates the 6-state RotX-based machine against all sample data, implement `runFullSwingDetection()` in SwingDetectionManager.
- **Add intermediate haptic for setup qualification** — At minimum, fire a soft haptic when the machine transitions to `qualified` so the user knows they're in putting stance.
- **Collect chip shot data** — Use AccelTestView recording, analyze with new Python tooling.

---

## FS/BS Ratio — Confirmed Constraint

**Current values:** `puttMinFSBSRatio = 1.25`, `puttMaxFSBSRatio = 4.0`

Confirmed from all 7 putt recordings: the forward stroke rotation is always larger than the backstroke (1.98× - 2.47× range). Minimum of 1.25 enforces this physical constraint with margin below the smallest observed. Maximum of 4.0 prevents false positives from one-directional spike motions. These values are based on measured data.

---

## Stroke Classification Roadmap

The detection system currently handles putts via smart detect and all other clubs via naive detect. Long-term goal is full stroke characterization for every club type.

### Priority Order

1. **Fix CMBatchedSensorManager screen-off delivery** — prerequisite for reliable putt detection
2. **Full swing shape detection** — Python state machine validated, needs Swift port
3. **Chip shots** — most similar to putts, data collection next
4. **Fairway punch / half-swing** — distinguishable from full swing by backswing extent

### Chip Shot Detection

Chips differ from putts:
- **Orientation**: intermediate between putt (~115° roll) and full swing (~101° roll) — needs data to confirm
- **Motion scale**: backstroke/forward stroke larger than putt, smaller than full swing
- **Accel**: will have raw accel impact transient detectable via same contact detector
- **Overlap with putts**: use selected club to disambiguate (putter → putt logic, wedge → chip logic)

**Plan:**
1. Record chip sessions via AccelTestView
2. Analyze CSVs to characterize orientation, BS/FS rotMag, ratio, raw accel impact
3. Implement `runChipDetection()` mirroring putt state machine with chip-specific parameters
4. Route smartDetect to chip logic when wedge/short iron selected

### Full Swing / Half-Swing Classification

Full swings already fire naive detect. Once the shape machine is ported:
- Backswing extent (roll/pitch delta from setup to top): smaller delta = abbreviated swing
- Peak rotMag: correlates with swing speed
- Classification threshold (e.g., <60% backswing extent) flags as half-swing/punch

---

## Backswing Metrics

Orientation data encodes how far back the club goes — useful for both detection accuracy and coaching feedback.

### Backswing Percentage

Concept: at setup, record reference attitude. Track maximum attitude deviation during backswing. Express as percentage of a calibrated "full" backswing reference.

**Approaches:**
- **Dynamic baseline**: average the largest N backswing extents observed, drop outliers (top 3 of 20). Gives a representative "strong but not over-extended" baseline.
- **Calibrated baseline**: user records ideal swings tagged as reference; all future swings compare against this.
- **Manual reference**: user pauses at top of backswing, presses button to set 100% reference.

**Display:** percentage with color coding:
- <70%: yellow (not enough backswing)
- 70–110%: green (normal range)
- >110%: orange (over-extended)

### Stroke Speed

**Metric:** Peak userAcceleration magnitude (G) during forward stroke. Express as percentage of a baseline derived the same way as backswing extent, or show raw G-force.

---

## Swing Direction Vector

CoreMotion provides absolute orientation as `CMAttitude`. Changing the reference frame to `xMagneticNorthZVertical` and transforming the device-frame `userAcceleration` vector to world frame gives the magnetic compass heading the wrist was accelerating toward at peak forward stroke.

```swift
// Change reference frame:
motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: motionQueue) { ... }

// At FS peak, transform to world frame:
// a_world = R * a_device  (R from data.attitude.rotationMatrix)
// heading = atan2(a_world.x, a_world.y)  // degrees from magnetic north
```

For putts and chips, this closely corresponds to intended shot direction. For full swings, wrist path is arc-shaped, but peak acceleration direction still gives a strong signal for shot heading.

**Caveats:** accuracy depends on watch compass calibration; magnetic declination applies for true north.

---

## Data Collection Needed

| Stroke Type | Status | Notes |
|-------------|--------|-------|
| Putts | 7 recordings | Well characterized. Raw accel also captured. |
| Chip shots | **0 recordings** | Priority next collection. |
| Full swings | 5+ recordings (device motion only) | Orientation characterized. Shape state machine in Python. Need raw accel. |
| Half-swing / punch | **0 recordings** | Needed to characterize backswing extent. |
| Sand shots | **0 recordings** | May have unique signature. |

**Recording protocol:**
1. Open AccelTestView on Watch
2. Enable recording
3. Perform 5–10 strokes of the type being characterized
4. Stop recording and transfer to iPhone
5. Run analysis scripts in `/Users/jaredgantt/Projects/SwingDetect/` or the sample visualizers
