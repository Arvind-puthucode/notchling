import CoreLocation
import MapKit

/// "Time to leave" for events with a physical location, using Apple Maps driving times.
@MainActor
final class TravelTimeService: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Event id -> expected travel seconds.
    @Published private(set) var travel: [String: TimeInterval] = [:]
    private let location = CLLocationManager()
    private var lastQuery: [String: Date] = [:]
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        location.delegate = self
    }

    var enabled: Bool { Prefs.d.bool(forKey: Prefs.travelAlerts) }

    func requestAccess() {
        location.requestWhenInUseAuthorization()
    }

    /// Refreshes travel time for today's upcoming in-person events, at most every 10 minutes each.
    func refresh(_ events: [CalEvent]) {
        guard enabled else { travel = [:]; return }
        let status = location.authorizationStatus
        guard status == .authorizedAlways || status == .authorized else {
            if status == .notDetermined { requestAccess() }
            return
        }
        let now = Date()
        for e in events where !e.isAllDay && e.joinURL == nil && e.start > now && e.start.timeIntervalSince(now) < 6 * 3600 {
            guard let place = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty,
                  URL(string: place)?.scheme == nil else { continue }
            if let last = lastQuery[e.id], now.timeIntervalSince(last) < 600 { continue }
            lastQuery[e.id] = now
            Task { await self.query(e.id, place) }
        }
    }

    private func query(_ id: String, _ place: String) async {
        do {
            guard let mark = try await geocoder.geocodeAddressString(place).first else { return }
            let req = MKDirections.Request()
            req.source = .forCurrentLocation()
            req.destination = MKMapItem(placemark: MKPlacemark(placemark: mark))
            req.transportType = .automobile
            let eta = try await MKDirections(request: req).calculateETA()
            travel[id] = eta.expectedTravelTime
        } catch {
            // Unknown address or no route: no alert for this event.
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
