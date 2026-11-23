import AppKit
import NotchlingCore
import SwiftUI

@main
struct NotchlingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Notchling", systemImage: "rectangle.topthird.inset.filled") {
            MenuContent()
                .environmentObject(delegate.model)
                .environmentObject(delegate.model.store)
                .environmentObject(delegate.model.focus)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var notch: NotchWindowController?
    private var hotKey: HotKey?

    override init() {
        Prefs.registerDefaults()
        model = AppModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = NotchWindowController(model: model)
        notch = controller
        hotKey = HotKey { [weak controller] in
            MainActor.assumeIsolated { controller?.toggleFromHotKey() }
        }
    }

    /// notchling://open[/<tab>], notchling://close, notchling://add?text=…, notchling://focus?minutes=25
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "notchling" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func param(_ name: String) -> String? { query.first { $0.name == name }?.value }
            switch url.host {
            case "open": model.open(NotchTab(rawValue: url.lastPathComponent))
            case "close": model.close()
            case "add":
                if let text = param("text") { model.store.mutate { $0.addTask(parsing: text, defaultDay: Date()) } }
            case "focus":
                model.focus.start(.countdown, minutes: Int(param("minutes") ?? "") ?? 25)
            default: break
            }
        }
    }
}

private struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var focus: FocusController

    var body: some View {
        Button("Open Notchling") { model.open() }
            .keyboardShortcut("n", modifiers: .option)
        Divider()
        if focus.clock.isActive {
            Text("Focus · \(focus.displayText)")
            if focus.clock.isRunning {
                Button("Pause Focus") { focus.pause() }
            } else {
                Button("Resume Focus") { focus.resume() }
            }
            Button("End Focus") { focus.stop() }
        } else {
            Button("Start 25-min Focus") { focus.start(.countdown, minutes: 25) }
        }
        Divider()
        let open = store.data.tasks(on: Date()).filter { !$0.isDone }
        Text(open.isEmpty ? "No open tasks today" : "Today")
        ForEach(open.prefix(5)) { task in
            Button("○ \(task.title)") { store.mutate { $0.toggleDone(task.id) } }
        }
        Divider()
        if let until = model.remindersPausedUntil {
            Button("Resume Reminders (paused until \(until.formatted(date: .omitted, time: .shortened)))") {
                model.remindersPausedUntil = nil
            }
        } else {
            Button("Pause Reminders for 1 Hour") { model.remindersPausedUntil = Date().addingTimeInterval(3600) }
        }
        Button("Settings…") { SettingsWindow.show(model: model) }
            .keyboardShortcut(",")
        Button("Quit Notchling") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
