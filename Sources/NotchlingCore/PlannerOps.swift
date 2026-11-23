import Foundation

/// Pure mutations on `PlannerData`. Shared by the app and the MCP server so
/// both apply identical rules to the same file.
extension PlannerData {
    @discardableResult
    public mutating func addTask(parsing text: String, now: Date = Date(), calendar: Calendar = .current, defaultDay: Date? = nil) -> TaskItem? {
        guard let parsed = TaskParser.parse(text, now: now, calendar: calendar) else { return nil }
        let day = parsed.day ?? defaultDay.map { calendar.startOfDay(for: $0) }
        let task = TaskItem(title: parsed.title, day: day, due: parsed.due, important: parsed.important, links: parsed.links, createdAt: now)
        tasks.append(task)
        return task
    }

    public mutating func toggleDone(_ id: UUID, now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].completedAt = tasks[i].isDone ? nil : now
        tasks[i].modifiedAt = now
    }

    public mutating func setDone(_ id: UUID, now: Date = Date()) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return false }
        if tasks[i].completedAt == nil {
            tasks[i].completedAt = now
            tasks[i].modifiedAt = now
        }
        return true
    }

    public mutating func delete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let rid = tasks[i].reminderID { deletedReminderIDs = (deletedReminderIDs ?? []) + [rid] }
        tasks.remove(at: i)
    }

    public mutating func rename(_ id: UUID, to title: String, now: Date = Date()) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].title != t else { return }
        tasks[i].title = t
        tasks[i].modifiedAt = now
    }

    public mutating func toggleImportant(_ id: UUID, now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].important.toggle()
        tasks[i].modifiedAt = now
    }

    public mutating func attach(_ links: [String], to id: UUID, now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let new = links.filter { !tasks[i].links.contains($0) }
        guard !new.isEmpty else { return }
        tasks[i].links += new
        tasks[i].modifiedAt = now
    }

    public mutating func detach(_ link: String, from id: UUID, now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].links.removeAll { $0 == link }
        tasks[i].modifiedAt = now
    }

    /// Moves a task to a day (keeping its time of day when it has one) or to the Inbox.
    public mutating func move(_ id: UUID, to day: Date?, calendar: Calendar = .current, now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].modifiedAt = now
        guard let day else {
            tasks[i].day = nil
            tasks[i].due = nil
            return
        }
        let start = calendar.startOfDay(for: day)
        tasks[i].day = start
        if let due = tasks[i].due {
            let t = calendar.dateComponents([.hour, .minute], from: due)
            tasks[i].due = calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: start)
            tasks[i].reminded = false
        }
    }

    /// Unfinished tasks from past days roll onto today. Their reminder time is dropped
    /// because a past time on a new day is meaningless.
    public mutating func carryForward(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        for i in tasks.indices where !tasks[i].isDone {
            if let day = tasks[i].day, day < today {
                tasks[i].day = today
                tasks[i].due = nil
                tasks[i].reminded = false
                tasks[i].modifiedAt = now
            }
        }
    }

    public func tasks(on day: Date, calendar: Calendar = .current) -> [TaskItem] {
        let start = calendar.startOfDay(for: day)
        return tasks.filter { $0.day == start }.sorted(by: Self.order)
    }

    public var inbox: [TaskItem] {
        tasks.filter { $0.day == nil && !$0.isDone }.sorted(by: Self.order)
    }

    /// Open first, then important, then timed by time, then by creation.
    public static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.important != b.important { return a.important }
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt < b.createdAt
        }
    }

    /// Tasks whose reminder time has passed and that have not alerted yet.
    public func dueReminders(now: Date = Date()) -> [TaskItem] {
        tasks.filter { !$0.isDone && !$0.reminded && ($0.due.map { $0 <= now } ?? false) }
    }

    public mutating func markReminded(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].reminded = true
    }

    public mutating func snooze(_ id: UUID, minutes: Int = 10, now: Date = Date(), calendar: Calendar = .current) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let due = now.addingTimeInterval(TimeInterval(minutes * 60))
        tasks[i].due = due
        tasks[i].day = calendar.startOfDay(for: due)
        tasks[i].reminded = false
        tasks[i].modifiedAt = now
    }

    // MARK: Notes

    public func note(for day: Date, calendar: Calendar = .current) -> String {
        notes[DayKey.key(day, calendar: calendar)] ?? ""
    }

    public mutating func setNote(_ text: String, for day: Date, calendar: Calendar = .current) {
        let key = DayKey.key(day, calendar: calendar)
        notes[key] = text.isEmpty ? nil : text
    }

    // MARK: Wrap up

    /// Moves every open task scheduled today (or earlier) to tomorrow or the Inbox.
    public mutating func moveLeftovers(toTomorrow: Bool, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        for t in tasks where !t.isDone {
            guard let day = t.day, day <= today else { continue }
            move(t.id, to: toTomorrow ? tomorrow : nil, calendar: calendar)
        }
    }
}

public enum TaskSort: String, CaseIterable, Identifiable, Sendable {
    case smart, time, title, created
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .smart: return "Smart"
        case .time: return "Time"
        case .title: return "Title"
        case .created: return "Newest"
        }
    }

    /// Open tasks always stay above finished ones.
    public func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            switch self {
            case .smart: return PlannerData.order(a, b)
            case .time: return (a.due ?? .distantFuture, a.createdAt) < (b.due ?? .distantFuture, b.createdAt)
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .created: return a.createdAt > b.createdAt
            }
        }
    }
}
