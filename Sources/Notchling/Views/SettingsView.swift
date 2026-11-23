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
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Notchling Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView().withServices(model))
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
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            DaySettings().tabItem { Label("Your day", systemImage: "sun.max") }
            FocusSettings().tabItem { Label("Focus", systemImage: "timer") }
            CalendarSettings().tabItem { Label("Calendar", systemImage: "calendar") }
            AgentSettings().tabItem { Label("AI agents", systemImage: "sparkles") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .padding(16)
        .frame(width: 640, height: 520)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var clips: ClipsService
    @AppStorage(Prefs.hoverToOpen) private var hover = false
    @AppStorage(Prefs.fakeNotch) private var fakeNotch = true
    @AppStorage(Prefs.displayPin) private var pin = "pointer"
    @AppStorage(Prefs.openMode) private var openMode = "notch"
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.clipsEnabled) private var clipsOn = true
    @AppStorage(Prefs.clipsScreenshots) private var screenshots = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Text("Click the notch or press ⌥N. Esc or a click outside closes it.").foregroundStyle(.secondary)
                Picker("Open as", selection: $openMode) {
                    Text("Notch").tag("notch")
                    Text("Window").tag("window")
                }
                Toggle("Open when the pointer rests on the notch", isOn: $hover)
                Toggle("Haptic feedback on the trackpad", isOn: $haptics)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Displays") {
                Picker("Show on", selection: $pin) {
                    Text("Display with the pointer").tag("pointer")
                    Text("Built-in display").tag("builtin")
                    ForEach(NSScreen.screens, id: \.displayID) { s in
                        Text(s.localizedName).tag(String(s.displayID))
                    }
                }
                Toggle("Notch on monitors without one", isOn: $fakeNotch)
                Text(fakeNotch ? "It steps aside when an app goes full screen." : "The middle of the top edge still opens Notchling.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Clips") {
                Toggle("Keep recent copies", isOn: $clipsOn)
                Toggle("Add new screenshots and screen recordings", isOn: $screenshots).disabled(!clipsOn)
            }
            .onChange(of: clipsOn) { _, _ in clips.applyPrefs() }
            .onChange(of: screenshots) { _, _ in clips.applyPrefs() }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = "dark"
    @AppStorage(Prefs.width) private var width = 700.0
    @AppStorage(Prefs.height) private var height = 380.0
    @AppStorage(Prefs.textScale) private var textScale = 1.0

    var body: some View {
        Form {
            Section("Look") {
                Picker("Open notch", selection: $appearance) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }
            Section("Size") {
                LabeledContent("Width") {
                    Slider(value: $width, in: 600...960, step: 10)
                    Text("\(Int(width))").monospacedDigit().frame(width: 36)
                }
                LabeledContent("Height") {
                    Slider(value: $height, in: 300...560, step: 10)
                    Text("\(Int(height))").monospacedDigit().frame(width: 36)
                }
                LabeledContent("Text size") {
                    Slider(value: $textScale, in: 0.85...1.3, step: 0.05)
                    Text("\(Int(textScale * 100))%").monospacedDigit().frame(width: 36)
                }
                Button("Reset to defaults") { width = 700; height = 380; textScale = 1 }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DaySettings: View {
    @EnvironmentObject var reminders: RemindersSyncService
    @AppStorage(Prefs.dayPrompts) private var prompts = true
    @AppStorage(Prefs.workdayEndHour) private var endHour = 18
    @AppStorage(Prefs.remindersSync) private var sync = false
    @AppStorage(Prefs.spotlight) private var spotlight = true

    var body: some View {
        Form {
            Section("Plan your day & Wrap up") {
                Toggle("Offer them once a day in the notch", isOn: $prompts)
                Stepper("Workday ends at \(endHour):00", value: $endHour, in: 12...23)
            }
            Section("Apple Reminders") {
                Toggle("Two-way sync with a “Notchling” list", isOn: $sync)
                    .onChange(of: sync) { _, _ in reminders.applyPrefs() }
                Text("Your tasks show up on iPhone and Apple Watch through Reminders. Off by default.")
                    .font(.caption).foregroundStyle(.secondary)
                if sync { LabeledContent("Status", value: statusText) }
            }
            Section("Spotlight") {
                Toggle("Make open tasks searchable in Spotlight", isOn: $spotlight)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch reminders.status {
        case .off: return "Off"
        case .needsAccess: return "Allow Reminders access in System Settings › Privacy"
        case .syncing: return "Syncing…"
        case let .synced(d): return "Synced \(d.formatted(date: .omitted, time: .shortened))"
        case let .failed(e): return "Failed: \(e)"
        }
    }
}

private struct FocusSettings: View {
    @AppStorage(Prefs.focusStartShortcut) private var startShortcut = ""
    @AppStorage(Prefs.focusEndShortcut) private var endShortcut = ""
    @AppStorage(Prefs.distractionApps) private var distractions = ""

    private var listed: Set<String> {
        Set(distractions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    var body: some View {
        Form {
            Section("Shortcuts") {
                TextField("Run when a session starts", text: $startShortcut, prompt: Text("Shortcut name"))
                TextField("Run when a session ends", text: $endShortcut, prompt: Text("Shortcut name"))
                Text("For example, a Shortcut that turns Do Not Disturb on, and one that turns it off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Nudge me back from these apps") {
                let apps = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                ForEach(apps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier {
                        Toggle(isOn: Binding(get: { listed.contains(id) }, set: { on in
                            var s = listed
                            if on { s.insert(id) } else { s.remove(id) }
                            distractions = s.sorted().joined(separator: ",")
                        })) {
                            HStack {
                                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                                Text(app.localizedName ?? id)
                            }
                        }
                    }
                }
                Text("Shows running apps. While a focus session runs, opening one asks if you want to get back to work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarSettings: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var external: ExternalCalendars
    @AppStorage(Prefs.calendarEnabled) private var calendarOn = true
    @AppStorage(Prefs.icsLinks) private var icsLinks = ""
    @AppStorage(Prefs.travelAlerts) private var travelAlerts = false
    @State private var calendly = Keychain.get(ExternalCalendars.calendlyKey) ?? ""
    @State private var calcom = Keychain.get(ExternalCalendars.calcomKey) ?? ""

    var body: some View {
        Form {
            Section("Apple Calendar (read-only)") {
                Toggle("Show events", isOn: $calendarOn).onChange(of: calendarOn) { _, _ in calendar.refresh() }
                if calendar.access != .granted {
                    Button("Grant Calendar access") { calendar.requestAccess() }
                }
                Text("Includes Google and Outlook accounts added in System Settings › Internet Accounts. macOS calls this permission “Full Access”; Notchling never creates, edits or deletes events.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("“Time to leave” alerts using Apple Maps travel time", isOn: $travelAlerts)
            }
            Section("Calendar links (ICS / webcal)") {
                TextEditor(text: $icsLinks)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 56)
                HStack {
                    Text("One link per line.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { external.refresh() }
                }
            }
            Section("Booking services") {
                SecureField("Calendly personal access token", text: $calendly)
                SecureField("Cal.com API key", text: $calcom)
                HStack {
                    Text("Stored in your Keychain.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        Keychain.set(calendly.trimmingCharacters(in: .whitespaces), for: ExternalCalendars.calendlyKey)
                        Keychain.set(calcom.trimmingCharacters(in: .whitespaces), for: ExternalCalendars.calcomKey)
                        external.refresh()
                    }
                }
                ForEach(external.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
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
        let json = #"{ "mcpServers": { "notchling": { "command": "\#(serverPath)" } } }"#
        Form {
            Section("Local MCP server") {
                Text("Lets AI agents on this Mac manage tasks and reminders, read and append notes, read insights, and run the focus timer. Nothing leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
            Section("Claude Code") {
                CopyRow(text: claudeCode)
                Button("Connect Claude Code") { runInTerminal(claudeCode) }
            }
            Section("Claude app / Cursor (mcp.json)") {
                CopyRow(text: json)
                HStack {
                    Button("Open Claude config") { openConfig("~/Library/Application Support/Claude/claude_desktop_config.json") }
                    Button("Open Cursor config") { openConfig("~/.cursor/mcp.json") }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runInTerminal(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func openConfig(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("{ \"mcpServers\": {} }\n".utf8).write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    private struct CopyRow: View {
        let text: String
        @State private var copied = false
        var body: some View {
            HStack(alignment: .top) {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
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
                Text("No account. The internet is only used for calendar links and booking services you add.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Link("Source code (MIT)", destination: URL(string: "https://github.com/Arvind-puthucode/notchling")!)
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
