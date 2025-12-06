import SwiftUI
import MapKit

struct ActiveRoundView: View {
    @StateObject private var store = WatchDataStore.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var selectedClubIndex: Double = 0
    @State private var position: MapCameraPosition = .automatic
    @State private var showingRecordedFeedback = false

    private let clubs = Club.allCases

    private var selectedClub: Club {
        let index = Int(selectedClubIndex.rounded()) % clubs.count
        return clubs[index]
    }

    private var distanceToHole: Int? {
        guard let userLocation = locationManager.location,
              let hole = store.currentHole else { return nil }

        let holeLocation = CLLocation(
            latitude: hole.coordinate.latitude,
            longitude: hole.coordinate.longitude
        )

        let distanceInMeters = userLocation.distance(from: holeLocation)
        return Int(distanceInMeters * 1.09361) // Convert to yards
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen map
                if let hole = store.currentHole {
                    mapView(for: hole)
                        .ignoresSafeArea()
                        .onLongPressGesture(minimumDuration: 1.0) {
                            finishCurrentHole()
                        }
                }

                // Overlays
                VStack(spacing: 0) {
                    // Club selector (top right, near digital crown)
                    HStack {
                        Spacer()
                        Text(selectedClub.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.top, 2)
                    .padding(.trailing, 4)

                    Spacer()

                    // Distance to hole (centered, above info bar)
                    if let distance = distanceToHole {
                        Text("\(distance)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    // Bottom info bar - hole number, par, strokes
                    if let hole = store.currentHole {
                        let parText = hole.par.map { String($0) } ?? "-"
                        Text("H: \(hole.number)  P: \(parText)  S: \(store.strokeCount(for: hole))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.bottom, 1)
                    }

                    // Bottom buttons
                    if let hole = store.currentHole {
                        HStack(spacing: 0) {
                            // Delete last stroke button (left)
                            Button(action: deleteLastStroke) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.orange)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(store.isHoleCompleted(hole.number))
                            .opacity(store.isHoleCompleted(hole.number) ? 0.3 : 1.0)

                            Spacer()

                            // Record stroke button (right)
                            Button(action: recordStroke) {
                                ZStack {
                                    Circle()
                                        .fill(showingRecordedFeedback ? Color.white : Color.green)
                                        .frame(width: 34, height: 34)
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                    Image(systemName: showingRecordedFeedback ? "checkmark" : "plus")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(showingRecordedFeedback ? .green : .white)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(store.isHoleCompleted(hole.number))
                            .opacity(store.isHoleCompleted(hole.number) ? 0.3 : 1.0)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 1)
                    }
                }
                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            }
        }
        .focusable()
        .digitalCrownRotation($selectedClubIndex, from: 0, through: Double(clubs.count - 1), by: 1, sensitivity: .low)
        .onAppear {
            locationManager.requestPermission()
            updateMapPosition()
        }
        .onChange(of: locationManager.location) { _, _ in
            updateMapPosition()
        }
        .onChange(of: store.currentHole) { _, _ in
            updateMapPosition()
        }
    }

    // MARK: - Map View

    @ViewBuilder
    private func mapView(for hole: Hole) -> some View {
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
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
        }
    }

    // MARK: - Actions

    private func recordStroke() {
        store.addStroke(club: selectedClub)

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

    private func finishCurrentHole() {
        store.finishCurrentHole()

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)
    }

    private func updateMapPosition() {
        guard let hole = store.currentHole,
              let userLocation = locationManager.location else { return }

        let userCoord = userLocation.coordinate
        let holeCoord = hole.coordinate

        // Calculate bearing from user to hole
        let bearing = calculateBearing(from: userCoord, to: holeCoord)

        // Calculate distance
        let holeLocation = CLLocation(latitude: holeCoord.latitude, longitude: holeCoord.longitude)
        let distance = userLocation.distance(from: holeLocation)

        // Calculate center point (slightly toward hole from user)
        let centerLat = (userCoord.latitude + holeCoord.latitude) / 2
        let centerLon = (userCoord.longitude + holeCoord.longitude) / 2

        // Create camera oriented with user at bottom, hole at top
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
}
