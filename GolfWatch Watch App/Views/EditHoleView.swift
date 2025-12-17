import SwiftUI
import MapKit

struct EditHoleView: View {
    @ObservedObject var store: WatchDataStore
    let locationManager: LocationManager
    let hole: Hole
    @Binding var isPresented: Bool

    @State private var position: MapCameraPosition = .automatic
    @State private var temporaryHolePosition: CLLocationCoordinate2D?
    @FocusState private var isMapFocused: Bool
    @State private var shouldMaintainFocus = true

    var body: some View {
        ZStack {
            // Map layer
            MapReader { proxy in
                Map(position: $position) {
                    // Show user location
                    if let userLocation = locationManager.location {
                        Annotation("", coordinate: userLocation.coordinate) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                                .shadow(color: .white, radius: 2)
                        }
                    }

                    // Show temporary or current hole position
                    let holePosition = temporaryHolePosition ?? hole.coordinate
                    Annotation("", coordinate: holePosition) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 24))
                            .shadow(color: .black, radius: 2)
                    }
                }
                .mapStyle(.standard)
                .mapControls {
                    // Disable default map controls
                }
                .mapControlVisibility(.hidden)
                .focusable()
                .focused($isMapFocused)
                .onTapGesture { screenCoord in
                    if let coordinate = proxy.convert(screenCoord, from: .local) {
                        temporaryHolePosition = coordinate
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
            .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top hole number - center, ignoring safe area
                Text("Edit Hole \(hole.number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                // Buttons - bottom
                HStack(spacing: 8) {
                    // Cancel button
                    Button(action: {
                        shouldMaintainFocus = false
                        isPresented = false
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.95))
                                .frame(width: 50, height: 50)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    // Save button - only show when hole has been moved
                    if temporaryHolePosition != nil {
                        Button(action: saveHoleLocation) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.95))
                                    .frame(width: 50, height: 50)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 16)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // Focus the map immediately for crown zoom
            isMapFocused = true

            // Center map on hole location
            let spanInMeters: CLLocationDistance = 320.0 // ~350 yards
            let spanDegrees = spanInMeters / 111000.0

            position = .region(MKCoordinateRegion(
                center: hole.coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
            ))
        }
        .onChange(of: isMapFocused) { _, newValue in
            // If focus is lost and we should maintain it, re-focus
            if !newValue && shouldMaintainFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isMapFocused = true
                }
            }
        }
    }

    private func saveHoleLocation() {
        guard let coordinate = temporaryHolePosition else { return }

        // Stop maintaining focus before dismissing
        shouldMaintainFocus = false

        // Update hole location via store
        store.updateHole(holeNumber: hole.number, newCoordinate: coordinate)

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)

        // Dismiss view
        isPresented = false
    }
}
