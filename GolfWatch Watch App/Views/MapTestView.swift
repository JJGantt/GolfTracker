import SwiftUI
import MapKit
import CoreLocation

struct MapTestView: View {
    @ObservedObject var locationManager: LocationManager
    @Binding var isPresented: Bool

    @State private var position: MapCameraPosition = .automatic

    // Dummy location for testing
    private let dummyLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

    var body: some View {
        Map(position: $position) {
            // User location arrow - use real location or dummy for testing
            let testLocation = locationManager.location ?? dummyLocation
            Annotation("", coordinate: testLocation.coordinate) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(locationManager.heading ?? 45))
                    .shadow(color: .white, radius: 2)
                    .shadow(color: .black.opacity(0.3), radius: 1)
            }
        }
        .mapStyle(.standard)
        .onAppear {
            // Center map on user location or dummy location
            let testLocation = locationManager.location ?? dummyLocation
            let spanInMeters: CLLocationDistance = 320.0
            let spanDegrees = spanInMeters / 111000.0

            position = .region(MKCoordinateRegion(
                center: testLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
            ))
        }
    }
}
