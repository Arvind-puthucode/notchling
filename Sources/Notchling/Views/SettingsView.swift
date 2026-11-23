import AppKit
import ServiceManagement
import SwiftUI

/// Settings live in a plain window we own, so the notch, the menu bar and ⌘, can all open it.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        model.close()
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Notchling Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView()
                .environmentObject(model)
                .environmentObject(model.calendar)
                .environmentObject(model.clips)
                .environmentObject(model.store))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            DaySettings().tabItem { Label("Your day", systemImage: "sun.max") }
            AgentSettings().tabItem { Label("AI agents", systemImage: "sparkles") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var clips: ClipsService
    @AppStorage(Prefs.hoverToOpen) private var hover = false
    @AppStorage(Prefs.fakeNotch) private var fakeNotch = true
    @AppStorage(Prefs.followPointer) private var follow = true
    @AppStorage(Prefs.width) private var width = 680.0
    @AppStorage(Prefs.height) private var height = 360.0
    @AppStorage(Prefs.clipsEnabled) private var clipsOn = true
    @AppStorage(Prefs.clipsScreenshots) private var screenshots = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Opening") {
                Text("Click the notch or press ⌥N.").foregroundStyle(.secondary)
                Toggle("Open when the pointer rests on the notch", isOn: $hover)
                Toggle("Follow the pointer between displays", isOn: $follow)
                Toggle("Draw a notch on displays without one", isOn: $fakeNotch)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Open notch size") {
                Slider(value: $width, in: 560...900, step: 10) { Text("Width") }
                Slider(value: $height, in: 280...520, step: 10) { Text("Height") }
            }
            Section("Clips") {
                Toggle("Keep recent copies", isOn: $clipsOn)
                Toggle("Add new screenshots and recordings", isOn: $screenshots).disabled(!clipsOn)
            }
            .onChange(of: clipsOn) { _, _ in clips.applyPrefs() }
            .onChange(of: screenshots) { _, _ in clips.applyPrefs() }
        }
        .formStyle(.grouped)
    }
}

private struct DaySettings: View {
    @EnvironmentObject var calendar: CalendarService
    @AppStorage(Prefs.dayPrompts) private var prompts = true
    @AppStorage(Prefs.workdayEndHour) private var endHour = 18
    @AppStorage(Prefs.calendarEnabled) private var calendarOn = true
    @AppStorage(Prefs.focusStartShortcut) private var startShortcut = ""
    @AppStorage(Prefs.focusEndShortcut) private var endShortcut = ""

    var body: some View {
        Form {
            Section("Daily prompts") {
                Toggle("Offer “Plan your day” and “Wrap up” once a day", isOn: $prompts)
                Stepper("Workday ends at \(endHour):00", value: $endHour, in: 12...23)
            }
            Section("Calendar (read-only)") {
                Toggle("Show Apple Calendar events", isOn: $calendarOn)
                    .onChange(of: calendarOn) { _, _ in calendar.refresh() }
                if calendar.access != .granted {
                    Button("Grant Calendar access") { calendar.requestAccess() }
                }
            }
            Section("Focus Shortcuts") {
                TextField("Run on start (Shortcut name)", text: $startShortcut)
                TextField("Run on end (Shortcut name)", text: $endShortcut)
                Text("E.g. a Shortcut that turns Do Not Disturb on or off.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentSettings: View {
    private var serverPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/notchling-mcp").path
    }

    var body: some View {
        let claudeCode = "claude mcp add notchling -- \"\(serverPath)\""
        let json = """
        { "mcpServers": { "notchling": { "command": "\(serverPath)" } } }
        """
        Form {
            Section("Local MCP server") {
                Text("Lets AI agents on this Mac list and add tasks, complete them, read and append notes, and read insights. Nothing leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
            Section("Claude Code") {
                CopyRow(text: claudeCode)
            }
            Section("Claude Desktop / Cursor (mcp.json)") {
                CopyRow(text: json)
            }
        }
        .formStyle(.grouped)
    }

    private struct CopyRow: View {
        let text: String
        var body: some View {
            HStack(alignment: .top) {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }
}

private struct DataSettings: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        Form {
            Section("Your data stays on this Mac") {
                Text(store.file.url.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.file.url]) }
                    Button("Export JSON…") { export() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notchling-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportJSON(to: url)
    }
}
