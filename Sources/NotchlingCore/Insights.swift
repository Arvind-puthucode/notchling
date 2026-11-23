import Foundation

public struct Insights: Equatable, Sendable {
    public var completedToday: Int
    public var completedThisWeek: Int
    public var focusMinutesToday: Int
    public var focusMinutesThisWeek: Int
    /// Consecutive days, ending today (or yesterday if today is empty), with a completed task or focus session.
    public var streak: Int
    /// Hour of day (0-23) with the most focus time, if any.
    public var bestFocusHour: Int?

    public static func compute(_ data: PlannerData, now: Date = Date(), calendar: Calendar = .current) -> Insights {
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        let doneDates = data.tasks.compactMap(\.completedAt)

        var activeDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        activeDays.formUnion(data.sessions.map { calendar.startOfDay(for: $0.start) })
        var streak = 0
        var day = activeDays.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while activeDays.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }

        var byHour: [Int: TimeInterval] = [:]
        for s in data.sessions { byHour[calendar.component(.hour, from: s.start), default: 0] += s.activeSeconds }

        func minutes(since start: Date) -> Int {
            Int(data.sessions.filter { $0.start >= start }.reduce(0) { $0 + $1.activeSeconds } / 60)
        }
        return Insights(
            completedToday: doneDates.filter { $0 >= today }.count,
            completedThisWeek: doneDates.filter { $0 >= weekAgo }.count,
            focusMinutesToday: minutes(since: today),
            focusMinutesThisWeek: minutes(since: weekAgo),
            streak: streak,
            bestFocusHour: byHour.max { $0.value < $1.value }?.key)
    }
}
