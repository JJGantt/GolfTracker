# Unified Swing Detection — Event-Based Approach

## Motivation

The current detection system uses 3 separate state machines (FullSwingDetector, PartialDetector, PuttDetector) that gate each state on the previous one succeeding. Real-world data shows this is too restrictive — axis checks on noisy threshold-crossing samples reject most real swings before the algorithm ever sees the strong, clear signals at the peak.

The new approach detects key events **independently** and reasons about them after the fact.

## Architecture: Swings vs Putts

Swings and putts are handled by **separate visualizers** because the signals are fundamentally different:

- **Swings** (full + irregular): Large rotational magnitudes (5-15+ rad/s peaks), primary directional axis is **rotZ** for backswing/forward swing, **rotX** contributes significantly
- **Putts**: Much smaller magnitudes (~1-2 rad/s peaks), primary directional axis is **rotY**, rotZ/rotX gates that work for swings reject all putt events

Both visualizers share the same 3-detector architecture but will have independently tuned parameters and directional gates.

### Files

| File | Target data | Output |
|------|-------------|--------|
| `swing_visualize.py` | `iregular_samples/`, `full_swing_samples/` | `irregular.html`, `full_swings.html` |
| `putt_visualize.py` | `putts_samples/` | `putts.html` |

## The 3 Independent Event Detectors

Each detector scans the entire signal independently. No event depends on another.

### 1. Setup Events
Player standing still in correct orientation, about to swing/putt.
- Pitch in [-25deg, 0deg], roll in [85deg, 135deg]
- rotMag below ceiling (1.0 rad/s) sustained for at least 0.20s
- Brief spikes up to 0.06s tolerated without resetting — handles minor wrist fidgeting
- Output: green shaded bands from stability start to end

### 2. Backswing Top Events
The moment the backswing reverses into the forward swing. rotMag drops to a local minimum (club momentarily still at the top) then rises again.

**Detection:**
- `scipy.signal.find_peaks` on **inverted** rotMag finds valleys (prominence ≥ 0.15, distance ≥ 15 samples)
- Valley rotMag must be < 1.5
- **Area-under-curve** computed for each rotation axis (X, Y, Z) in a 0.2s window before and after the valley — this captures direction and commitment of motion on each side

**Directional gate (swings):** rotZ area must be < -0.1 before the valley and > +0.1 after (backswing → forward swing direction reversal). This gate cut ~70% of false positives.

**Putt version:** Currently uses same swing gates as starting point (to be tuned — putts use rotY not rotZ).

- Note: follow-through deceleration also triggers this (resembles BS top). Final swing determination will use event ordering — that's for later.
- Output: vertical dashed lines (blue) with area values per axis

### 3. Forward Swing Force Events
Peak rotation during the forward swing — the moment of maximum rotational force.

**Detection:**
- `scipy.signal.find_peaks` on rotMag (prominence ≥ 1.0, distance ≥ 15 samples)
- **Area-under-curve** computed for each axis in a 0.2s window before and after the peak

**Directional gates (swings):**
- rotZ area > +0.1 before peak and < -0.1 after (forward swing → deceleration)
- rotX area < -0.1 before peak

**Putt version:** Currently uses same swing gates as starting point (to be tuned — putt FS magnitudes are much smaller and use different axes).

- Output: vertical solid lines (red) with peak magnitude and area values per axis

## How Area-Under-Curve Works

Instead of checking a single sample's sign (fragile with noise), we sum axis values × dt across a time window. This gives:
- **Sign** = direction of rotation (positive or negative area)
- **Magnitude** = how committed the motion is in that direction
- More robust than single-sample checks because it integrates over many samples

Example for a swing BS top:
- 0.2s **before** valley: rotZ area ≈ -0.4 (club rotating backward)
- 0.2s **after** valley: rotZ area ≈ +0.4 (club rotating forward)

## Sample Data Notes

- **Putt data** (`putts_samples/`): 100Hz new format with real sensor timestamps
- **Swing data** (`iregular_samples/`, `full_swing_samples/`): ~50Hz old format with index-based timestamps
- Both visualizers preserve actual sample spacing — the x-axis represents real time

## Current Results

### Swings (`swing_visualize.py`)
- Irregular: ~11 setups, ~7 BS tops, ~6 FS peaks
- Full swings: ~7 setups, ~5 BS tops, ~5 FS peaks
- Directional gates are well-tuned — very few false positives

### Putts (`putt_visualize.py`)
- 29 setups, 4 BS tops, 0 FS peaks
- BS tops and FS peaks need putt-specific tuning (swing gates reject putt signals)
- **Next step**: adjust directional gates to use rotY instead of rotZ, lower prominence/magnitude thresholds

## File References

### Existing Python code (NOT MODIFIED)
- `putts_samples/detect.py` — `parse_csv()`, orientation constants, impact detection. Imported by all visualizers.
- `putts_samples/visualize.py` — putt visualization with state machine events
- `iregular_samples/visualize.py` — irregular/partial swing visualization
- `full_swing_samples/visualize.py` — full swing visualization

### Existing sample CSVs
- `putts_samples/motion_test_1771471188.csv` (100Hz)
- `iregular_samples/motion_test_*.csv` (6 files, ~50Hz)
- `full_swing_samples/motion_test_*.csv` (5 files, ~50Hz)

### Existing Swift detectors (NOT MODIFIED)
- `GolfWatch Watch App/Services/FullSwingDetector.swift`
- `GolfWatch Watch App/Services/PartialDetector.swift`
- `GolfWatch Watch App/Services/PuttDetector.swift`
- `GolfWatch Watch App/Services/SwingDetectionManager.swift`

## Usage
```bash
cd /path/to/GolfTracker

# Swings (irregular + full)
python3 unified_detection/swing_visualize.py

# Putts
python3 unified_detection/putt_visualize.py
```
