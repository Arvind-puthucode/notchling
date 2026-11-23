import Foundation

public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// Start of the day the task is scheduled for. `nil` means it lives in the Inbox.
    public var day: Date?
    /// Exact time for a reminder. Implies `day`.
    public var due: Date?
    public var important: Bool
    public var links: [String]
    public var completedAt: Date?
    public var createdAt: Date
    /// Set once the due-time alert fired, so it never fires twice.
    public var reminded: Bool
    /// Last local edit. Drives conflict resolution with Apple Reminders.
    public var modifiedAt: Date?
    /// `calendarItemIdentifier` of the linked Apple Reminder, when sync is on.
    public var reminderID: String?

    public init(
        id: UUID = UUID(), title: String, day: Date? = nil, due: Date? = nil,
        important: Bool = false, links: [String] = [], completedAt: Date? = nil,
        createdAt: Date = Date(), reminded: Bool = false, modifiedAt: Date? = nil, reminderID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.day = day
        self.due = due
        self.important = important
        self.links = links
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.reminded = reminded
        self.modifiedAt = modifiedAt ?? createdAt
        self.reminderID = reminderID
    }

    public var isDone: Bool { completedAt != nil }
}

public struct FocusSession: Codable, Equatable, Sendable {
    public var start: Date
    /// Active seconds only: paused and asleep time is excluded.
    public var activeSeconds: TimeInterval

    public init(start: Date, activeSeconds: TimeInterval) {
        self.start = start
        self.activeSeconds = activeSeconds
    }
}

public struct PlannerData: Codable, Equatable, Sendable {
    public var version = 1
    public var tasks: [TaskItem] = []
    /// Daily notes keyed by `DayKey` (yyyy-MM-dd).
    public var notes: [String: String] = [:]
    public var sessions: [FocusSession] = []
    /// Linked reminders whose task was deleted here; sync deletes them remotely, then clears this.
    public var deletedReminderIDs: [String]?

    public init() {}
}

/// Stable string key for a calendar day in the user's current calendar.
public enum DayKey {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
