import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1 // Update every 1 meter
    }

    func requestPermission() {
        #if os(iOS)
        locationManager.requestWhenInUseAuthorization()
        #elseif os(macOS)
        // macOS doesn't require explicit permission request
        #endif
    }

    func startTracking() {
        #if os(iOS)
        let isAuthorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #elseif os(macOS)
        let isAuthorized = authorizationStatus == .authorizedAlways
        #endif

        guard isAuthorized else {
            errorMessage = "Location permission not granted"
            return
        }
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let location = location else { return nil }
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: targetLocation)
    }

    func formattedDistance(to coordinate: CLLocationCoordinate2D) -> String {
        guard let distance = distance(to: coordinate) else {
            return "Searching for GPS..."
        }

        // Convert meters to yards
        let yards = distance * 1.09361

        if yards < 1000 {
            return String(format: "%.0f yards", yards)
        } else {
            let miles = yards / 1760
            return String(format: "%.2f miles", miles)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        #if os(iOS)
        let authorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #elseif os(macOS)
        let authorized = authorizationStatus == .authorizedAlways
        #endif

        if authorized {
            startTracking()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            errorMessage = "Location access denied. Please enable in Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Failed to get location: \(error.localizedDescription)"
    }
}
