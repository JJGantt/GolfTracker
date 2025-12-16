import SwiftUI
import MapKit

struct ActiveRoundView: View {
    @StateObject private var store = WatchDataStore.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var selectedClubIndex: Double = 0
    @State private var position: MapCameraPosition = .automatic
    @State private var showingRecordedFeedback = false
    @State private var capturedAimDirection: Double? = nil
    @State private var crownOffset: CGFloat = 0
    @State private var isPlacingTarget = false
    @State private var isDeleting = false
    @State private var showingActionsSheet = false

    private let clubs = Club.allCases

    private var selectedClub: Club {
        let index = Int(selectedClubIndex.rounded()) % clubs.count
        return clubs[index]
    }

    private var canUndo: Bool {
        guard let hole = store.currentHole else { return false }

        // Can undo if there are strokes on current hole
        let strokesForHole = store.currentRound?.strokes.filter { $0.holeNumber == hole.number } ?? []
        if !strokesForHole.isEmpty {
            return true
        }

        // Can undo if we just finished the previous hole (no strokes on current, previous is completed)
        if store.currentHoleIndex > 0,
           let round = store.currentRound,
           let course = store.getCourse(for: round) {
            let previousHoleNumber = course.holes[store.currentHoleIndex - 1].number
            return round.isHoleCompleted(previousHoleNumber)
        }

        return false
    }

    private var distanceToHole: Int? {
        print("⌚ [Distance] locationManager.location: \(locationManager.location?.description ?? "nil")")
        print("⌚ [Distance] currentHole: \(store.currentHole?.number.description ?? "nil")")

        guard let userLocation = locationManager.location,
              let hole = store.currentHole else {
            print("⌚ [Distance] Returning nil - missing location or hole")
            return nil
        }

        let holeLocation = CLLocation(
            latitude: hole.coordinate.latitude,
            longitude: hole.coordinate.longitude
        )

        let distanceInMeters = userLocation.distance(from: holeLocation)
        let yards = Int(distanceInMeters * 1.09361)
        print("⌚ [Distance] Calculated distance: \(yards) yards")
        return yards
    }

    private var targetCoordinatesBinding: Binding<[CLLocationCoordinate2D]> {
        Binding(
            get: {
                guard let round = self.store.currentRound,
                      let hole = self.store.currentHole else { return [] }
                return round.targets
                    .filter { $0.holeNumber == hole.number }
                    .map { $0.coordinate }
            },
            set: { newCoordinates in
                guard var round = self.store.currentRound,
                      let hole = self.store.currentHole else { return }

                // Remove old targets for this hole
                round.targets.removeAll { $0.holeNumber == hole.number }

                // Add new targets
                let newTargets = newCoordinates.map { Target(holeNumber: hole.number, coordinate: $0) }
                round.targets.append(contentsOf: newTargets)

                // Update in store
                self.store.currentRound = round
                self.store.saveToStorage()

                // Sync to iPhone
                WatchConnectivityManager.shared.sendRound(round)
            }
        )
    }

    private func distanceToTarget(_ target: CLLocationCoordinate2D) -> Int? {
        guard let userLocation = locationManager.location else { return nil }

        let targetLocation = CLLocation(
            latitude: target.latitude,
            longitude: target.longitude
        )

        let distanceInMeters = userLocation.distance(from: targetLocation)
        return Int(distanceInMeters * 1.09361) // Convert to yards
    }

    // Calculate the rotation angle for the aim arrow
    private var aimArrowRotation: Double {
        guard let capturedHeading = capturedAimDirection,
              let userLocation = locationManager.location,
              let hole = store.currentHole else {
            return 0 // Arrow points up when not set
        }

        // Calculate bearing to hole
        let bearingToHole = calculateBearing(from: userLocation.coordinate, to: hole.coordinate)

        // Calculate offset: how much the aim direction differs from hole bearing
        // Positive = aiming right of hole, Negative = aiming left of hole
        let offset = (capturedHeading - bearingToHole + 360).truncatingRemainder(dividingBy: 360)

        // Convert to -180 to 180 range for cleaner display
        let normalizedOffset = offset > 180 ? offset - 360 : offset

        return normalizedOffset
    }

    var body: some View {
        GeometryReader { geometry in
            let buttonSize = geometry.size.width * 0.25  // All buttons: 25% of screen width
            let iconSize = buttonSize * 0.45

            // Relative text sizes based on screen width
            let distanceFontSize = geometry.size.width * 0.12  // Distance number: 12% of width (~22pt on 44mm)
            let holeInfoFontSize = geometry.size.width * 0.055  // Hole info: 5.5% of width (~10pt on 44mm)
            let clubFontSize = geometry.size.width * 0.05  // Club selector: 5% of width

            ZStack {
                // Full screen map
                if let hole = store.currentHole {
                    mapView(for: hole)
                        .ignoresSafeArea()
                }

                // Club selector overlay (positioned at crown height)
                VStack {
                    Spacer()
                        .frame(height: crownOffset)
                    HStack {
                        Spacer()
                        Text(selectedClub.rawValue)
                            .font(.system(size: clubFontSize, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(.trailing, 2)
                    Spacer()
                }

                // Info overlay (top left) - unified distance and hole info
                VStack {
                    HStack(alignment: .top) {
                        if let hole = store.currentHole {
                            VStack(alignment: .leading, spacing: 4) {
                                // Distance - always show, use "XXX" if not available
                                Text(distanceToHole.map { String($0) } ?? "XXX")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                // Hole info
                                let parText = hole.par.map { String($0) } ?? "-"
                                Text("H:\(hole.number)  P:\(parText)  S:\(store.strokeCount(for: hole))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .fixedSize()
                        }

                        Spacer()
                    }
                    .padding(.leading, 6)

                    Spacer()
                }
                .ignoresSafeArea()

                // Buttons overlay (bottom)
                VStack {
                    Spacer()

                    if let hole = store.currentHole {
                        HStack(alignment: .bottom, spacing: 4) {
                            // Left: Stack of buttons (bottom to top: penalty, target)
                            VStack(spacing: 4) {
                                // Target button (top)
                                Button(action: toggleTargetPlacement) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.95))
                                            .frame(width: buttonSize, height: buttonSize)
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                        if isPlacingTarget {
                                            Circle()
                                                .stroke(Color.yellow, lineWidth: 3)
                                                .frame(width: buttonSize, height: buttonSize)
                                        }

                                        Image(systemName: "scope")
                                            .font(.system(size: iconSize, weight: .bold))
                                            .foregroundColor(.black)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())

                                // Orange penalty button (bottom)
                                Button(action: addPenaltyStroke) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange.opacity(0.95))
                                            .frame(width: buttonSize, height: buttonSize)
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: iconSize, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(store.isHoleCompleted(hole.number))
                                .opacity(store.isHoleCompleted(hole.number) ? 0.3 : 0.95)
                            }

                            Spacer()

                            // Right: Stack of buttons (bottom to top: shot, direction)
                            VStack(spacing: 4) {
                                // Blue aim direction button (top)
                                Button(action: captureAimDirection) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.95))
                                            .frame(width: buttonSize, height: buttonSize)
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                        Image(systemName: "location.north.fill")
                                            .font(.system(size: iconSize, weight: .bold))
                                            .foregroundColor(.white)
                                            .rotationEffect(.degrees(aimArrowRotation))
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(store.isHoleCompleted(hole.number))
                                .opacity(store.isHoleCompleted(hole.number) ? 0.3 : 0.95)

                                // Green stroke button (bottom)
                                Button(action: recordStroke) {
                                    ZStack {
                                        Circle()
                                            .fill(showingRecordedFeedback ? Color.white.opacity(0.95) : Color.green.opacity(0.95))
                                            .frame(width: buttonSize, height: buttonSize)
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                        Image(systemName: showingRecordedFeedback ? "checkmark" : "plus")
                                            .font(.system(size: iconSize, weight: .bold))
                                            .foregroundColor(showingRecordedFeedback ? .green : .white)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(store.isHoleCompleted(hole.number))
                                .opacity(store.isHoleCompleted(hole.number) ? 0.3 : 0.95)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                    }
                }
                .ignoresSafeArea()

                // Bottom swipe-up indicator
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        // Swipe indicator pill
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 30, height: 5)
                            .padding(.bottom, 4)
                            .onTapGesture {
                                showingActionsSheet = true
                            }

                        Spacer()
                    }
                }
                .ignoresSafeArea()
            }
            .task {
                calculateCrownOffset(screenHeight: geometry.size.height)
            }
        }
        .focusable()
        .digitalCrownRotation($selectedClubIndex, from: 0, through: Double(clubs.count - 1), by: 1, sensitivity: .low)
        .sheet(isPresented: $showingActionsSheet) {
            actionsSheet
        }
        .onAppear {
            print("⌚ [ActiveRoundView] View appeared")
            print("⌚ [ActiveRoundView] Current location: \(locationManager.location?.description ?? "nil")")
            print("⌚ [ActiveRoundView] Authorization status: \(locationManager.authorizationStatus.rawValue)")
            locationManager.requestPermission()
            locationManager.startTracking()
            print("⌚ [ActiveRoundView] Called requestPermission and startTracking")
            updateMapPosition()
        }
        .onChange(of: locationManager.location) { _, _ in
            // Trigger view refresh when location updates (for distance display)
        }
        .onChange(of: store.currentHoleIndex) { _, _ in
            // Watch syncs hole index from phone - update map when it changes
            updateMapPosition()
        }
        .onChange(of: store.currentHole) { _, _ in
            // Update map when hole changes (also covers new holes added from phone)
            updateMapPosition()
        }
    }

    // MARK: - Map View

    @ViewBuilder
    private func mapView(for hole: Hole) -> some View {
        MapReader { proxy in
            Map(position: $position) {
                // Hole marker (top) - green if completed, yellow if not
                Annotation("", coordinate: hole.coordinate) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 20))
                        .foregroundColor(store.isHoleCompleted(hole.number) ? .green : .yellow)
                }

                // User location (bottom)
                if let userLocation = locationManager.location {
                    Annotation("", coordinate: userLocation.coordinate) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .shadow(color: .white, radius: 2)
                    }
                }

                // Target markers
                ForEach(Array(targetCoordinatesBinding.wrappedValue.enumerated()), id: \.offset) { index, target in
                    Annotation("", coordinate: target) {
                        ZStack {
                            Image(systemName: "scope")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)

                            if let distance = distanceToTarget(target) {
                                VStack {
                                    Spacer()
                                    Text("\(distance)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .offset(y: 18) // Position below the scope icon
                                }
                                .frame(height: 24)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .onTapGesture {
                            if isPlacingTarget {
                                // Remove the target immediately
                                var coords = targetCoordinatesBinding.wrappedValue
                                coords.remove(at: index)
                                targetCoordinatesBinding.wrappedValue = coords
                                WKInterfaceDevice.current().play(.click)
                                // Set flag to block the map tap that will fire immediately after
                                isDeleting = true
                                // Reset the flag on the next run loop so future taps work normally
                                DispatchQueue.main.async {
                                    isDeleting = false
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControls {
                // Disable default map controls (including crown zoom and legal label)
            }
            .mapControlVisibility(.hidden) // Hide legal/attribution label
            .onTapGesture { screenLocation in
                guard isPlacingTarget else { return }

                // If we just deleted a target, skip placing a new one
                if isDeleting {
                    return
                }

                guard let coordinate = proxy.convert(screenLocation, from: .local) else { return }

                // Add new target
                var coords = targetCoordinatesBinding.wrappedValue
                coords.append(coordinate)
                targetCoordinatesBinding.wrappedValue = coords
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    // MARK: - Actions Sheet

    @ViewBuilder
    private var actionsSheet: some View {
        VStack(spacing: 12) {
            // Undo button
            Button(action: {
                deleteLastStroke()
                showingActionsSheet = false
            }) {
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30)

                    Text("Undo Last Stroke")
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.9))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canUndo)
            .opacity(canUndo ? 1.0 : 0.5)

            // Finish hole button
            Button(action: {
                finishCurrentHole()
                showingActionsSheet = false
            }) {
                HStack {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30)

                    Text("Finish Hole")
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.9))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(store.currentHole.map { store.isHoleCompleted($0.number) } ?? true)
            .opacity((store.currentHole.map { store.isHoleCompleted($0.number) } ?? true) ? 0.5 : 1.0)
        }
        .padding()
    }

    // MARK: - Actions

    private func captureAimDirection() {
        print("⌚ [AimDirection] Button tapped")
        print("⌚ [AimDirection] Current heading: \(locationManager.heading?.description ?? "nil")")

        var heading: Double?

        // Try to get real heading first
        if let realHeading = locationManager.heading {
            heading = realHeading
        } else if let userLocation = locationManager.location,
                  let hole = store.currentHole {
            // Fallback: Use bearing to hole + 45 degrees as simulated offset
            // This allows testing in simulator
            let bearingToHole = calculateBearing(from: userLocation.coordinate, to: hole.coordinate)
            heading = (bearingToHole + 45).truncatingRemainder(dividingBy: 360)
            print("⌚ [AimDirection] Using simulated heading (bearing + 45°)")
        }

        guard let finalHeading = heading else {
            // No heading available, vibrate to indicate error
            print("⌚ [AimDirection] ERROR: No heading or location available")
            WKInterfaceDevice.current().play(.failure)
            return
        }

        // Capture the current heading
        capturedAimDirection = finalHeading
        print("⌚ [AimDirection] Captured heading: \(finalHeading)")

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)
    }

    private func recordStroke() {
        // Pass the captured aim direction to the stroke
        store.addStroke(club: selectedClub, trajectoryHeading: capturedAimDirection)

        // Reset aim direction after stroke is recorded
        capturedAimDirection = nil

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)

        // Visual feedback
        withAnimation(.easeInOut(duration: 0.3)) {
            showingRecordedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingRecordedFeedback = false
            }
        }
    }

    private func deleteLastStroke() {
        store.deleteLastStroke()

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)
    }

    private func addPenaltyStroke() {
        guard var round = store.currentRound,
              let hole = store.currentHole,
              let userLocation = LocationManager.shared.location else { return }

        let holeCoord = hole.coordinate
        let userCoord = userLocation.coordinate

        // Calculate position: few yards behind the user in relation to the hole
        let bearing = calculateBearing(from: holeCoord, to: userCoord) // Bearing from hole to user
        let distanceMeters = 5.0 // ~5 yards back

        // Calculate new coordinate
        let penaltyCoord = calculateCoordinate(from: userCoord, bearing: bearing, distanceMeters: distanceMeters)

        // Add penalty stroke using selected club
        let strokesForHole = round.strokes.filter { $0.holeNumber == hole.number }
        let strokeNumber = strokesForHole.count + 1

        let stroke = Stroke(
            holeNumber: hole.number,
            strokeNumber: strokeNumber,
            coordinate: penaltyCoord,
            club: selectedClub,
            isPenalty: true
        )

        round.strokes.append(stroke)
        store.currentRound = round
        store.saveToStorage()

        // Sync to iPhone
        WatchConnectivityManager.shared.sendRound(round)

        // Haptic feedback - notification for penalty
        WKInterfaceDevice.current().play(.notification)
    }

    private func finishCurrentHole() {
        store.finishCurrentHole()

        // Haptic feedback - directionUp for hole completion
        WKInterfaceDevice.current().play(.directionUp)
    }

    private func toggleTargetPlacement() {
        isPlacingTarget.toggle()
        WKInterfaceDevice.current().play(.click)
    }

    private func updateMapPosition() {
        // Don't update map during target placement mode
        guard !isPlacingTarget else { return }

        guard let hole = store.currentHole else { return }

        let holeCoord = hole.coordinate

        // Use tee coordinate if available, otherwise use user's current location
        let startCoord: CLLocationCoordinate2D
        if let teeCoord = hole.teeCoordinate {
            startCoord = teeCoord
        } else if let userLocation = locationManager.location {
            startCoord = userLocation.coordinate
        } else {
            // No tee and no user location - can't position map
            return
        }

        // Calculate bearing from start to hole
        let bearing = calculateBearing(from: startCoord, to: holeCoord)

        // Calculate distance
        let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)
        let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        let distance = startLocation.distance(from: holeLocation)

        // Calculate center point - balanced between start and hole
        let centerLat = startCoord.latitude + (holeCoord.latitude - startCoord.latitude) * 0.45
        let centerLon = startCoord.longitude + (holeCoord.longitude - startCoord.longitude) * 0.5

        // Create camera oriented with start at bottom, hole at top
        let camera = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            distance: max(distance * 2.5, 100), // Zoom to show both points with padding
            heading: bearing, // Rotate so hole is "up"
            pitch: 0
        )

        position = .camera(camera)
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)

        let bearingDegrees = bearing * 180.0 / .pi
        return (bearingDegrees + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private func calculateCoordinate(from: CLLocationCoordinate2D, bearing: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0 // meters
        let bearingRadians = bearing * .pi / 180.0
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0

        let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius) +
                       cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearingRadians))

        let lon2 = lon1 + atan2(sin(bearingRadians) * sin(distanceMeters / earthRadius) * cos(lat1),
                               cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }

    private func calculateCrownOffset(screenHeight: CGFloat) {
        crownOffset = screenHeight * 0.05
    }
}

