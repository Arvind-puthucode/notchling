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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                Column(title: "Inbox", subtitle: "\(store.data.inbox.count)", day: nil, tasks: store.data.inbox, events: [])
                ForEach(days, id: \.self) { day in
                    Column(
                        title: cal.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)),
                        subtitle: day.formatted(.dateTime.day().month(.abbreviated)),
                        day: day,
                        tasks: store.data.tasks(on: day).filter { !$0.isDone || cal.isDateInToday(day) },
                        events: calendar.events(on: day).filter { !$0.isAllDay })
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
        @State private var targeted = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                if day == nil {
                    AddTaskField(placeholder: "Add…", defaultDay: nil)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(events) { e in
                            Text("\(e.start.formatted(date: .omitted, time: .shortened)) \(e.title)")
                                .font(.system(size: 10)).lineLimit(1)
                                .foregroundStyle(Color(nsColor: e.color))
                        }
                        ForEach(tasks) { TaskRow(task: $0, compact: true) }
                    }
                }
            }
            .padding(8)
            .frame(width: 150)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.white.opacity(targeted ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .dropDestination(for: String.self) { items, _ in
                let ids = items.compactMap(UUID.init(uuidString:))
                store.mutate { d in ids.forEach { d.move($0, to: day) } }
                return !ids.isEmpty
            } isTargeted: { targeted = $0 }
        }
    }
}
