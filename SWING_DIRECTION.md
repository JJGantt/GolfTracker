# Swing Direction Vector

This document covers the theory and planned implementation for deriving shot heading from Watch motion data during a golf swing — without requiring the user to manually set an aim direction.

---

## The Core Problem

For putts and chips (approximately linear strokes), the acceleration vector at peak forward stroke points closely along the shot direction. For full swings, this breaks down because the wrist is traveling in a rotational arc, and the acceleration vector is dominated by **centripetal force** pointing inward toward the body's rotation axis — not toward the target.

The solution is to separate the centripetal and tangential components of the acceleration vector mathematically.

---

## Step 1: Rotation Matrix Transform (Device Frame → World Frame)

`CMAttitude` provides a 3×3 rotation matrix `R` encoding the device's current orientation. Each row describes where one of the world frame's axes falls in device space. To transform any device-frame vector into world frame:

```
a_world = R × a_device
```

Expanded:
```
worldX = R.m11*ax + R.m12*ay + R.m13*az   // magnetic east
worldY = R.m21*ax + R.m22*ay + R.m23*az   // magnetic north
worldZ = R.m31*ax + R.m32*ay + R.m33*az   // up (against gravity)
```

This works for any 3D vector — acceleration, rotation rate, gravity. The matrix is **orthonormal**: every row and column is a unit vector and all are mutually perpendicular, so it purely rotates without scaling or skewing.

**Reference frame:** The default `xArbitraryZVertical` reference makes yaw relative to an arbitrary start orientation. For world-frame shot heading, we need `xMagneticNorthZVertical`:
- World X = magnetic east
- World Y = magnetic north
- World Z = up

One line change to unlock this:
```swift
motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: motionQueue) { ... }
```

---

## Step 2: Separating Centripetal from Tangential

For any point on a rotating body, the total acceleration has two components:

- **Centripetal** (`a_c`): points inward toward the rotation axis. Encodes "how fast are you spinning." Does NOT point toward the target.
- **Tangential** (`a_t`): points along the direction of travel (tangent to the arc). This IS the shot direction.

These components are related to the angular velocity vector `ω` (from the gyroscope) and the current velocity `v` (of the wrist) by:

```
a_centripetal = ω × v          (cross product)
a_tangential  = a_total − (ω × v)
```

Both `ω` and `a_total` are measured directly by the Watch. We need `v`.

---

## Step 3: Getting Wrist Velocity by Integration

We already identify the **setup phase** — the period where the wrist is stationary at address. This gives us a known zero-velocity anchor:

```
v = 0  at setup start
```

From there, numerically integrate the world-frame acceleration at each sample:

```
v(t + dt) = v(t) + a_world(t) * dt
```

Since the swing is ~0.5–1.5 seconds from setup end to impact, IMU drift over that window is manageable. Critically, drift affects **magnitude** much more than **direction** — so heading accuracy from the velocity direction remains useful even as the magnitude estimate drifts.

---

## Step 4: Extracting Shot Heading

At the forward stroke peak (already identified in the state machine):

1. Compute `a_centripetal = ω_world × v_world`
2. Compute `a_tangential = a_world − a_centripetal`
3. Drop the vertical component (Z): project onto horizontal plane
4. `heading = atan2(a_tangential.x, a_tangential.y)` — degrees from magnetic north

This heading is the compass direction the wrist was traveling at peak forward stroke, which closely corresponds to the intended shot direction.

---

## Applicability by Stroke Type

| Stroke Type | Centripetal Component | Shortcut Available? | Best Method |
|-------------|----------------------|---------------------|-------------|
| Putt | Negligible (linear stroke) | Yes — use raw `a_world` direction directly | Acceleration direction |
| Chip | Small | Mostly OK with raw direction | Acceleration direction (or full decomposition) |
| Half-swing | Moderate | Use full decomposition | ω × v decomposition |
| Full swing | Dominant (~5–20G) | No shortcut | ω × v decomposition |

For putts, the full decomposition still works — `ω ≈ 0` so `ω × v ≈ 0` and `a_tangential ≈ a_total`. No harm in using the same code path for all stroke types.

---

## Why the "Yaw at Impact" Shortcut Doesn't Work

An earlier idea was to read the device yaw at impact and use that as shot heading. This is wrong for two reasons:

1. **Yaw encodes face orientation, not travel direction.** Yaw tells you which compass direction the watch face is pointing, not which direction the wrist is moving. These are unrelated — the wrist can move in any direction regardless of how the watch face is oriented.

2. **Wrist rotation (pronation/supination) through impact.** The forearm rolls through impact independently of the arm's travel direction, changing yaw without changing where the shot goes. There is no stable geometric mapping from watch yaw to shot heading.

---

## Implementation Plan

### What already exists
- 50Hz device motion including attitude rotation matrix and gyroscope
- Setup phase detection (zero-velocity anchor)
- Forward stroke peak detection (timing of impact moment)
- `xMagneticNorthZVertical` reference frame available (one-line change)

### What needs to be added
1. **Reference frame change:** Switch `startDeviceMotionUpdates` to `xMagneticNorthZVertical`
2. **World-frame transform:** At each sample during a swing, compute `a_world = R × a_device` and `ω_world = R × ω_device`
3. **Velocity integration:** From setup-end zero, accumulate `v_world` each sample
4. **Decomposition at peak:** Apply `a_tangential = a_world − (ω_world × v_world)`
5. **Heading output:** `atan2(a_tangential.x, a_tangential.y)` → degrees from magnetic north → store in `DetectedSwing.trajectoryHeading`

### Validation approach
Collect paired data: GPS start position + GPS landing position (gives ground-truth heading) alongside motion data. Compare derived heading against `bearing(from: strokeLocation, to: landingLocation)`. Measure angular error across stroke types.

---

## Limitations and Caveats

- **Compass calibration:** `xMagneticNorthZVertical` uses the Watch magnetometer. Accuracy degrades near metal (golf carts, etc.). Same limitation as any compass app.
- **Rotation axis assumption:** The decomposition assumes a single dominant rotation axis. For a golf swing this is approximately true (spine/vertical axis dominates) but the axis tilts somewhat, adding a small error in the horizontal projection.
- **Velocity drift:** Single integration of consumer IMU over 1+ seconds accumulates some error. Direction is affected less than magnitude, but long setup-to-impact windows (player takes time addressing) increase drift. May need to re-zero velocity at the moment the setup phase ends rather than at setup start.
- **Club-head vs wrist:** The Watch is on the wrist, not the club head. The tangential direction of wrist travel at impact is a proxy for shot direction, not a direct measurement. For putts this proxy is very close; for full swings there is a small but consistent offset due to wrist mechanics at impact (forearm rotation). This offset is player-specific and could be calibrated from GPS ground truth over time.
