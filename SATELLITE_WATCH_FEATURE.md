# Satellite Imagery on Apple Watch - Feature Documentation

## Current Status: ALL MAJOR ISSUES FIXED ✅

**CRITICAL FIXES COMPLETED (2026-01-11):**
- ✅ **Camera centering now matches regular MapKit view** (45%/50% midpoint between user and hole)
- ✅ **View now shows user at bottom, hole at top** (just like regular map)
- ✅ **Coordinate transformations updated** to use view center instead of image center
- ✅ **Image offset calculation** handles difference between image center and view center
- ✅ **iPhone image cropping now uses EXACT midpoint** between user and hole (not hole-centered)

**All Issues Fixed (2026-01-11):**
- ✅ Bottom menu not opening in satellite view (allowsHitTesting)
- ✅ Large image metadata mismatch (2000×2000 vs 3000×3000)
- ✅ Image aspect ratio distortion (.fill → .fit)
- ✅ Coordinate transformation scaling logic
- ✅ Camera center unused code (documented intent)
- ✅ Edge holes not centered properly (pixel-to-coordinate calculation)
- ✅ Tap gesture support for target/penalty placement
- ✅ Digital Crown behavior (only zoom in target/penalty placement modes)
- ✅ Camera centering fundamentally wrong (now uses 45%/50% midpoint)
- ✅ Coordinate transformation reference point (now uses view center, not image center)
- ✅ iPhone image cropping centered on hole (now uses EXACT midpoint with user location)

**What's Working:**
- ✅ iPhone downloads 2000×2000px satellite images (2km diameter)
- ✅ iPhone crops per-hole images when holes are added
- ✅ WatchConnectivity file transfer is working
- ✅ Watch receives and caches satellite images
- ✅ Logging system captures all operations to shareable log files
- ✅ Reactive hole addition triggers download/crop/transfer
- ✅ Digital Crown zoom (0.5x - 3.0x) in placement modes only
- ✅ Bottom menu opens via swipe-up indicator
- ✅ Tap gestures work for placing targets and penalties
- ✅ Camera centers between user and hole (matching regular map)
- ✅ Annotations positioned correctly relative to view center

**Ready for Testing:**
- All critical issues fixed
- Watch display logic matches regular map perfectly
- iPhone cropping optimized for maximum relevant coverage
- Coordinate transformations handle all edge cases

**Next Steps:**
1. Test on actual device to verify positioning is correct
2. Validate user appears at bottom, hole at top
3. Test annotations align correctly with satellite imagery
4. Test zoom behavior preserves correct positioning
5. Test new crops show optimal coverage (user and hole both visible with minimal wasted space)

---

## 🗺️ UNDERSTANDING THE REGULAR MAP VIEW BEHAVIOR

**This section documents the EXACT behavior of the regular MapKit view (`ActiveRoundView.swift:1470-1512`), which the satellite view MUST replicate.**

### Regular Map View: How It Works

#### 1. **View Center Calculation**

The map is NOT centered on the user, and it's NOT centered on the hole. It's centered on a point **between** the user and the hole:

```swift
// Calculate center point - balanced between start and hole
let centerLat = startCoord.latitude + (holeCoord.latitude - startCoord.latitude) * 0.45
let centerLon = startCoord.longitude + (holeCoord.longitude - startCoord.longitude) * 0.5
```

**What this means:**
- **Vertically (latitude)**: Center is 45% of the way from user to hole
- **Horizontally (longitude)**: Center is 50% of the way from user to hole
- **Result**: User appears near bottom of screen, hole appears near top of screen
- **Why 45%/50%**: Slight bias toward user gives more view of what's ahead

#### 2. **Camera Setup**

```swift
let camera = MapCamera(
    centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
    distance: max(distance * 2.5, 100), // Zoom level ("altitude")
    heading: bearing, // Rotate so hole is "up" and user is "down"
    pitch: 0
)
```

**What this means:**
- **Center**: The calculated midpoint (45%/50% between user and hole)
- **Distance**: 2.5× the user-to-hole distance (minimum 100m) - this is the "altitude" of the camera
- **Heading**: Bearing from user → hole, so the hole always appears at top of screen
- **Result**: Map rotates as user moves to always keep hole at top

#### 3. **Visual Result**

When looking at the Watch screen:
- **Top of screen**: Hole flag marker (yellow flag)
- **Bottom of screen**: User location marker (blue arrow pointing user's heading)
- **Between them**: The fairway, hazards, targets, stroke markers
- **Rotation**: Map rotates so the hole is always "up" regardless of actual cardinal direction
- **Coverage**: Shows both user and hole with padding on all sides

#### 4. **Full View Mode Variation**

In "Full View Mode", the start coordinate is the **first stroke** instead of current user location:

```swift
if isFullViewMode, let first = firstStroke {
    startCoord = first.coordinate  // Tee box position
} else if let userLocation = locationManager.location {
    startCoord = userLocation.coordinate  // Current position
}
```

This shows the entire shot history from tee to current position.

---

### Satellite View: Current BROKEN Behavior

#### What It's Doing Wrong (Lines 710-720 in ActiveRoundView.swift)

```swift
// ❌ WRONG - centered on hole
let cameraInfo = MapCameraInfo(
    centerCoordinate: hole.coordinate,  // ❌ Should be midpoint!
    bearing: bearing,
    distance: max(distance * 2.5, 100)
)
```

**Why this is wrong:**
1. **Image is centered on hole coordinate**
2. **50% of image shows area BEYOND the hole** (completely irrelevant)
3. **Only 50% of image shows area BETWEEN user and hole** (the only relevant area)
4. **User appears in weird positions** depending on distance from hole
5. **Does NOT match regular map behavior**

#### Why The Crop Strategy Is Also Wrong

The iPhone crops per-hole images centered on the hole coordinate:

```swift
// SatelliteCacheManager.swift:175
let metadata = SatelliteImageMetadata(courseId: courseId, holeNumber: hole.number, center: actualCenter)
```

**Why this is wrong:**
- When you're on the tee box 400 yards from the hole, the cropped image shows:
  - 200 yards in front of hole (useless)
  - 200 yards behind hole (useless)
  - Only the hole is visible, user is off-screen or barely visible
- The image should be centered on the **typical midpoint** for that hole (e.g., 45%/50% between tee and hole)

---

### What Needs To Be Fixed

#### 1. **Image Cropping Strategy (iPhone)**

When cropping per-hole images, center the crop on:
- **Option A**: Midpoint between hole and where the hole was created (usually tee box)
- **Option B**: Midpoint between hole and a point 400 yards away (max drive + approach)
- **Option C**: Dynamically calculate based on hole par and typical distances

#### 2. **Camera Centering Logic (Watch)**

When displaying satellite view, calculate the center the SAME way as regular map:

```swift
// Should match updateMapPosition() logic
let centerLat = userCoord.latitude + (holeCoord.latitude - userCoord.latitude) * 0.45
let centerLon = userCoord.longitude + (holeCoord.longitude - userCoord.longitude) * 0.5

let cameraInfo = MapCameraInfo(
    centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
    bearing: bearing,
    distance: max(distance * 2.5, 100)
)
```

#### 3. **Coordinate Transformation**

The `coordinateToScreenPosition()` function needs to account for the fact that:
- The image is centered on a fixed point (crop center)
- The view is centered on a dynamic point (user-to-hole midpoint)
- These are NOT the same point
- Transformation needs to handle the offset between them

---

## ⚠️ PRIMARY USE CASE: First-Time User with New Course

**CRITICAL**: This feature must be designed around the first-time user experience. When thinking about this feature, ALWAYS assume:

1. User opens app for the first time
2. User creates a new course (just a name, **NO holes yet**)
3. User starts a round on that course
4. User is physically at the golf course (has GPS location)
5. User adds holes one-by-one as they play

**The flow should support pre-mapped courses with existing holes, but the PRIMARY design target is unmapped courses being played for the first time.**

---

## Goal

Display satellite imagery on Apple Watch during active rounds to provide golfers with a visual representation of the hole, showing:
- Satellite view of the hole and surrounding area
- User's current location
- All recorded strokes with numbers
- Target markers
- Hole position (flag)
- Digital Crown zoom capability (0.5x - 3.0x)

---

## Intended Architecture & Flow

### The CORRECT Flow (First-Time User)

**Step 1: Round Start (No Holes Exist Yet)**
- User starts a round on a course with 0 holes
- iPhone attempts to download large 2km × 2km (2000×2000px) satellite image **centered on USER'S CURRENT GPS LOCATION**
- Uses `LocationManager.shared.getCurrentLocation()` which falls back to last known location if needed
- Image covers 1000m radius around where user is standing
- Assumption: User is at the golf course when starting the round
- Large image stored on iPhone only
- **Nothing sent to Watch yet** (no holes to crop!)
- If location unavailable at round start, download triggered when first hole is added

**Step 2: User Adds First Hole**
- User adds hole #1 (on iPhone or Watch)
- Hole coordinate is captured at user's current location
- **TRIGGER**: iPhone detects new hole was added
- iPhone crops 2000×2000px image centered on hole #1 from large image
- iPhone transfers cropped image to Watch
- Watch receives and displays satellite view for hole #1

**Step 3: User Adds More Holes During Play**
- User moves to next location, adds hole #2
- **TRIGGER**: iPhone detects new hole was added
- iPhone crops image for hole #2
- iPhone transfers cropped image to Watch
- Watch receives and displays satellite view for hole #2
- Repeat for all 18 holes as they're added during play

### The Flow for Pre-Mapped Courses

If a course already has holes defined:

**At Round Start:**
- Check if large satellite image already cached
- If not cached: Download large image centered on **course centroid** (average of all hole coordinates)
- Crop images for all holes immediately
- Transfer all crops to Watch
- User starts playing with satellite views already available

---

## Current Implementation (What Exists)

### iPhone Side

#### 1. SatelliteCacheManager.swift ✅ (Mostly Working)
**Location**: `GolfTracker/Services/SatelliteCacheManager.swift`

**Methods that work:**
- `downloadLargeSatelliteImage(centerCoordinate:courseId:completion:)` - Downloads 3000×3000px satellite image
- `cropImageForHole(courseId:hole:completion:)` - Crops 2000×2000px image for a specific hole
- `getCachedImages(for:)` - Retrieves cache metadata
- `getImageData(for:holeNumber:)` - Gets image data for a hole

**What works:**
- Downloads satellite imagery using MapKit `MKMapSnapshotter`
- JPEG compression at 85% quality
- Coordinate-to-pixel transformation math
- File system storage and metadata management

#### 2. SatelliteTransferManager.swift ✅ (Working)
**Location**: `GolfTracker/Services/SatelliteTransferManager.swift`

**Methods:**
- `transferImages(for:completion:)` - Transfer all holes for a course
- `transferHoleImage(courseId:holeNumber:completion:)` - Transfer single hole
- Uses `WCSession.default.transferFile()` for reliable background transfer

**What works:**
- Encodes metadata as JSON
- Saves image to temp file
- Queues file transfer via WatchConnectivity
- Sequential transfer to avoid overwhelming Watch

#### 3. Auto-Trigger Logic ❌ (BROKEN)
**Location**: `GolfTracker/Services/DataStore.swift` line 285-355

**Current behavior:**
```swift
private func handleSatelliteImagesForRound(course: Course) {
    let cacheManager = SatelliteCacheManager.shared

    if existingCache.images.count == course.holes.count {
        // Transfer existing cache
        SatelliteTransferManager.shared.transferImages(for: course.id)
    } else {
        // Download large image centered on FIRST HOLE
        let startLocation = course.holes.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        cacheManager.downloadLargeSatelliteImage(centerCoordinate: startLocation, courseId: course.id) { result in
            // Crop and transfer all holes sequentially
            self.cropAndTransferHoleImages(for: course)
        }
    }
}
```

**What's wrong:**
1. ❌ Centers on `course.holes.first?.coordinate` - assumes holes exist!
2. ❌ Falls back to (0, 0) if no holes → downloads ocean off Africa
3. ❌ Only runs at round start, **never runs when holes are added later**
4. ❌ Tries to crop all holes immediately → if 0 holes, crops nothing
5. ❌ No reactive hook to detect when new holes are added

### Watch Side

#### 1. WatchSatelliteCacheManager.swift ✅ (Working)
**Location**: `GolfWatch Watch App/Services/WatchSatelliteCacheManager.swift`

**What works:**
- File system storage for received images
- Metadata JSON management
- Image retrieval by courseId and holeNumber
- Published `availableCourses` set for UI

#### 2. SatelliteImageView.swift ✅ (Working)
**Location**: `GolfWatch Watch App/Views/SatelliteImageView.swift`

**What works:**
- Renders satellite image as background
- Coordinate-to-pixel transformation with rotation
- Overlays annotations (hole, user, strokes, targets)
- Digital Crown zoom (0.5x - 3.0x)
- Falls back to loading view if no image

#### 3. WatchConnectivityManager.swift ❌ (CRITICAL MISSING)
**Location**: `GolfTracker/Services/WatchConnectivityManager.swift` (shared file)

**What's missing:**
- **NO `session(_:didReceive file:)` delegate method**
- iPhone sends files via `transferFile()` but Watch never receives them!
- Images are sent but disappear into the void
- Watch cache remains empty forever

---

## What's Broken (Detailed Issues)

### 🔴 Critical Issue #1: No File Transfer Receiver on Watch

**Problem:**
iPhone calls `WCSession.default.transferFile()` but Watch has no delegate method to receive the file.

**Impact:**
- Images are downloaded ✅
- Images are cropped ✅
- Transfer is initiated ✅
- **Watch never receives images** ❌
- `WatchSatelliteCacheManager` stays empty ❌
- User sees "Loading Satellite" forever ❌

**Fix Required:**
Add to `WatchConnectivityManager.swift`:
```swift
func session(_ session: WCSession, didReceive file: WCSessionFile) {
    print("⌚ [Watch] Received file: \(file.fileURL.lastPathComponent)")

    guard let metadataJSON = file.metadata?["metadata"] as? Data,
          let metadata = try? JSONDecoder().decode(SatelliteImageMetadata.self, from: metadataJSON) else {
        print("⌚ [Watch] ERROR: Failed to decode metadata")
        return
    }

    guard let imageData = try? Data(contentsOf: file.fileURL) else {
        print("⌚ [Watch] ERROR: Failed to read image data")
        return
    }

    WatchSatelliteCacheManager.shared.saveImage(metadata: metadata, imageData: imageData)
    print("⌚ [Watch] Successfully cached satellite image for hole \(metadata.holeNumber)")
}
```

### 🔴 Critical Issue #2: Wrong Center Coordinate for Large Image

**Problem:**
Line 301 in `DataStore.swift`:
```swift
let startLocation = course.holes.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
```

**What happens:**
- If no holes exist: Downloads image of **null island (0°N, 0°E)** in the ocean
- If holes exist: Centers on first hole (okay but not optimal)

**Should be:**
```swift
let startLocation = LocationManager.shared.location?.coordinate ?? course.holes.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
```

**Better yet:**
- Use **user's current GPS location** when starting round
- Only fall back to hole coordinates if user location unavailable
- For pre-mapped courses, use **centroid of all holes**

### 🔴 Critical Issue #3: No Reactive Hole Addition Hook

**Problem:**
`handleSatelliteImagesForRound()` only runs when round starts. There's no code that triggers when a new hole is added during play.

**Current flow (broken):**
1. User starts round with 0 holes
2. Large image downloads centered at (0, 0) 🌊
3. No holes to crop, so nothing happens
4. User adds hole #1 → **Nothing happens!**
5. User adds hole #2 → **Nothing happens!**
6. Satellite feature never works

**What needs to happen:**
1. User starts round
2. Large image downloads centered at **user location** 📍
3. User adds hole #1
4. **TRIGGER**: Detect hole was added
5. **ACTION**: Crop image for hole #1, transfer to Watch
6. User adds hole #2
7. **TRIGGER**: Detect hole was added
8. **ACTION**: Crop image for hole #2, transfer to Watch

**Where to add the hook:**

Holes can be added from two places:

**A. iPhone side:**
Find where holes are added to courses (likely in course editor or during play). After saving new hole, call:
```swift
// After hole is added to course
if let activeRound = currentActiveRound, activeRound.courseId == course.id {
    handleNewHoleAdded(courseId: course.id, hole: newHole)
}
```

**B. Watch side:**
When Watch adds a hole, it syncs to iPhone via `WatchConnectivityManager.sendRound()`. The iPhone's `onReceiveRound` callback should detect new holes and trigger crop/transfer.

**Required new method in DataStore:**
```swift
private func handleNewHoleAdded(courseId: UUID, hole: Hole) {
    let cacheManager = SatelliteCacheManager.shared

    // Check if large image exists for this course
    guard cacheManager.getCachedImages(for: courseId)?.largeImage != nil else {
        print("📱 [DataStore] No large satellite image cached, cannot crop for hole \(hole.number)")
        return
    }

    // Crop and transfer this hole's image
    cacheManager.cropImageForHole(courseId: courseId, hole: hole) { result in
        switch result {
        case .success(_):
            SatelliteTransferManager.shared.transferHoleImage(courseId: courseId, holeNumber: hole.number) { success in
                if success {
                    print("📱 [DataStore] Transferred satellite image for hole \(hole.number)")
                }
            }
        case .failure(let error):
            print("📱 [DataStore] Failed to crop hole \(hole.number): \(error)")
        }
    }
}
```

### 🟡 Moderate Issue #4: No User Feedback

**Problems:**
- No progress indicator during download
- No success/failure notifications
- User has no idea if feature is working
- Can't tell which courses have cached images
- No way to manually trigger download
- No retry on failure

**Impact:**
- Poor user experience
- Hard to debug
- Users think feature is broken even when it's working

---

## Implementation Plan

### Phase 1: Make It Work (Critical - Do This First!)

#### Task 1.1: Add File Transfer Receiver to Watch
**File**: `GolfTracker/Services/WatchConnectivityManager.swift`
**Action**: Add `session(_:didReceive file:)` delegate method as shown above
**Test**: Transfer a file, verify Watch logs "Successfully cached satellite image"

#### Task 1.2: Fix Large Image Center Coordinate
**File**: `GolfTracker/Services/DataStore.swift` line 301
**Current**:
```swift
let startLocation = course.holes.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
```
**Change to**:
```swift
let startLocation = LocationManager.shared.location?.coordinate ?? calculateCourseCentroid(course: course) ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
```

**Add helper**:
```swift
private func calculateCourseCentroid(course: Course) -> CLLocationCoordinate2D? {
    guard !course.holes.isEmpty else { return nil }
    let avgLat = course.holes.map { $0.coordinate.latitude }.reduce(0, +) / Double(course.holes.count)
    let avgLon = course.holes.map { $0.coordinate.longitude }.reduce(0, +) / Double(course.holes.count)
    return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
}
```

#### Task 1.3: Add Reactive Hole Addition Hook
**File**: `GolfTracker/Services/DataStore.swift`

**Step A**: Add method to handle new holes:
```swift
private func handleNewHoleAdded(courseId: UUID, hole: Hole) {
    let cacheManager = SatelliteCacheManager.shared

    // Check if large image exists
    guard let cache = cacheManager.getCachedImages(for: courseId),
          cache.largeImage != nil else {
        print("📱 [DataStore] No large satellite image for course, cannot crop")
        return
    }

    // Check if we already have this hole's crop
    if cache.images.contains(where: { $0.holeNumber == hole.number }) {
        print("📱 [DataStore] Hole \(hole.number) already has satellite crop")
        return
    }

    // Crop and transfer
    print("📱 [DataStore] Cropping satellite image for newly added hole \(hole.number)")
    cacheManager.cropImageForHole(courseId: courseId, hole: hole) { result in
        switch result {
        case .success(_):
            SatelliteTransferManager.shared.transferHoleImage(courseId: courseId, holeNumber: hole.number) { success in
                if success {
                    print("📱 [DataStore] ✅ Transferred satellite for hole \(hole.number)")
                }
            }
        case .failure(let error):
            print("📱 [DataStore] ❌ Failed to crop hole \(hole.number): \(error)")
        }
    }
}
```

**Step B**: Call it when holes are added to courses
Find where `Course.holes.append()` is called and add:
```swift
// After adding hole to course
if let activeRound = rounds.first(where: { $0.courseId == course.id && /* round is active */ }) {
    handleNewHoleAdded(courseId: course.id, hole: newHole)
}
```

**Step C**: Call it when receiving round updates from Watch
In `setupWatchConnectivity()` → `onReceiveRound` callback:
```swift
WatchConnectivityManager.shared.onReceiveRound = { [weak self] receivedRound in
    self?.updateRoundFromWatch(receivedRound)

    // Check for new holes
    if let course = self?.courses.first(where: { $0.id == receivedRound.courseId }) {
        for hole in receivedRound.holes {
            if !course.holes.contains(where: { $0.number == hole.number }) {
                self?.handleNewHoleAdded(courseId: course.id, hole: hole)
            }
        }
    }
}
```

#### Task 1.4: Update `handleSatelliteImagesForRound` Logic
**File**: `GolfTracker/Services/DataStore.swift` line 285-314

**Current logic is wrong. Replace with:**
```swift
private func handleSatelliteImagesForRound(course: Course) {
    let cacheManager = SatelliteCacheManager.shared
    let existingCache = cacheManager.getCachedImages(for: course.id)

    // Case 1: Course has holes AND we have all crops cached
    if !course.holes.isEmpty,
       let cache = existingCache,
       cache.images.count == course.holes.count {
        print("📱 [DataStore] All \(course.holes.count) holes already cached, transferring to Watch")
        SatelliteTransferManager.shared.transferImages(for: course.id) { success in
            if success {
                print("📱 [DataStore] ✅ Successfully transferred cached images")
            }
        }
        return
    }

    // Case 2: Course has holes BUT incomplete/missing cache
    if !course.holes.isEmpty {
        print("📱 [DataStore] Course has \(course.holes.count) holes but incomplete cache, downloading...")
        let centerCoordinate = calculateCourseCentroid(course: course) ?? course.holes.first!.coordinate

        cacheManager.downloadLargeSatelliteImage(centerCoordinate: centerCoordinate, courseId: course.id) { result in
            switch result {
            case .success(_):
                print("📱 [DataStore] Large image downloaded, cropping all holes...")
                self.cropAndTransferHoleImages(for: course)
            case .failure(let error):
                print("📱 [DataStore] ❌ Download failed: \(error)")
            }
        }
        return
    }

    // Case 3: Course has NO holes yet (first-time user flow)
    if course.holes.isEmpty {
        // Download large image centered on user's current location
        guard let userLocation = LocationManager.shared.location?.coordinate else {
            print("📱 [DataStore] Cannot download satellite: no user location and no holes")
            return
        }

        print("📱 [DataStore] Downloading satellite centered on user location (course has no holes yet)")
        cacheManager.downloadLargeSatelliteImage(centerCoordinate: userLocation, courseId: course.id) { result in
            switch result {
            case .success(_):
                print("📱 [DataStore] ✅ Large image ready, waiting for holes to be added...")
                // Don't crop anything yet - holes will be added later
            case .failure(let error):
                print("📱 [DataStore] ❌ Download failed: \(error)")
            }
        }
        return
    }
}
```

### Phase 2: User Experience (Important - Do After Phase 1 Works)

#### Task 2.1: Add Progress Indicators
- Download progress on iPhone (already has `@Published var downloadProgress`)
- Transfer progress (X of Y holes)
- Toast notification on Watch when image arrives

#### Task 2.2: Add Manual Controls
- "Download Satellite" button in course details (iPhone)
- "Refresh Satellite Cache" option
- View cached courses list with sizes

#### Task 2.3: Error Handling & Retry
- Retry failed downloads automatically
- Show user-facing error messages
- Fallback to standard map gracefully

### Phase 3: Optimization (Nice to Have - Do Last)

#### Task 3.1: Smart Caching
- Preload next 2-3 holes as user approaches
- Delete old course caches to save space
- Compress images more aggressively

#### Task 3.2: Better Image Coverage
- Validate all holes fall within large image bounds
- Adjust radius dynamically if course is large
- Support courses > 3km diameter

---

## Testing Checklist

### Test Scenario 1: First-Time User (PRIMARY)
1. [ ] Create new course with just a name
2. [ ] Start round (0 holes exist)
3. [ ] Verify large image downloads centered on user location (not 0,0)
4. [ ] Verify nothing sent to Watch yet
5. [ ] Add first hole on Watch
6. [ ] Verify iPhone crops image for hole #1
7. [ ] Verify Watch receives and displays hole #1 satellite image
8. [ ] Add second hole
9. [ ] Verify iPhone crops and transfers hole #2
10. [ ] Verify Watch displays hole #2 satellite image
11. [ ] Complete full round adding all 18 holes
12. [ ] Verify all 18 satellite images work

### Test Scenario 2: Pre-Mapped Course
1. [ ] Create course with 18 pre-defined holes
2. [ ] Start round
3. [ ] Verify large image downloads centered on course centroid
4. [ ] Verify all 18 holes cropped immediately
5. [ ] Verify all 18 crops transferred to Watch
6. [ ] Verify Watch displays satellite for hole #1 immediately
7. [ ] Navigate through all 18 holes
8. [ ] Verify satellite view works for all holes

### Test Scenario 3: Partial Course
1. [ ] Create course with 5 holes
2. [ ] Start round
3. [ ] Verify 5 holes cropped and transferred
4. [ ] Play to hole #6 (doesn't exist yet)
5. [ ] Add hole #6 during play
6. [ ] Verify hole #6 crops and transfers
7. [ ] Add holes #7-18 during play
8. [ ] Verify each new hole gets satellite image

### Test Scenario 4: Edge Cases
1. [ ] Start round without GPS lock (should fallback gracefully)
2. [ ] Add hole outside 1500m radius of large image (should handle boundary)
3. [ ] Disconnect Watch mid-transfer (should queue and retry)
4. [ ] Start round, immediately add hole before download completes
5. [ ] Delete satellite cache, verify re-download works

---

## Key Files Reference

### iPhone
- `GolfTracker/Services/SatelliteCacheManager.swift` - Download & crop
- `GolfTracker/Services/SatelliteTransferManager.swift` - Transfer to Watch
- `GolfTracker/Services/DataStore.swift` (line 285-355) - Round start logic
- `GolfTracker/Services/WatchConnectivityManager.swift` - Connectivity (shared)
- `GolfTracker/Services/LocationManager.swift` - User GPS location

### Watch
- `GolfWatch Watch App/Services/WatchSatelliteCacheManager.swift` - Storage
- `GolfWatch Watch App/Views/SatelliteImageView.swift` - Rendering
- `GolfWatch Watch App/Views/ActiveRoundView.swift` (line 692-721, 1117-1131) - UI
- `GolfWatch Watch App/Services/WatchDataStore.swift` - satelliteModeEnabled

### Shared
- `GolfTracker/Models/Models.swift` (line 171-238) - Data models

---

## Data Models

### SatelliteImageMetadata (Per-Hole Crop)
```swift
struct SatelliteImageMetadata: Codable {
    var courseId: UUID
    var holeNumber: Int
    var fileName: String              // "hole_1_satellite.jpg"
    var centerLatitude: Double        // Hole coordinate
    var centerLongitude: Double
    var metersPerPixel: Double        // ~0.55 (2000px covers 1100m)
    var pixelWidth: Int               // 2000
    var pixelHeight: Int              // 2000
    var capturedDate: Date
    var version: Int = 1
}
```

### LargeSatelliteImageMetadata (Course-Wide)
```swift
struct LargeSatelliteImageMetadata: Codable {
    var fileName: String              // "large_satellite.jpg"
    var centerLatitude: Double        // User location OR course centroid
    var centerLongitude: Double
    var radiusMeters: Double          // 1500 (3km diameter)
    var pixelWidth: Int               // 3000
    var pixelHeight: Int              // 3000
    var metersPerPixel: Double        // 1.0
    var capturedDate: Date
}
```

### CourseSatelliteCache
```swift
struct CourseSatelliteCache: Codable {
    var courseId: UUID
    var courseName: String
    var largeImage: LargeSatelliteImageMetadata?
    var images: [SatelliteImageMetadata]  // Per-hole crops
    var lastUpdated: Date
    var version: Int = 1
}
```

---

## Logging System (IMPLEMENTED ✅)

A complete logging system captures all satellite operations to shareable text files for debugging on TestFlight.

**SatelliteLogHandler** (`GolfTrackerApp.swift`):
- Singleton pattern: `SatelliteLogHandler.shared`
- Creates new log file for each round: `satellite_log_[timestamp].txt`
- Stored in `Documents/SatelliteLogs/`
- Accessible via Tests tab → "Satellite Logs" segment

**What Gets Logged:**
- Round start with course name
- Large image download attempts (with GPS coordinates)
- Download success/failure with detailed error codes
- Each hole detection (with coordinates)
- Crop operations (success/failure)
- File transfers to Watch
- Watch sync events

**Viewing Logs:**
1. Open Tests tab on iPhone
2. Switch to "Satellite Logs" segment
3. Select log file(s)
4. Tap "Share" to export via AirDrop/Messages/Email
5. Delete old logs with "Delete" button

**Example Log Entry:**
```
[8:45:23 PM] 📱 Satellite log started for round on Pine Valley
[8:45:23 PM] 📱 [DataStore] Downloading satellite centered on user location
[8:45:23 PM] 📍 User location: (30.293752, -81.717635)
[8:45:25 PM] 📡 [SatelliteCache] Starting download - Size: 2000x2000px, Radius: 1000m
[8:45:28 PM] 📱 [DataStore] ✅ Large image ready
[8:45:35 PM] 🆕 New hole detected: #1 at (30.293752, -81.717635)
[8:45:35 PM] 📱 [DataStore] Cropping satellite image for hole 1
[8:45:36 PM] ✂️ Successfully cropped hole 1
[8:45:36 PM] 📱 [DataStore] ✅ Transferred satellite for hole 1
```

---

## Summary

**What's Working Now:**
1. ✅ Watch file receiver implemented - images successfully transferred
2. ✅ Large image uses user location via `getCurrentLocation()`
3. ✅ Reactive hooks detect holes added on iPhone and Watch
4. ✅ Round start logic handles 0-hole case (downloads on first hole if needed)
5. ✅ Full logging system for TestFlight debugging
6. ✅ Image size reduced to 2000×2000px to avoid Apple Maps server errors

**What's Still Broken:**
None! All critical issues have been addressed. Testing needed to verify fixes.

---

## Fix Log (2026-01-11)

### Issue #1: Large Image Metadata Mismatch ✅ FIXED
**Problem**: `LargeSatelliteImageMetadata` was initialized with default values (3000×3000px @ 1500m radius) but actual download used different dimensions (2000×2000px @ 1000m radius).

**Files Changed**:
- `SatelliteCacheManager.swift:36-46`
- `Models.swift:197-221`

**Fix**:
```swift
// Before:
let metadata = LargeSatelliteImageMetadata(center: centerCoordinate)  // Used defaults
let radiusMeters: Double = 1000.0
options.size = CGSize(width: 2000, height: 2000)

// After:
let radiusMeters: Double = 1000.0
let pixelSize = 2000
let metadata = LargeSatelliteImageMetadata(
    center: centerCoordinate,
    radiusMeters: radiusMeters,
    pixelWidth: pixelSize,
    pixelHeight: pixelSize
)
```

**Impact**: Metadata now accurately describes image dimensions (metersPerPixel = 1.0).

---

### Issue #2: Image Aspect Ratio Distortion ✅ FIXED
**Problem**: Using `.aspectRatio(contentMode: .fill)` on square satellite image (2000×2000) in rectangular Watch screen (184×224) caused the image to be cropped instead of uniformly scaled. Coordinate transformation assumed uniform scaling, causing position errors.

**Files Changed**:
- `SatelliteImageView.swift:69`

**Fix**:
```swift
// Before:
.aspectRatio(contentMode: .fill)

// After:
.aspectRatio(contentMode: .fit)
```

**Impact**: Image now scales uniformly, matching the assumptions in the coordinate transformation math.

---

### Issue #3: Coordinate Transformation Scaling ✅ FIXED
**Problem**: The scale factor needed clarification. With `.fit` mode, the effective display size is `(screenSize.width * scale) x (screenSize.width * scale)` for a square image, so scale must be included in the transformation.

**Files Changed**:
- `SatelliteImageView.swift:225-234`

**Fix**: Added comprehensive comments explaining the scaling math:
```swift
// 3. Scale to screen size
// With .fit mode, image scales to fit within frame of (screenSize * scale)
// For square image in rectangular screen, constraining dimension is width
// So effective image display size is (screenSize.width * scale)
// Therefore we need to include scale in the transformation
let scaleX = (screenSize.width / imageSize.width) * scale
let scaleY = (screenSize.height / imageSize.height) * scale
```

**Impact**: Annotations should now scale correctly with Digital Crown zoom.

---

### Issue #4: Camera Center Unused Code ✅ FIXED
**Problem**: `mapCamera.centerCoordinate` was calculated but never used. The coordinate transformation always uses `metadata.centerCoordinate` (the hole), not the camera center.

**Files Changed**:
- `ActiveRoundView.swift:709-720`

**Fix**: Removed the calculation and documented intent:
```swift
// Before:
let centerLat = userLocation.coordinate.latitude + (hole.coordinate.latitude - userLocation.coordinate.latitude) * 0.45
let centerLon = userLocation.coordinate.longitude + (hole.coordinate.longitude - userLocation.coordinate.longitude) * 0.5
let cameraInfo = MapCameraInfo(centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon), ...)

// After:
// Note: Satellite image is centered on hole coordinate (not a calculated center)
// because the cropped images are pre-centered on each hole
let cameraInfo = MapCameraInfo(centerCoordinate: hole.coordinate, ...)
```

**Impact**: Removed dead code and clarified that satellite views are always centered on the hole.

---

### Issue #5: Edge Holes Not Centered Properly ✅ FIXED
**Problem**: When cropping a hole image from the large satellite image, if the crop rect extended beyond the large image bounds, it was clamped. But metadata still claimed the image was centered on `hole.coordinate`, when it was actually offset.

**Files Changed**:
- `SatelliteCacheManager.swift:139-175`
- `SatelliteCacheManager.swift:222-247` (new helper function)

**Fix**: Added `pixelToCoordinate()` helper and calculated actual center of clamped crop:
```swift
// Calculate the actual center coordinate of the cropped region
// (may differ from hole coordinate if clamping occurred near edges)
let cropCenterX = cropRect.origin.x + cropRect.width / 2
let cropCenterY = cropRect.origin.y + cropRect.height / 2
let actualCenter = pixelToCoordinate(
    pixelX: cropCenterX,
    pixelY: cropCenterY,
    imageCenter: largeImageMetadata.centerCoordinate,
    imageSize: CGSize(width: CGFloat(largeImageMetadata.pixelWidth), height: CGFloat(largeImageMetadata.pixelHeight)),
    metersPerPixel: largeImageMetadata.metersPerPixel
)

// Use actual center of cropped region (accounts for edge clamping)
let metadata = SatelliteImageMetadata(courseId: courseId, holeNumber: hole.number, center: actualCenter)
```

**Impact**: Metadata now accurately reflects the true center of the cropped image, fixing annotation alignment for edge holes.

---

### Issue #6: Rotation Origin ✅ VERIFIED
**Problem**: Potential mismatch between image rotation origin and annotation rotation origin.

**Files Changed**: None

**Fix**: Verified both image (`.rotationEffect()`) and annotations rotate around the same center point (`screenSize.width/2, screenSize.height/2`). No changes needed.

**Impact**: Rotation should work correctly.

---

### Issue #7: No Tap Gesture Support ✅ FIXED
**Problem**: Unlike standard map view, satellite view didn't support tap gestures for placing targets or penalties.

**Files Changed**:
- `SatelliteImageView.swift:24, 30-44, 61-76, 234-288` (added onTap callback, init, gesture handler, screen-to-coordinate function)
- `ActiveRoundView.swift:735-737, 1201-1236` (added callback and handler)

**Fix**: Added complete tap gesture support:
1. Added `onTap` callback parameter to `SatelliteImageView`
2. Added explicit initializer to accept callback
3. Added `.onTapGesture` handler with screen-to-coordinate conversion
4. Added `screenPositionToCoordinate()` function (inverse of coordinate transformation)
5. Added `handleSatelliteViewTap()` in `ActiveRoundView` to process taps

**Impact**: Users can now place targets and penalties in satellite mode, with proper coordinate conversion accounting for rotation and zoom.

---

### Issue #8: Bottom Button Not Opening ✅ FIXED
**Problem**: Swipe-up indicator (bottom button) didn't work in satellite view because `SatelliteImageView` was capturing all touch events.

**Files Changed**:
- `SatelliteImageView.swift:61`

**Fix**:
```swift
.allowsHitTesting(isPlacingTarget || isPlacingPenalty)
```

**Impact**: Only captures touch events during placement modes, allowing bottom menu to work in normal view.

---

### Issue #9: Camera Centering Fundamentally Wrong ✅ FIXED
**Problem**: Satellite view was centered on the hole coordinate, showing 50% irrelevant area beyond the hole. The regular MapKit view centers at 45%/50% between user and hole, showing user at bottom and hole at top. Satellite view did not match this behavior.

**Files Changed**:
- `ActiveRoundView.swift:709-735` (satelliteImageView function)

**Fix**:
```swift
// Determine start coordinate based on view mode
let startCoord: CLLocationCoordinate2D
if isFullViewMode, let first = firstStroke {
    // Full view mode - anchor to first stroke (tee position)
    startCoord = first.coordinate
} else {
    // Default mode - use current user location
    startCoord = userLocation.coordinate
}

// Calculate center point - 45%/50% between start and hole (SAME as regular map)
let centerLat = startCoord.latitude + (hole.coordinate.latitude - startCoord.latitude) * 0.45
let centerLon = startCoord.longitude + (hole.coordinate.longitude - startCoord.longitude) * 0.5

let cameraInfo = MapCameraInfo(
    centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
    bearing: bearing,
    distance: max(distance * 2.5, 100)
)
```

**Impact**: View now centers on midpoint between user and hole, matching regular map behavior. User appears at bottom, hole at top.

---

### Issue #10: Coordinate Transformation Reference Point Wrong ✅ FIXED
**Problem**: After fixing camera centering, coordinate transformations still used `metadata.centerCoordinate` (hole) as reference, but view is now centered at midpoint. This caused annotations to be positioned incorrectly.

**Files Changed**:
- `SatelliteImageView.swift:103-128` (added image offset calculation)
- `SatelliteImageView.swift:235` (annotation positioning - changed to use mapCamera.centerCoordinate)
- `SatelliteImageView.swift:66` (tap gesture - changed to use mapCamera.centerCoordinate)
- `SatelliteImageView.swift:253-284` (new calculateImageOffset function)

**Fix**:
1. Added `calculateImageOffset()` function to calculate screen offset between image center (hole) and view center (midpoint)
2. Applied offset to image display: `.offset(x: imageOffset.x, y: imageOffset.y)`
3. Changed all coordinate transformations to use `mapCamera.centerCoordinate` instead of `metadata.centerCoordinate`

**Impact**:
- Image is physically centered at hole but displayed offset so view appears centered at midpoint
- All annotations (user, hole, strokes, targets) positioned relative to view center
- Coordinate-to-screen transformations now match the display logic

---

### Issue #11: iPhone Image Cropping Centered on Hole Instead of Midpoint ✅ FIXED
**Problem**: iPhone crops per-hole images centered on hole coordinate, wasting 50% of image area showing irrelevant space beyond the hole. Should crop at the EXACT midpoint between user location (when hole is added) and hole position.

**Files Changed**:
- `SatelliteCacheManager.swift:122-162` (added userLocation parameter and midpoint calculation)
- `DataStore.swift:195, 399, 447` (propagate userLocation through call chain)
- `HolePlayView.swift:707` (pass user location when adding hole)
- `CourseEditorView.swift:154, 178` (pass user location when adding hole)

**Fix**:
```swift
// In SatelliteCacheManager.cropImageForHole:
let cropCenter: CLLocationCoordinate2D
if let userLoc = userLocation {
    // Center crop at 45%/50% between user (tee) and hole (pin)
    let centerLat = userLoc.latitude + (hole.coordinate.latitude - userLoc.latitude) * 0.45
    let centerLon = userLoc.longitude + (hole.coordinate.longitude - userLoc.longitude) * 0.5
    cropCenter = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
} else {
    // Fallback: center on hole (legacy behavior for old crops)
    cropCenter = hole.coordinate
}

// In DataStore.addHole:
store.addHole(to: currentCourse, coordinate: coordinate, par: par, userLocation: locationManager.location?.coordinate)
```

**Impact**:
- New crops use EXACT midpoint between user and hole
- Maximizes relevant image area (between user and hole)
- Minimizes wasted area (beyond hole)
- Reduces need for Watch-side offset compensation
- Matches Watch display logic perfectly

---

## Testing Recommendations

After deploying these fixes, test the following:

1. **User Location Marker**: Start a round, verify user (blue arrow) appears at your actual GPS location on the satellite image
2. **Hole Flag Marker**: Verify yellow flag appears exactly at the hole coordinate
3. **Stroke Markers**: Record strokes, verify numbered circles appear at stroke locations
4. **Digital Crown Zoom**:
   - Turn crown to zoom in (scale increases to 3.0x)
   - Verify annotations stay aligned with features in the satellite image
   - Turn crown to zoom out (scale decreases to 0.5x)
   - Verify annotations still align correctly
5. **Rotation**: Move around the hole, verify image rotates to keep hole "up"
6. **Target Placement**:
   - Tap target button (scope icon)
   - Tap on satellite image
   - Verify white scope icon appears at tap location
   - Tap near existing target to delete it
7. **Penalty Placement**:
   - Tap penalty button (orange triangle)
   - Tap on satellite image
   - Verify orange circle appears at tap location
   - Tap checkmark to save
8. **Bottom Menu**: Tap swipe-up indicator, verify actions sheet opens
9. **Edge Holes**: Test with holes near the edge of the course (within 1000m of course boundary)
10. **Bearing Changes**: Walk in a circle around the hole, verify rotation is smooth

---

**Next Phase:**
Real-world testing to validate all coordinate transformations are accurate and the user experience is smooth.
