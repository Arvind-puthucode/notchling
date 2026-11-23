import NotchlingCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var focus: FocusController
    @AppStorage(Prefs.taskSort) private var sortRaw = "smart"

    var body: some View {
        let sort = TaskSort(rawValue: sortRaw) ?? .smart
        let tasks = sort.sorted(store.data.tasks(on: Date()))
        let done = tasks.filter(\.isDone).count
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Ring(progress: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count), lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                    Text("Today").nfont(15, .bold)
                    Text(tasks.isEmpty ? "" : "\(done) of \(tasks.count)").nfont(12, .medium).foregroundStyle(Tok.ink(0.45))
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sortRaw) {
                            ForEach(TaskSort.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down").nfont(10, .semibold)
                            Text(sort.label).nfont(11, .medium)
                        }
                        .foregroundStyle(Tok.ink(0.55))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                AddTaskField()
                if tasks.isEmpty {
                    EmptyHint(icon: "sparkles", title: "A clear day", subtitle: "Add a task, say one, or drag one in from Week.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(tasks) { TaskRow(task: $0).transition(.opacity.combined(with: .move(edge: .top))) }
                        }
                        .animation(Tok.spring, value: tasks.map(\.id))
                    }
                    .scrollIndicators(.never)
                }
                HStack(spacing: 6) {
                    Button { model.planDay() } label: { Label("Plan my day", systemImage: "wand.and.stars") }
                        .buttonStyle(.pill)
                        .help("Fit untimed tasks into free time around your events, most important first")
                    Button { model.enqueue(.wrapUp) } label: { Label("Wrap up", systemImage: "moon.stars") }
                        .buttonStyle(.pill)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            SidePanel()
                .frame(width: 200)
        }
    }
}

/// Right column on Today: next event and focus.
private struct SidePanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let today = store.data.tasks(on: Date())
            CharacterCard(open: today.filter { !$0.isDone }.count, done: today.filter(\.isDone).count, focusing: focus.clock.isRunning)
            SectionLabel("Up next")
            let events = Array(calendar.upcomingToday.filter { !$0.isAllDay }.prefix(3))
            if calendar.access == .unknown && calendar.events.isEmpty {
                Button { calendar.requestAccess() } label: { Label("Connect Calendar", systemImage: "calendar.badge.plus") }
                    .buttonStyle(.pill)
            } else if events.isEmpty {
                Text("Nothing else today").nfont(12).foregroundStyle(Tok.ink(0.45))
            } else {
                NextEventCard(event: events[0])
                ForEach(events.dropFirst()) { EventRow(event: $0, compact: true) }
            }
            Spacer(minLength: 0)
            SectionLabel("Focus")
            if focus.clock.isActive {
                Button { model.tab = .focus } label: {
                    HStack(spacing: 8) {
                        Ring(progress: focus.progress, lineWidth: 3, tint: Tok.accent).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(focus.displayText).nfont(18, .semibold, design: .rounded).monospacedDigit()
                            Text(focus.clock.isRunning ? "Focusing" : "Paused").nfont(10, .medium).foregroundStyle(Tok.ink(0.5))
                        }
                        Spacer()
                    }
                    .card(8)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 5) {
                    ForEach([15, 25, 50], id: \.self) { m in
                        Button("\(m)m") { focus.start(.countdown, minutes: m) }.buttonStyle(.pill(Tok.accent))
                    }
                }
            }
        }
    }
}

private struct NextEventCard: View {
    let event: CalEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let mins = Int(event.start.timeIntervalSince(ctx.date) / 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: event.color)).frame(width: 7, height: 7)
                    Text(mins <= 0 ? "Now" : mins < 60 ? "In \(mins) min" : event.start.formatted(date: .omitted, time: .shortened))
                        .nfont(11, .semibold).foregroundStyle(mins <= 5 ? Tok.accent : Tok.ink(0.55))
                }
                Text(event.title).nfont(13, .semibold).lineLimit(2)
                if let url = event.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }
                        .buttonStyle(.pill(Tok.done, prominent: mins <= 5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(10)
        }
    }
}

struct EventRow: View {
    let event: CalEvent
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).nfont(compact ? 12 : 13, .medium).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .nfont(11).foregroundStyle(Tok.ink(0.5))
            }
            Spacer(minLength: 2)
            if let url = event.joinURL {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.pill(Tok.done))
            }
        }
        .frame(height: compact ? 30 : 36)
    }
}
