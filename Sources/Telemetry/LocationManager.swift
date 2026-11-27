import Foundation
import CoreLocation
import Combine

// MARK: - Location Manager
// Provides GPS speed and position as fallback when OBD is unavailable.
// Rule 6: Use GPS for route/distance fallback, not as a silent replacement for OBD speed.

final class LocationManager: NSObject, ObservableObject {

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isTracking = false

    private let manager = CLLocationManager()
    private(set) var route: [CLLocation] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5  // metres — reduce update frequency slightly
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    /// True when the user refused (or a profile restricts) location access.
    /// Trips then record no GPS distance; the UI explains this and links to Settings.
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func requestPermission() {
#if os(iOS)
        manager.requestWhenInUseAuthorization()
#else
        manager.requestAlwaysAuthorization()
#endif
    }

    func startTracking() {
#if os(iOS)
        let authorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
#else
        let authorized = authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
#endif
        guard authorized else {
            // Remember the intent so the authorization callback starts updates
            // immediately after the user grants permission.
            isTracking = true
            requestPermission()
            return
        }
        route.removeAll()
        isTracking = true
        // Foreground recording only (v1): no "location" background mode is
        // declared, so When-In-Use authorisation is enough.
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
    }

    // MARK: - Derived

    /// Total route distance in km, calculated from GPS track.
    var routeDistanceKm: Double {
        guard route.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1 ..< route.count {
            total += route[i].distance(from: route[i-1])
        }
        return total / 1000.0
    }

    /// GPS speed in km/h (negative = invalid/unavailable).
    var gpsSpeedKmh: Double? {
        guard let loc = location, loc.speed >= 0 else { return nil }
        return loc.speed * 3.6
    }
}

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        if isTracking {
            route.append(latest)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
#if os(iOS)
        let authorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
#else
        let authorized = authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
#endif
        if isTracking && authorized {
            route.removeAll()
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal — GPS may be unavailable indoors
        AppLog.location.error("Location error: \(error.localizedDescription)")
    }
}
