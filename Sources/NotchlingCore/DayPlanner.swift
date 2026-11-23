import Foundation

/// Fits today's untimed tasks into the free gaps between calendar events.
public enum DayPlanner {
    public struct Busy: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public init(start: Date, end: Date) { self.start = start; self.end = end }
    }

    /// Returns task id -> suggested start time. Important tasks are placed first.
    /// Tasks that do not fit before `dayEnd` are left out.
    public static func plan(
        tasks: [TaskItem], busy: [Busy], now: Date, dayEnd: Date,
        slot: TimeInterval = 30 * 60, step: TimeInterval = 15 * 60
    ) -> [(UUID, Date)] {
        let queue = tasks.filter { !$0.isDone && $0.due == nil }.sorted(by: PlannerData.order)
        var blocks = busy.filter { $0.end > now && $0.start < dayEnd }.sorted { $0.start < $1.start }
        var cursor = roundUp(now, to: step)
        var result: [(UUID, Date)] = []
        for task in queue {
            // Advance past any block that overlaps [cursor, cursor + slot).
            var moved = true
            while moved {
                moved = false
                for b in blocks where b.start < cursor + slot && b.end > cursor {
                    cursor = roundUp(b.end, to: step)
                    moved = true
                }
            }
            guard cursor + slot <= dayEnd else { break }
            result.append((task.id, cursor))
            blocks.append(Busy(start: cursor, end: cursor + slot))
            cursor += slot
        }
        return result
    }

    static func roundUp(_ date: Date, to step: TimeInterval) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / step).rounded(.up) * step)
    }
}

extension PlannerData {
    public mutating func applyPlan(_ plan: [(UUID, Date)], calendar: Calendar = .current, now: Date = Date()) {
        for (id, start) in plan {
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { continue }
            tasks[i].due = start
            tasks[i].day = calendar.startOfDay(for: start)
            tasks[i].reminded = false
            tasks[i].modifiedAt = now
        }
    }
}
