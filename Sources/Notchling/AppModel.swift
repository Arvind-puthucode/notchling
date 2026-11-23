import AppKit
import Combine
import NotchlingCore
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case today, week, notes, focus, calendar, clips, insights
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "checklist"
        case .week: return "square.grid.3x1.below.line.grid.1x2"
        case .notes: return "note.text"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .clips: return "paperclip"
        case .insights: return "chart.bar.fill"
        }
    }
    var title: String { rawValue.capitalized }
}

/// Something that pops the notch open: a due reminder, a meeting, a finished timer, a nudge, a daily prompt.
enum NotchAlert: Identifiable, Equatable {
    case reminder(taskID: UUID, title: String)
    case meeting(CalEvent)
    case leave(CalEvent, travelMinutes: Int)
    case focusDone(minutes: Int)
    case distraction(appName: String, bundleID: String)
    case planDay
    case wrapUp

    var id: String {
        switch self {
        case let .reminder(id, _): return "r-\(id)"
        case let .meeting(e): return "m-\(e.id)"
        case let .leave(e, _): return "l-\(e.id)"
        case .focusDone: return "f"
        case let .distraction(_, b): return "d-\(b)"
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
    /// True when the fake notch should step aside (a full-screen app hides the menu bar).
    @Published var menuBarHidden = false
    @Published var hoveringClosedNotch = false
    @Published var remindersPausedUntil: Date?

    let store = PlannerStore()
    let focus = FocusController()
    let calendar = CalendarService()
    let clips = ClipsService()
    let speech = SpeechInput()
    let external = ExternalCalendars()
    let travel = TravelTimeService()
    let spotlight = SpotlightIndexer()
    let characters = CharacterStore()
    lazy var reminders = RemindersSyncService(planner: store)

    /// Set by the window controller; opens the workspace as a regular window.
    var showWindow: (() -> Void)?

    private var ticker: Timer?
    private var alertedEvents = Set<String>()
    /// The notch opened itself for an alert; it shows as a compact live activity until the user expands it.
    @Published private(set) var openedByAlert = false
    private var lastDayKey = DayKey.key(Date())
    private var distractionSnoozed: [String: Date] = [:]
    private var bag = Set<AnyCancellable>()

    init() {
        focus.onLog = { [weak self] session in
            self?.store.mutate { $0.sessions.append(session) }
        }
        focus.onFinish = { [weak self] session in
            self?.enqueue(.focusDone(minutes: Int((session?.activeSeconds ?? 0) / 60)))
        }
        external.$events.sink { [weak self] in self?.calendar.setExternal($0) }.store(in: &bag)
        store.$data.dropFirst().removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] data in
                self?.spotlight.update(data)
                self?.reminders.schedule()
            }.store(in: &bag)
        spotlight.update(store.data)
        _ = reminders

        focus.$clock.map(\.isActive).removeDuplicates().dropFirst()
            .sink { [weak self] active in if active { self?.characters.react(.focusStart, mood: .idle) } }
            .store(in: &bag)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in self?.checkDistraction(app) }
            .store(in: &bag)

        ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var currentAlert: NotchAlert? { alerts.first }
    var isCompact: Bool { isOpen && openedByAlert && currentAlert != nil }

    /// Size of the open notch: compact for a self-opened alert, otherwise the user's chosen size.
    var openSize: CGSize {
        if isCompact { return CGSize(width: 520, height: notchSize.height + 74) }
        return CGSize(width: Prefs.d.double(forKey: Prefs.width), height: Prefs.d.double(forKey: Prefs.height))
    }

    func expandFromAlert() { openedByAlert = false }

    // MARK: Open / close

    func open(_ tab: NotchTab? = nil) {
        if let tab { self.tab = tab }
        if Prefs.d.string(forKey: Prefs.openMode) == "window" {
            showWindow?()
            return
        }
        guard !isOpen else { return }
        isOpen = true
        haptic()
    }

    func close() {
        isOpen = false
        openedByAlert = false
    }

    func toggle() { isOpen ? close() : open() }

    func haptic() {
        guard Prefs.d.bool(forKey: Prefs.haptics) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Alerts

    func enqueue(_ alert: NotchAlert) {
        guard !alerts.contains(alert) else { return }
        alerts.append(alert)
        NSSound(named: "Glass")?.play()
        if !isOpen && Prefs.d.string(forKey: Prefs.openMode) != "window" {
            openedByAlert = true
            open()
        } else if Prefs.d.string(forKey: Prefs.openMode) == "window" {
            showWindow?()
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

    // MARK: Focus guard

    private func checkDistraction(_ app: NSRunningApplication) {
        guard focus.clock.isRunning, let id = app.bundleIdentifier else { return }
        let listed = (Prefs.d.string(forKey: Prefs.distractionApps) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard listed.contains(id) else { return }
        if let until = distractionSnoozed[id], until > Date() { return }
        enqueue(.distraction(appName: app.localizedName ?? id, bundleID: id))
    }

    func allowDistraction(_ bundleID: String, minutes: Int = 5) {
        distractionSnoozed[bundleID] = Date().addingTimeInterval(TimeInterval(minutes * 60))
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
        let upcoming = calendar.upcomingToday
        travel.refresh(upcoming)
        if remindersPausedUntil == nil {
            for task in store.data.dueReminders(now: now) {
                store.mutate { $0.markReminded(task.id) }
                enqueue(.reminder(taskID: task.id, title: task.title))
            }
            for event in upcoming where !event.isAllDay {
                let lead = event.start.timeIntervalSince(now)
                if let seconds = travel.travel[event.id], !alertedEvents.contains("l" + event.id),
                   lead <= seconds + 5 * 60, lead > 0 {
                    alertedEvents.insert("l" + event.id)
                    enqueue(.leave(event, travelMinutes: Int((seconds / 60).rounded())))
                }
                if !alertedEvents.contains(event.id), lead <= 60, lead > -120 {
                    alertedEvents.insert(event.id)
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
