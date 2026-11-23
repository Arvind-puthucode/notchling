import NotchlingCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var focus: FocusController

    var body: some View {
        let tasks = store.data.tasks(on: Date())
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AddTaskField()
                if tasks.isEmpty {
                    Text("Nothing planned. Add a task above or drag one in from Week.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 6)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { TaskRow(task: $0) }
                    }
                }
                HStack {
                    Button("Plan my day") { model.planDay() }.buttonStyle(.pill)
                        .help("Fit untimed tasks into free time around your events")
                    Button("Wrap up") { model.enqueue(.wrapUp) }.buttonStyle(.pill)
                    Spacer()
                    let open = tasks.filter { !$0.isDone }.count
                    Text("\(tasks.count - open)/\(tasks.count) done")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Up next")
                let events = calendar.upcomingToday.prefix(4)
                if calendar.access != .granted {
                    Button("Connect Calendar") { calendar.requestAccess() }.buttonStyle(.pill)
                } else if events.isEmpty {
                    Text("No more events today").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(Array(events)) { EventRow(event: $0, compact: true) }
                Spacer(minLength: 4)
                SectionLabel("Focus")
                if focus.clock.isActive {
                    HStack {
                        Text(focus.displayText).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        Spacer()
                        Button { model.tab = .focus } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach([15, 25, 50], id: \.self) { m in
                            Button("\(m)m") { focus.start(.countdown, minutes: m) }.buttonStyle(.pill(.orange))
                        }
                    }
                }
            }
            .frame(width: 190)
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
                Text(event.title).font(.system(size: compact ? 12 : 13, weight: .medium)).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 2)
            if let url = event.joinURL {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.pill(.green))
            }
        }
        .frame(height: compact ? 30 : 36)
    }
}
