import AppKit
import NotchlingCore
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case today, week, notes, focus, calendar, clips, insights
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "checklist"
        case .week: return "calendar.day.timeline.left"
        case .notes: return "note.text"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .clips: return "paperclip"
        case .insights: return "chart.bar.xaxis"
        }
    }
    var title: String { rawValue.capitalized }
}

/// Something that pops the notch open: a due reminder, a meeting, a finished timer, a daily prompt.
enum NotchAlert: Identifiable, Equatable {
    case reminder(taskID: UUID, title: String)
    case meeting(CalEvent)
    case focusDone(minutes: Int)
    case planDay
    case wrapUp

    var id: String {
        switch self {
        case let .reminder(id, _): return "r-\(id)"
        case let .meeting(e): return "m-\(e.id)"
        case .focusDone: return "f"
        case .planDay: return "plan"
        case .wrapUp: return "wrap"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .today
    @Published private(set) var alerts: [NotchAlert] = []
    /// Size of the notch on the screen the panel currently sits on.
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var screenHasHardwareNotch = true
    @Published var remindersPausedUntil: Date?

    let store = PlannerStore()
    let focus = FocusController()
    let calendar = CalendarService()
    let clips = ClipsService()

    private var ticker: Timer?
    private var alertedMeetings = Set<String>()
    private var openedByAlert = false
    private var lastDayKey = DayKey.key(Date())

    init() {
        focus.onLog = { [weak self] session in
            self?.store.mutate { $0.sessions.append(session) }
        }
        focus.onFinish = { [weak self] session in
            self?.enqueue(.focusDone(minutes: Int((session?.activeSeconds ?? 0) / 60)))
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var currentAlert: NotchAlert? { alerts.first }

    // MARK: Open / close

    func open(_ tab: NotchTab? = nil) {
        if let tab { self.tab = tab }
        isOpen = true
    }

    func close() {
        isOpen = false
        openedByAlert = false
    }

    func toggle() { isOpen ? close() : open() }

    // MARK: Alerts

    func enqueue(_ alert: NotchAlert) {
        guard !alerts.contains(alert) else { return }
        alerts.append(alert)
        NSSound(named: "Glass")?.play()
        if !isOpen {
            openedByAlert = true
            open()
        }
    }

    func resolve(_ alert: NotchAlert) {
        alerts.removeAll { $0 == alert }
        if alerts.isEmpty && openedByAlert { close() }
    }

    // MARK: Day actions

    func planDay() {
        let cal = Calendar.current
        let now = Date()
        let endHour = Prefs.d.integer(forKey: Prefs.workdayEndHour)
        var dayEnd = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: now)!
        if dayEnd <= now { dayEnd = cal.date(bySettingHour: 23, minute: 0, second: 0, of: now)! }
        let busy = calendar.events(on: now).filter { !$0.isAllDay }.map { DayPlanner.Busy(start: $0.start, end: $0.end) }
        let plan = DayPlanner.plan(tasks: store.data.tasks(on: now), busy: busy, now: now, dayEnd: dayEnd)
        store.mutate { $0.applyPlan(plan) }
    }

    // MARK: Ticker

    private func tick() {
        let now = Date()
        store.reloadIfChangedExternally()

        let key = DayKey.key(now)
        if key != lastDayKey {
            lastDayKey = key
            store.mutate { $0.carryForward(now: now) }
            calendar.refresh()
        }

        if remindersPausedUntil.map({ $0 <= now }) ?? false { remindersPausedUntil = nil }
        if remindersPausedUntil == nil {
            for task in store.data.dueReminders(now: now) {
                store.mutate { $0.markReminded(task.id) }
                enqueue(.reminder(taskID: task.id, title: task.title))
            }
            for event in calendar.upcomingToday where !event.isAllDay && !alertedMeetings.contains(event.id) {
                let lead = event.start.timeIntervalSince(now)
                if lead <= 60 && lead > -120 {
                    alertedMeetings.insert(event.id)
                    enqueue(.meeting(event))
                }
            }
        }
        checkDailyPrompts(now)
    }

    private func checkDailyPrompts(_ now: Date) {
        guard Prefs.d.bool(forKey: Prefs.dayPrompts) else { return }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let key = DayKey.key(now)
        let d = Prefs.d
        if hour >= 6, d.string(forKey: "day.lastPlanPrompt") != key {
            d.set(key, forKey: "day.lastPlanPrompt")
            if store.data.tasks(on: now).contains(where: { !$0.isDone && $0.due == nil }) { enqueue(.planDay) }
        }
        if hour >= d.integer(forKey: Prefs.workdayEndHour), d.string(forKey: "day.lastWrapPrompt") != key {
            d.set(key, forKey: "day.lastWrapPrompt")
            enqueue(.wrapUp)
        }
    }
}
