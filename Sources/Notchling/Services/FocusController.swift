import AppKit
import NotchlingCore

@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var clock = FocusClock() { didSet { publishState() } }
    @Published private(set) var now = Date()
    @Published var sound: NoisePlayer.Sound = .off {
        didSet { if clock.isRunning { noise.play(sound) } }
    }
    @Published var volume: Float = 0.5 { didSet { noise.volume = volume } }

    /// Called with the finished session when a countdown reaches zero.
    var onFinish: ((FocusSession?) -> Void)?
    /// Called with every logged session (manual stop or finish).
    var onLog: ((FocusSession) -> Void)?

    private let noise = NoisePlayer()
    private var ticker: Timer?
    private var pausedBySleep = false

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
    }

    var display: TimeInterval { clock.display(at: now) }
    /// 0…1 through a countdown; a stopwatch fills once per hour.
    var progress: Double {
        let e = clock.elapsed(at: now)
        return clock.mode == .countdown ? e / max(1, clock.target) : (e.truncatingRemainder(dividingBy: 3600)) / 3600
    }
    var displayText: String { Self.format(display) }

    /// Mirrors timer state into the app's defaults so the MCP server can report it.
    private func publishState() {
        let now = Date()
        let state: [String: Any] = [
            "active": clock.isActive, "running": clock.isRunning, "mode": clock.mode.rawValue,
            "elapsed": clock.elapsed(at: now), "target": clock.target, "at": now.timeIntervalSince1970,
        ]
        Prefs.d.set(state, forKey: "focus.state")
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    func start(_ mode: FocusClock.Mode, minutes: Int) {
        if clock.isActive { stop() }
        now = Date()
        clock.start(mode, minutes: minutes, at: now)
        noise.play(sound)
        runShortcut(Prefs.d.string(forKey: Prefs.focusStartShortcut))
        startTicker()
    }

    func pause() {
        clock.pause(at: Date())
        noise.stop()
    }

    func resume() {
        clock.resume(at: Date())
        noise.play(sound)
    }

    func addFive() { clock.addFiveMinutes() }

    @discardableResult
    func stop() -> FocusSession? {
        let session = clock.stop(at: Date())
        finishCommon(session)
        return session
    }

    private func finishCommon(_ session: FocusSession?) {
        noise.stop()
        ticker?.invalidate()
        ticker = nil
        runShortcut(Prefs.d.string(forKey: Prefs.focusEndShortcut))
        if let session { onLog?(session) }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        if clock.isFinished(at: now) {
            let session = clock.stop(at: now)
            finishCommon(session)
            onFinish?(session)
        }
    }

    private func handleSleep() {
        guard clock.isRunning else { return }
        pausedBySleep = true
        pause()
    }

    private func handleWake() {
        guard pausedBySleep else { return }
        pausedBySleep = false
        resume()
    }

    /// Runs a user Shortcut by name, e.g. one that turns on a Focus mode.
    private func runShortcut(_ name: String?) {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }
}
