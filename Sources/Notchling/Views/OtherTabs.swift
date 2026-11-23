import NotchlingCore
import SwiftUI

struct CalendarTabView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        if calendar.access != .granted {
            VStack(spacing: 10) {
                Text("Notchling shows your Apple Calendar events (including Google and Outlook accounts added in System Settings). It never changes them.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                if calendar.access == .denied {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(.pill)
                } else {
                    Button("Connect Calendar") { calendar.requestAccess() }.buttonStyle(.pill(.green))
                }
            }
            .frame(maxWidth: 360, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else {
            let grouped = Dictionary(grouping: calendar.events) { Calendar.current.startOfDay(for: $0.start) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if grouped.isEmpty {
                        Text("No events in the next two weeks").foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(grouped.keys.sorted(), id: \.self) { day in
                        SectionLabel(day.formatted(.dateTime.weekday(.wide).day().month()))
                            .padding(.top, 4)
                        ForEach(grouped[day]!) { EventRow(event: $0) }
                    }
                }
            }
        }
    }
}

struct ClipsView: View {
    @EnvironmentObject var clips: ClipsService
    @EnvironmentObject var store: PlannerStore
    @AppStorage(Prefs.clipsEnabled) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Clips · copies, screenshots, recordings")
                Spacer()
                if !clips.clips.isEmpty { Button("Clear") { clips.clear() }.buttonStyle(.pill) }
            }
            if !enabled {
                Text("Clips are off. Turn them on in Settings.").foregroundStyle(.white.opacity(0.5))
            } else if clips.clips.isEmpty {
                Text("Copy something or take a screenshot. Click a clip to copy it, drag it into any app, or make it a task.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(clips.clips) { clip in
                        ClipCard(clip: clip)
                            .onTapGesture { clips.copy(clip) }
                            .onDrag { clip.itemProvider }
                            .contextMenu {
                                Button("Copy") { clips.copy(clip) }
                                Button("Make Task") { makeTask(clip) }
                                Button("Remove") { clips.remove(clip) }
                            }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func makeTask(_ clip: Clip) {
        store.mutate { d in
            switch clip.kind {
            case let .text(s): d.addTask(parsing: String(s.prefix(200)), defaultDay: Date())
            case let .file(url):
                d.tasks.append(TaskItem(title: url.lastPathComponent, day: Calendar.current.startOfDay(for: Date()), links: [url.absoluteString]))
            case .image:
                d.tasks.append(TaskItem(title: "Image clip", day: Calendar.current.startOfDay(for: Date())))
            }
        }
    }
}

private struct ClipCard: View {
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch clip.kind {
                case let .image(img):
                    Image(nsImage: img).resizable().scaledToFill()
                case let .file(url):
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(20)
                    }
                case let .text(s):
                    Text(s).font(.system(size: 11)).lineLimit(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
                }
            }
            .frame(width: 130, height: 90)
            .clipped()
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(clip.label).font(.system(size: 10)).lineLimit(1).foregroundStyle(.white.opacity(0.6))
                .frame(width: 130, alignment: .leading)
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        let i = Insights.compute(store.data)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Stat(value: "\(i.completedToday)", label: "Done today")
                Stat(value: "\(i.completedThisWeek)", label: "Done this week")
                Stat(value: "\(i.focusMinutesToday)m", label: "Focus today")
                Stat(value: "\(i.focusMinutesThisWeek)m", label: "Focus this week")
                Stat(value: "\(i.streak)", label: i.streak == 1 ? "Day streak" : "Days streak")
            }
            if let h = i.bestFocusHour {
                let start = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
                Text("You focus best around \(start.formatted(date: .omitted, time: .shortened)).")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
            }
            Text("Only active focus time counts: pauses and sleep are excluded.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Live-activity card shown over the open notch.
struct AlertCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var focus: FocusController
    let alert: NotchAlert

    var body: some View {
        VStack(spacing: 12) {
            content
            if model.alerts.count > 1 {
                Text("+\(model.alerts.count - 1) more").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }

    @ViewBuilder private var content: some View {
        switch alert {
        case let .reminder(id, title):
            header("bell.fill", .yellow, "Reminder", title)
            HStack {
                Button("Snooze 10 min") { store.mutate { $0.snooze(id) }; model.resolve(alert) }.buttonStyle(.pill)
                Button("Done") { store.mutate { $0.toggleDone(id) }; model.resolve(alert) }.buttonStyle(.pill(.green))
            }
        case let .meeting(e):
            header("video.fill", .green, "Starting now", e.title)
            HStack {
                Button("Dismiss") { model.resolve(alert) }.buttonStyle(.pill)
                if let url = e.joinURL {
                    Button("Join") { NSWorkspace.shared.open(url); model.resolve(alert) }.buttonStyle(.pill(.green))
                }
            }
        case let .focusDone(minutes):
            header("checkmark.seal.fill", .orange, "Focus complete", "\(minutes) minutes of focus. Nice.")
            HStack {
                Button("Done") { model.resolve(alert) }.buttonStyle(.pill)
                Button("Another 25") { focus.start(.countdown, minutes: 25); model.resolve(alert) }.buttonStyle(.pill(.orange))
            }
        case .planDay:
            header("sun.max.fill", .yellow, "Plan your day", "Fit today's untimed tasks into your free time?")
            HStack {
                Button("Not now") { model.resolve(alert) }.buttonStyle(.pill)
                Button("Plan it") { model.planDay(); model.resolve(alert); model.tab = .today }.buttonStyle(.pill(.green))
            }
        case .wrapUp:
            let today = store.data.tasks(on: Date())
            let done = today.filter(\.isDone).count
            let left = today.count - done
            header("moon.stars.fill", .purple, "Wrap up", "\(done) done today. \(left) left.")
            HStack {
                Button("Later") { model.resolve(alert) }.buttonStyle(.pill)
                if left > 0 {
                    Button("Leftovers → Inbox") { store.mutate { $0.moveLeftovers(toTomorrow: false) }; model.resolve(alert) }.buttonStyle(.pill)
                    Button("Leftovers → Tomorrow") { store.mutate { $0.moveLeftovers(toTomorrow: true) }; model.resolve(alert) }.buttonStyle(.pill(.green))
                }
            }
        }
    }

    private func header(_ icon: String, _ tint: Color, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(tint)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
        }
    }
}
