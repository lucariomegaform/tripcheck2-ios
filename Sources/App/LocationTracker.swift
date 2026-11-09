// Notes where the driver is while TripCheck is reading offers, so each recorded offer can
// say where it was made. Runs only while reading offers is on (iOS shows its blue location
// pill meanwhile). It keeps the last hour of positions and picks the one closest in time to
// each offer, or the latest one while the driver hasn't moved (the iPhone sends nothing new
// until the driver moves about 10 metres).

import Foundation
import CoreLocation

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorised = false

    private let manager = CLLocationManager()
    private var fixes: [CLLocation] = []
    private var running = false
    /// When positions started arriving without a break (nil while stopped).
    private var followingSince: Date?

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
        followingSince = nil
        manager.stopUpdatingLocation()
    }

    /// Where the driver was at `date`.
    ///
    /// The iPhone only sends a new position after the driver has moved about 10 metres, so
    /// when parked (several offers at home, at a rank) the last position can be many minutes
    /// old and still be right. So: the position closest in time if one was taken within
    /// 2 minutes; otherwise the last position before `date`, as long as positions were being
    /// followed the whole time since (the driver hasn't moved 10 m, or a new one would have come).
    func location(near date: Date) -> CLLocation? {
        let best = fixes.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
        if let fix = best, abs(fix.timestamp.timeIntervalSince(date)) <= 120 {
            return fix
        }
        if let since = followingSince, since <= date,
           let last = fixes.last(where: { $0.timestamp <= date.addingTimeInterval(5) }) {
            return last
        }
        // Moments after starting: the phone's own last known position, if it's recent.
        if let known = manager.location, abs(known.timestamp.timeIntervalSince(date)) <= 120 {
            return known
        }
        return nil
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
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 200 }
        guard !good.isEmpty else { return }
        if followingSince == nil, running {
            // From now on each new position is within about 10 m of the last one sent.
            followingSince = Date()
        }
        fixes.append(contentsOf: good)
        fixes.sort { $0.timestamp < $1.timestamp }
        // Keep the last hour of positions, and always the latest one (it stays right while parked).
        let cutoff = Date().addingTimeInterval(-3600)
        if fixes.count > 1 {
            let latest = fixes[fixes.count - 1]
            fixes.removeAll { $0.timestamp < cutoff && $0 !== latest }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
