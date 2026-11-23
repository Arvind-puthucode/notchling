import AppKit
import EventKit
import NotchlingCore

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    var location: String? = nil
    let joinURL: URL?
}

/// Read-only view of the next two weeks of Apple Calendar (which includes Google,
/// Outlook and subscribed ICS calendars added in System Settings > Internet Accounts).
@MainActor
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    /// Apple Calendar events merged with ICS links and booking services.
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var access: Access = .unknown
    private var appleEvents: [CalEvent] = []
    private var externalEvents: [CalEvent] = []

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if access == .granted { refresh() }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted { self?.refresh() }
            }
        }
    }

    func setExternal(_ list: [CalEvent]) {
        externalEvents = list
        merge()
    }

    private func merge() {
        // The toggle covers Apple Calendar only; links and booking services have their own settings.
        let apple = Prefs.d.bool(forKey: Prefs.calendarEnabled) ? appleEvents : []
        events = (apple + externalEvents).sorted { $0.start < $1.start }
    }

    func refresh() {
        defer { merge() }
        guard access == .granted, Prefs.d.bool(forKey: Prefs.calendarEnabled) else {
            appleEvents = []
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        appleEvents = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                CalEvent(
                    id: (e.eventIdentifier ?? UUID().uuidString) + "@\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "Untitled",
                    start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                    color: e.calendar.color ?? .systemBlue,
                    location: e.location,
                    joinURL: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]))
            }
    }

    func events(on day: Date) -> [CalEvent] {
        let cal = Calendar.current
        return events.filter { cal.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day) }
    }

    var upcomingToday: [CalEvent] {
        let now = Date()
        return events(on: now).filter { $0.end > now }
    }
}
