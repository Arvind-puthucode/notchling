import EventKit
import NotchlingCore

/// Two-way sync with a "Notchling" list in Apple Reminders, so tasks reach iPhone and Apple Watch.
/// The merge rules live in `ReminderSync` (core, tested); this class only talks to EventKit.
@MainActor
final class RemindersSyncService: ObservableObject {
    enum Status: Equatable { case off, needsAccess, syncing, synced(Date), failed(String) }

    @Published private(set) var status: Status = .off

    private let store = EKEventStore()
    private weak var planner: PlannerStore?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var running = false
    private static let listName = "Notchling"

    init(planner: PlannerStore) {
        self.planner = planner
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        applyPrefs()
    }

    var enabled: Bool { Prefs.d.bool(forKey: Prefs.remindersSync) }

    func applyPrefs() {
        guard enabled else { status = .off; return }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: schedule()
        case .notDetermined:
            store.requestFullAccessToReminders { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.schedule() : (self.status = .needsAccess)
                }
            }
        default: status = .needsAccess
        }
    }

    /// Coalesces bursts of local edits into one sync.
    func schedule(after delay: TimeInterval = 1.5) {
        guard enabled, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sync() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func list() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == Self.listName }) { return existing }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = Self.listName
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw NSError(domain: "Notchling", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Reminders account found"])
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    private func sync() {
        guard !running, let planner else { return }
        running = true
        status = .syncing
        let cal: EKCalendar
        do { cal = try list() } catch {
            status = .failed(error.localizedDescription)
            running = false
            return
        }
        store.fetchReminders(matching: store.predicateForReminders(in: [cal])) { [weak self] reminders in
            let items = reminders ?? []
            DispatchQueue.main.async { self?.merge(items, into: cal, planner: planner) }
        }
    }

    private func merge(_ reminders: [EKReminder], into cal: EKCalendar, planner: PlannerStore) {
        defer { running = false }
        let byID = Dictionary(reminders.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let remote = reminders.map(snapshot)
        var ops = ReminderSync.Ops()
        planner.mutate { ops = ReminderSync.reconcile(&$0, remote: remote) }

        do {
            for id in ops.delete { if let r = byID[id] { try store.remove(r, commit: false) } }
            var created: [(UUID, EKReminder)] = []
            for task in ops.create {
                let r = EKReminder(eventStore: store)
                r.calendar = cal
                write(task, to: r)
                try store.save(r, commit: false)
                created.append((task.id, r))
            }
            var updated: [(UUID, EKReminder)] = []
            for (id, task) in ops.update {
                guard let r = byID[id] else { continue }
                write(task, to: r)
                try store.save(r, commit: false)
                updated.append((task.id, r))
            }
            try store.commit()
            planner.mutate { data in
                for (taskID, r) in created {
                    ReminderSync.link(taskID, to: r.calendarItemIdentifier, modified: r.lastModifiedDate ?? Date(), in: &data)
                }
                for (taskID, r) in updated {
                    ReminderSync.stamp(taskID, modified: r.lastModifiedDate ?? Date(), in: &data)
                }
            }
            status = .synced(Date())
        } catch {
            store.reset()
            status = .failed(error.localizedDescription)
        }
    }

    private func snapshot(_ r: EKReminder) -> RemoteReminder {
        let cal = Calendar.current
        var day: Date?, due: Date?
        if let c = r.dueDateComponents, let date = cal.date(from: c) {
            if c.hour != nil { due = date } else { day = cal.startOfDay(for: date) }
        }
        return RemoteReminder(
            id: r.calendarItemIdentifier, title: r.title ?? "", day: day, due: due,
            completedAt: r.isCompleted ? (r.completionDate ?? Date()) : nil,
            modified: r.lastModifiedDate ?? r.creationDate ?? .distantPast)
    }

    private func write(_ t: TaskItem, to r: EKReminder) {
        let cal = Calendar.current
        r.title = t.title
        r.priority = t.important ? 1 : 0
        r.alarms?.forEach { r.removeAlarm($0) }
        if let due = t.due {
            r.dueDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        } else if let day = t.day {
            r.dueDateComponents = cal.dateComponents([.year, .month, .day], from: day)
        } else {
            r.dueDateComponents = nil
        }
        r.isCompleted = t.isDone
        if let done = t.completedAt { r.completionDate = done }
        if r.url == nil, let link = t.links.first { r.url = URL(string: link) }
    }
}
