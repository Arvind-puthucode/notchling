import Charts
import NotchlingCore
import SwiftUI

struct CalendarTabView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var model: AppModel
    @State private var camera = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Next two weeks").nfont(15, .bold)
                    Spacer()
                    Button { camera.toggle() } label: { Label(camera ? "Hide camera" : "Check camera", systemImage: "web.camera") }
                        .buttonStyle(.pill(camera ? Tok.accent : .primary))
                }
                if calendar.access != .granted && calendar.events.isEmpty {
                    connect
                } else {
                    list
                }
            }
            if camera {
                CameraPreview()
                    .frame(width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text("Only you can see this").nfont(10, .medium).padding(5)
                            .background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white).padding(8)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Tok.spring, value: camera)
    }

    private var connect: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").nfont(26, .light).foregroundStyle(Tok.ink(0.4))
            Text("See your day next to your tasks").nfont(13, .semibold)
            Text("Reads Apple Calendar, including Google and Outlook accounts added in System Settings. Never changes events. You can also add ICS links and Calendly or Cal.com in Settings.")
                .nfont(11).foregroundStyle(Tok.ink(0.55)).multilineTextAlignment(.center).frame(maxWidth: 380)
            if calendar.access == .denied {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }.buttonStyle(.pill)
            } else {
                Button("Connect Calendar") { calendar.requestAccess() }.buttonStyle(.pill(Tok.done, prominent: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: calendar.events.filter { $0.end > Date() }) { cal.startOfDay(for: $0.start) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                if grouped.isEmpty {
                    EmptyHint(icon: "calendar", title: "No events coming up").frame(height: 160)
                }
                ForEach(grouped.keys.sorted(), id: \.self) { day in
                    Section {
                        ForEach(grouped[day]!) { EventRow(event: $0).padding(.horizontal, 4) }
                    } header: {
                        HStack {
                            Text(cal.isDateInToday(day) ? "Today" : cal.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide).day().month()))
                                .nfont(11, .bold).foregroundStyle(cal.isDateInToday(day) ? Tok.accent : Tok.ink(0.55))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .background(NotchBackground.color(light: Prefs.d.string(forKey: Prefs.appearance) == "light"))
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct ClipsView: View {
    @EnvironmentObject var clips: ClipsService
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.clipsEnabled) private var enabled = true
    @State private var copied: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clips").nfont(15, .bold)
                Text("copies, screenshots, recordings").nfont(12).foregroundStyle(Tok.ink(0.45))
                Spacer()
                if !clips.clips.isEmpty { Button("Clear") { clips.clear() }.buttonStyle(.pill) }
            }
            if !enabled {
                EmptyHint(icon: "paperclip", title: "Clips are off", subtitle: "Turn them on in Settings › General.")
            } else if clips.clips.isEmpty {
                EmptyHint(icon: "doc.on.clipboard", title: "Nothing yet",
                          subtitle: "Copy something or take a screenshot. Click a clip to copy it, drag it anywhere, or turn it into a task.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(clips.clips) { clip in
                            ClipCard(clip: clip, copied: copied == clip.id, makeTask: { makeTask(clip) }, remove: { clips.remove(clip) })
                                .onTapGesture {
                                    clips.copy(clip)
                                    model.haptic()
                                    withAnimation { copied = clip.id }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { if copied == clip.id { copied = nil } } }
                                }
                                .onDrag { clip.itemProvider }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func makeTask(_ clip: Clip) {
        let today = Calendar.current.startOfDay(for: Date())
        store.mutate { d in
            switch clip.kind {
            case let .text(s): d.addTask(parsing: String(s.prefix(200)), defaultDay: today)
            case let .file(url): d.tasks.append(TaskItem(title: url.deletingPathExtension().lastPathComponent, day: today, links: [url.absoluteString]))
            case .image: d.tasks.append(TaskItem(title: "Image clip", day: today))
            }
        }
        model.haptic()
    }
}

private struct ClipCard: View {
    let clip: Clip
    let copied: Bool
    let makeTask: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                preview
                    .frame(width: 150, height: 100)
                    .clipped()
                    .background(Tok.fill(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Tok.fill(hovering ? 0.25 : 0.08)))
                if hovering {
                    HStack(spacing: 2) {
                        IconButton(systemName: "checklist", help: "Make task", action: makeTask)
                        IconButton(systemName: "xmark", help: "Remove", action: remove)
                    }
                    .padding(3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(5)
                }
                if copied {
                    Label("Copied", systemImage: "checkmark").nfont(11, .bold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Tok.done, in: Capsule()).foregroundStyle(.black.opacity(0.8))
                        .frame(width: 150, height: 100)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            HStack(spacing: 4) {
                Image(systemName: icon).nfont(9, .semibold)
                Text(clip.label).nfont(10, .medium).lineLimit(1)
                Spacer(minLength: 0)
                Text(clip.date, format: .dateTime.hour().minute()).nfont(9).foregroundStyle(Tok.ink(0.35))
            }
            .foregroundStyle(Tok.ink(0.6))
            .frame(width: 150)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var icon: String {
        switch clip.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case let .file(url): return ["mov", "mp4"].contains(url.pathExtension.lowercased()) ? "video" : "doc"
        }
    }

    @ViewBuilder private var preview: some View {
        switch clip.kind {
        case let .image(img):
            Image(nsImage: img).resizable().scaledToFill()
        case let .file(url):
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(24)
            }
        case let .text(s):
            Text(s).nfont(11).lineLimit(6).foregroundStyle(Tok.ink(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        let i = Insights.compute(store.data)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Insights").nfont(15, .bold)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    Stat(value: "\(i.completedToday)", label: "Done today", icon: "checkmark.circle.fill", tint: Tok.done)
                    Stat(value: "\(i.streak)", label: i.streak == 1 ? "Day streak" : "Day streak", icon: "flame.fill", tint: Tok.accent)
                    Stat(value: Self.minutes(i.focusMinutesToday), label: "Focus today", icon: "timer", tint: Tok.accent)
                    Stat(value: Self.minutes(i.focusMinutesThisWeek), label: "Focus this week", icon: "chart.line.uptrend.xyaxis", tint: .purple)
                }
                if let h = i.bestFocusHour {
                    let start = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
                    Label("You focus best around \(start.formatted(date: .omitted, time: .shortened))", systemImage: "sparkles")
                        .nfont(12, .medium).foregroundStyle(Tok.ink(0.7))
                }
                Spacer(minLength: 0)
                Text("Only active focus time counts. Pauses and sleep are left out.").nfont(10).foregroundStyle(Tok.ink(0.35))
            }
            .frame(width: 290)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Last 7 days")
                Chart(i.daily) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Focus", day.focusMinutes))
                        .foregroundStyle(Tok.accent.gradient)
                        .cornerRadius(4)
                    if day.completed > 0 {
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Done", day.completed * 10))
                            .symbol { Circle().fill(Tok.done).frame(width: 7, height: 7) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Tok.fill(0.1))
                        AxisValueLabel { if let m = v.as(Int.self) { Text("\(m)m").nfont(9) } }
                    }
                }
                HStack(spacing: 12) {
                    Label("Focus minutes", systemImage: "square.fill").foregroundStyle(Tok.accent)
                    Label("Tasks done (×10)", systemImage: "circle.fill").foregroundStyle(Tok.done)
                }
                .nfont(10, .medium)
            }
            .card(12, opacity: 0.04)
        }
    }

    static func minutes(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }

    private struct Stat: View {
        let value: String
        let label: String
        let icon: String
        let tint: Color
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).nfont(12, .semibold).foregroundStyle(tint)
                Text(value).nfont(22, .bold, design: .rounded).monospacedDigit()
                Text(label).nfont(11, .medium).foregroundStyle(Tok.ink(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(10)
        }
    }
}

/// Live activity: shown as a compact notch when it popped open by itself, or over the workspace.
struct AlertCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var characters: CharacterStore
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var focus: FocusController
    let alert: NotchAlert
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            if let pack = characters.current {
                CharacterAvatar(pack: pack, mood: characterMood, size: compact ? 44 : 50)
            } else {
                ZStack {
                    Circle().fill(style.tint.opacity(0.18))
                    Image(systemName: style.icon).nfont(16, .semibold).foregroundStyle(style.tint)
                }
                .frame(width: 38, height: 38)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(characterTitle ?? style.title).nfont(11, .bold).foregroundStyle(characters.current?.accent ?? style.tint)
                Text(style.subtitle).nfont(14, .semibold).lineLimit(2)
                if model.alerts.count > 1 {
                    Text("+\(model.alerts.count - 1) more").nfont(10, .medium).foregroundStyle(Tok.ink(0.45))
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(compact ? 4 : 14)
        .frame(maxWidth: compact ? .infinity : 520)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tok.fill(0.12)))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: compact ? .center : .top)
        .padding(.top, compact ? 0 : 6)
    }

    /// The character's own words for reminders and finished sessions, stable per alert.
    private var characterTitle: String? {
        guard let pack = characters.current else { return nil }
        let seed = alert.id.hashValue & Int(Int32.max)
        switch alert {
        case .reminder: return pack.line(.reminder, seed: seed)
        case .focusDone: return pack.line(.focusDone, seed: seed)
        default: return nil
        }
    }

    private var characterMood: CharacterPack.Mood {
        switch alert {
        case .focusDone, .wrapUp: return .happy
        case .reminder, .meeting, .leave, .distraction: return .alert
        case .planDay: return .idle
        }
    }

    private var style: (icon: String, tint: Color, title: String, subtitle: String) {
        switch alert {
        case let .reminder(_, title): return ("bell.fill", Tok.star, "REMINDER", title)
        case let .meeting(e): return ("video.fill", Tok.done, "STARTING NOW", e.title)
        case let .leave(e, m): return ("car.fill", Tok.accent, "TIME TO LEAVE · \(m) MIN DRIVE", e.title)
        case let .focusDone(m): return ("checkmark.seal.fill", Tok.accent, "FOCUS COMPLETE", "\(m) minutes of deep work")
        case let .distraction(name, _): return ("hand.raised.fill", Tok.danger, "YOU'RE IN A FOCUS SESSION", "Back to work instead of \(name)?")
        case .planDay: return ("sun.max.fill", Tok.star, "GOOD MORNING", "Plan today around your calendar?")
        case .wrapUp:
            let today = store.data.tasks(on: Date())
            let done = today.filter(\.isDone).count
            return ("moon.stars.fill", .purple, "WRAP UP", "\(done) done · \(today.count - done) left")
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            switch alert {
            case let .reminder(id, _):
                Menu("Snooze") {
                    ForEach([5, 10, 30, 60], id: \.self) { m in
                        Button(m < 60 ? "\(m) minutes" : "1 hour") { store.mutate { $0.snooze(id, minutes: m) }; model.resolve(alert) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5).background(Tok.fill(0.13), in: Capsule())
                Button("Done") { store.mutate { _ = $0.setDone(id) }; model.haptic(); model.resolve(alert) }
                    .buttonStyle(.pill(Tok.done, prominent: true))
            case let .meeting(e), let .leave(e, _):
                Button("Dismiss") { model.resolve(alert) }.buttonStyle(.pill)
                if let url = e.joinURL {
                    Button { NSWorkspace.shared.open(url); model.resolve(alert) } label: { Label("Join", systemImage: "video.fill") }
                        .buttonStyle(.pill(Tok.done, prominent: true))
                } else if case .leave = alert, let place = e.location,
                          let url = URL(string: "maps://?daddr=\(place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Button { NSWorkspace.shared.open(url); model.resolve(alert) } label: { Label("Directions", systemImage: "map.fill") }
                        .buttonStyle(.pill(Tok.accent, prominent: true))
                }
            case .focusDone:
                Button("Done") { model.resolve(alert) }.buttonStyle(.pill)
                Button("Another 25") { focus.start(.countdown, minutes: 25); model.resolve(alert) }.buttonStyle(.pill(Tok.accent, prominent: true))
            case let .distraction(_, bundleID):
                Button("5 more min") { model.allowDistraction(bundleID); model.resolve(alert) }.buttonStyle(.pill)
                Button("Back to focus") {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.hide()
                    model.resolve(alert)
                }
                .buttonStyle(.pill(Tok.accent, prominent: true))
            case .planDay:
                Button("Not now") { model.resolve(alert) }.buttonStyle(.pill)
                Button("Plan it") { model.planDay(); model.resolve(alert); model.tab = .today }.buttonStyle(.pill(Tok.done, prominent: true))
            case .wrapUp:
                let left = store.data.tasks(on: Date()).filter { !$0.isDone }.count
                Button("Later") { model.resolve(alert) }.buttonStyle(.pill)
                if left > 0 {
                    Button("To Inbox") { store.mutate { $0.moveLeftovers(toTomorrow: false) }; model.resolve(alert) }.buttonStyle(.pill)
                    Button("To tomorrow") { store.mutate { $0.moveLeftovers(toTomorrow: true) }; model.resolve(alert) }
                        .buttonStyle(.pill(Tok.done, prominent: true))
                }
            }
        }
    }
}
