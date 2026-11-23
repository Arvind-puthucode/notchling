import NotchlingCore
import SwiftUI

extension PlannerData {
    mutating func toggleImportant(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].important.toggle()
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: PlannerStore
    let task: TaskItem
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Button { store.mutate { $0.toggleDone(task.id) } } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : .white.opacity(0.6))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .white.opacity(0.4) : .white)
                .lineLimit(compact ? 2 : 1)
            if task.important {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
            }
            Spacer(minLength: 4)
            ForEach(task.links, id: \.self) { link in
                if let url = URL(string: link) {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "link") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .help(link)
                }
            }
            if let due = task.due, !compact {
                Text(due, format: .dateTime.hour().minute())
                    .font(.system(size: 11)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
            }
        }
        .font(.system(size: compact ? 12 : 13))
        .padding(.vertical, compact ? 3 : 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .draggable(task.id.uuidString)
        .contextMenu { TaskMenu(task: task) }
    }
}

struct TaskMenu: View {
    @EnvironmentObject var store: PlannerStore
    let task: TaskItem

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        Button(task.important ? "Unmark Important" : "Mark Important") { store.mutate { $0.toggleImportant(task.id) } }
        Button("Move to Today") { store.mutate { $0.move(task.id, to: today) } }
        Button("Move to Tomorrow") { store.mutate { $0.move(task.id, to: cal.date(byAdding: .day, value: 1, to: today)) } }
        Button("Move to Inbox") { store.mutate { $0.move(task.id, to: nil) } }
        Divider()
        Button("Delete", role: .destructive) { store.mutate { $0.delete(task.id) } }
    }
}

/// Quick-add field that parses natural language.
struct AddTaskField: View {
    @EnvironmentObject var store: PlannerStore
    var placeholder = "Add a task… try “call mom tomorrow at 5pm !”"
    /// Day for tasks typed without a date. nil = Inbox.
    var defaultDay: Date? = Date()
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(.white.opacity(0.5))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    store.mutate { $0.addTask(parsing: text, defaultDay: defaultDay) }
                    text = ""
                }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(configuration.isPressed ? 0.3 : 0.16), in: Capsule())
            .foregroundStyle(tint == .white ? .white : tint)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ tint: Color) -> PillButtonStyle { PillButtonStyle(tint: tint) }
}
