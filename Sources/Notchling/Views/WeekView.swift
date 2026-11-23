import NotchlingCore
import SwiftUI

/// Inbox plus the next seven days. Drag tasks between columns.
struct WeekView: View {
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
        HStack(alignment: .top, spacing: 8) {
            Column(title: "Inbox", subtitle: "\(store.data.inbox.count)", day: nil, tasks: store.data.inbox, events: [], highlight: false)
                .frame(width: 170)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        Column(
                            title: cal.isDateInToday(day) ? "Today" : cal.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide)),
                            subtitle: day.formatted(.dateTime.day().month(.abbreviated)),
                            day: day,
                            tasks: store.data.tasks(on: day),
                            events: calendar.events(on: day).filter { !$0.isAllDay },
                            highlight: cal.isDateInToday(day))
                            .frame(width: 150)
                    }
                }
            }
        }
    }

    private struct Column: View {
        @EnvironmentObject var store: PlannerStore
        let title: String
        let subtitle: String
        let day: Date?
        let tasks: [TaskItem]
        let events: [CalEvent]
        let highlight: Bool
        @State private var targeted = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).nfont(12, .bold).foregroundStyle(highlight ? Tok.accent : Tok.ink(0.9))
                    Spacer()
                    Text(subtitle).nfont(10, .medium).foregroundStyle(Tok.ink(0.4))
                }
                if day == nil {
                    AddTaskField(placeholder: "Someday…", defaultDay: nil, showsMic: false)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(events) { e in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: e.color)).frame(width: 2, height: 10)
                                Text(e.start.formatted(date: .omitted, time: .shortened)).nfont(9, .semibold).foregroundStyle(Tok.ink(0.5))
                                Text(e.title).nfont(10).lineLimit(1).foregroundStyle(Tok.ink(0.7))
                            }
                        }
                        if !events.isEmpty && !tasks.isEmpty { Divider().opacity(0.4).padding(.vertical, 2) }
                        ForEach(tasks) { TaskRow(task: $0, compact: true) }
                        if tasks.isEmpty && events.isEmpty {
                            Text(day == nil ? "Drop tasks here" : "Free").nfont(10).foregroundStyle(Tok.ink(0.25))
                                .frame(maxWidth: .infinity).padding(.top, 14)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(9)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: Tok.radius, style: .continuous)
                    .fill(targeted ? Tok.accent.opacity(0.16) : Tok.fill(highlight ? 0.09 : 0.05))
                    .overlay(RoundedRectangle(cornerRadius: Tok.radius, style: .continuous)
                        .strokeBorder(targeted ? Tok.accent.opacity(0.6) : .clear, lineWidth: 1)))
            .animation(.easeOut(duration: 0.12), value: targeted)
            .dropDestination(for: String.self) { items, _ in
                let ids = items.compactMap(UUID.init(uuidString:))
                store.mutate { d in ids.forEach { d.move($0, to: day) } }
                return !ids.isEmpty
            } isTargeted: { targeted = $0 }
        }
    }
}
