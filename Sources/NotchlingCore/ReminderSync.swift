import Foundation

/// Snapshot of an Apple Reminder in the synced list.
public struct RemoteReminder: Equatable, Sendable {
    public var id: String
    public var title: String
    /// Start of day when the reminder only has a date; exact time when it has one.
    public var day: Date?
    public var due: Date?
    public var completedAt: Date?
    public var modified: Date

    public init(id: String, title: String, day: Date?, due: Date?, completedAt: Date?, modified: Date) {
        self.id = id
        self.title = title
        self.day = day
        self.due = due
        self.completedAt = completedAt
        self.modified = modified
    }
}

/// Two-way sync rules between tasks and one Apple Reminders list. Pure: the
/// caller applies `Ops` to EventKit and reports new ids back with `link`.
///
/// - Newer side wins, compared by modification time (1 s tolerance).
/// - A linked reminder that disappeared remotely deletes the task.
/// - A task deleted here deletes its reminder (via `deletedReminderIDs`).
/// - Unlinked open tasks are created remotely; unknown reminders become tasks.
public enum ReminderSync {
    public struct Ops: Equatable {
        public var create: [TaskItem] = []
        public var update: [(String, TaskItem)] = []
        public var delete: [String] = []

        public init() {}

        public static func == (a: Ops, b: Ops) -> Bool {
            a.create == b.create && a.delete == b.delete
                && a.update.map(\.0) == b.update.map(\.0) && a.update.map(\.1) == b.update.map(\.1)
        }
    }

    public static func reconcile(_ data: inout PlannerData, remote: [RemoteReminder], calendar: Calendar = .current) -> Ops {
        var ops = Ops()
        let byID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pendingDeletes = Set(data.deletedReminderIDs ?? [])
        ops.delete = (data.deletedReminderIDs ?? []).filter { byID[$0] != nil }
        data.deletedReminderIDs = nil

        var linked = Set<String>()
        var keep: [TaskItem] = []
        for var task in data.tasks {
            guard let rid = task.reminderID else {
                if !task.isDone { ops.create.append(task) }
                keep.append(task)
                continue
            }
            guard let r = byID[rid] else { continue } // deleted in Reminders
            linked.insert(rid)
            let local = task.modifiedAt ?? task.createdAt
            if r.modified.timeIntervalSince(local) > 1 {
                apply(r, to: &task, calendar: calendar)
            } else if local.timeIntervalSince(r.modified) > 1, differs(task, r) {
                ops.update.append((rid, task))
            }
            keep.append(task)
        }
        for r in remote where !linked.contains(r.id) && !pendingDeletes.contains(r.id) {
            var t = TaskItem(title: r.title, createdAt: r.modified, reminderID: r.id)
            apply(r, to: &t, calendar: calendar)
            keep.append(t)
        }
        data.tasks = keep
        return ops
    }

    /// Records the id EventKit assigned to a task created by `Ops.create`.
    public static func link(_ taskID: UUID, to reminderID: String, modified: Date, in data: inout PlannerData) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        data.tasks[i].reminderID = reminderID
        data.tasks[i].modifiedAt = modified
    }

    /// After pushing an update, align the local stamp with the remote one so it doesn't bounce back.
    public static func stamp(_ taskID: UUID, modified: Date, in data: inout PlannerData) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        data.tasks[i].modifiedAt = modified
    }

    static func differs(_ t: TaskItem, _ r: RemoteReminder) -> Bool {
        t.title != r.title || t.day != r.day || t.due != r.due || t.isDone != (r.completedAt != nil)
    }

    static func apply(_ r: RemoteReminder, to t: inout TaskItem, calendar: Calendar) {
        if t.due != r.due { t.reminded = false }
        t.title = r.title
        t.due = r.due
        t.day = r.due.map { calendar.startOfDay(for: $0) } ?? r.day
        t.completedAt = r.completedAt
        t.modifiedAt = r.modified
    }
}
