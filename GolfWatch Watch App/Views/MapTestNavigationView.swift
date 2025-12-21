import SwiftUI
import MapKit
import CoreLocation

struct MapTestNavigationView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            let testLocation = locationManager.location ?? CLLocation(latitude: 37.7749, longitude: -122.4194)
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
        .navigationTitle("Map Test")
        .onAppear {
            let testLocation = locationManager.location ?? CLLocation(latitude: 37.7749, longitude: -122.4194)
            let spanInMeters: CLLocationDistance = 320.0
            let spanDegrees = spanInMeters / 111000.0

            position = .region(MKCoordinateRegion(
                center: testLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
            ))
        }
    }
}
