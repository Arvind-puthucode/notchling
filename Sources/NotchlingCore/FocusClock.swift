import Foundation

/// Focus timer state machine. Time comes from the caller so it is testable and
/// so sleep can be excluded: the app calls `pause` on sleep and `resume` on wake.
public struct FocusClock: Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case countdown, stopwatch }
    public enum Phase: Equatable, Sendable { case idle, running(since: Date), paused }

    public private(set) var mode: Mode = .countdown
    public private(set) var phase: Phase = .idle
    public private(set) var target: TimeInterval = 25 * 60
    public private(set) var startedAt: Date?
    /// Active seconds banked before the current running stretch.
    private var banked: TimeInterval = 0

    public init() {}

    public var isActive: Bool { phase != .idle }
    public var isRunning: Bool { if case .running = phase { return true } else { return false } }

    public func elapsed(at now: Date) -> TimeInterval {
        if case let .running(since) = phase { return banked + max(0, now.timeIntervalSince(since)) }
        return banked
    }

    /// Seconds shown on the clock: remaining for countdown, elapsed for stopwatch.
    public func display(at now: Date) -> TimeInterval {
        mode == .countdown ? max(0, target - elapsed(at: now)) : elapsed(at: now)
    }

    public func isFinished(at now: Date) -> Bool {
        mode == .countdown && isActive && elapsed(at: now) >= target
    }

    public mutating func start(_ mode: Mode, minutes: Int = 25, at now: Date) {
        self.mode = mode
        target = TimeInterval(max(1, minutes) * 60)
        banked = 0
        startedAt = now
        phase = .running(since: now)
    }

    public mutating func pause(at now: Date) {
        guard case let .running(since) = phase else { return }
        banked += max(0, now.timeIntervalSince(since))
        phase = .paused
    }

    public mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        phase = .running(since: now)
    }

    public mutating func addFiveMinutes() {
        guard isActive, mode == .countdown else { return }
        target += 5 * 60
    }

    /// Ends the session and returns it for the log (nil if nothing ran).
    public mutating func stop(at now: Date) -> FocusSession? {
        defer {
            phase = .idle
            banked = 0
            startedAt = nil
        }
        guard isActive, let startedAt else { return nil }
        var seconds = elapsed(at: now)
        if mode == .countdown { seconds = min(seconds, target) }
        return seconds >= 60 ? FocusSession(start: startedAt, activeSeconds: seconds) : nil
    }
}
