// Notes where the driver is while TripCheck is reading offers, so each recorded offer can
// say where it was made. Runs only while reading offers is on (iOS shows its blue location
// pill meanwhile). It keeps the last 10 minutes of positions and picks the one closest in
// time to each offer.

import Foundation
import CoreLocation

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorised = false

    private let manager = CLLocationManager()
    private var fixes: [CLLocation] = []
    private var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        updateAuthorised()
    }

    /// Call from the Start button (the app must be on screen to ask permission and to start).
    func start() {
        running = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return   // starts when permission is given (see below)
        }
        begin()
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
    }

    /// The position closest in time to `date`, if one was taken within 2 minutes of it.
    func location(near date: Date) -> CLLocation? {
        let best = fixes.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
        guard let fix = best, abs(fix.timestamp.timeIntervalSince(date)) <= 120 else { return nil }
        return fix
    }

    private func begin() {
        guard running, isAllowed(manager.authorizationStatus) else { return }
        // Keep receiving positions while the driver app is on screen.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private func isAllowed(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func updateAuthorised() {
        let allowed = isAllowed(manager.authorizationStatus)
        DispatchQueue.main.async { self.authorised = allowed }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorised()
        begin()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        fixes.append(contentsOf: locations.filter { $0.horizontalAccuracy >= 0 })
        let cutoff = Date().addingTimeInterval(-600)
        fixes.removeAll { $0.timestamp < cutoff }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
