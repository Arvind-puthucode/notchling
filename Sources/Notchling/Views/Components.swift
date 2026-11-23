import NotchlingCore
import SwiftUI
import UniformTypeIdentifiers

struct TaskRow: View {
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var model: AppModel
    let task: TaskItem
    var compact = false
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var dropTarget = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Checkbox(done: task.isDone) {
                store.mutate { $0.toggleDone(task.id) }
                if !task.isDone {
                    model.haptic()
                    model.characters.react(.done)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                        .onChange(of: fieldFocused) { _, f in if !f { commit() } }
                } else {
                    Text(task.title)
                        .strikethrough(task.isDone, color: Tok.ink(0.4))
                        .foregroundStyle(task.isDone ? Tok.ink(0.38) : Tok.ink(0.95))
                        .lineLimit(compact ? 3 : 1)
                        .onTapGesture(count: 2) { startEditing() }
                }
                if compact, let due = task.due {
                    Label(due.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                        .nfont(10, .medium)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(due < Date() && !task.isDone ? Tok.danger : Tok.ink(0.5))
                }
                if !compact, !task.links.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(task.links, id: \.self) { AttachmentChip(link: $0, taskID: task.id) }
                    }
                }
            }
            .nfont(compact ? 12 : 13)

            if task.important {
                Image(systemName: "star.fill").nfont(9).foregroundStyle(Tok.star).fixedSize()
            }
            Spacer(minLength: 4)
            if !compact, let due = task.due {
                Text(due, format: .dateTime.hour().minute())
                    .nfont(compact ? 10 : 11, .medium).monospacedDigit()
                    .foregroundStyle(due < Date() && !task.isDone ? Tok.danger : Tok.ink(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Tok.fill(0.08), in: Capsule())
                    .fixedSize()
            }
            if hovering && !compact {
                Menu {
                    TaskMenu(task: task, onRename: startEditing)
                } label: {
                    Image(systemName: "ellipsis").nfont(11, .bold).foregroundStyle(Tok.ink(0.6))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dropTarget ? Tok.accent.opacity(0.18) : Tok.fill(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(task.id.uuidString)
        .dropDestination(for: URL.self) { urls, _ in
            store.mutate { $0.attach(urls.map(\.absoluteString), to: task.id) }
            return !urls.isEmpty
        } isTargeted: { dropTarget = $0 }
        .contextMenu { TaskMenu(task: task, onRename: startEditing) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func startEditing() {
        draft = task.title
        editing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commit() {
        guard editing else { return }
        editing = false
        store.mutate { $0.rename(task.id, to: draft) }
    }
}

struct Checkbox: View {
    let done: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(done ? Tok.done : Tok.ink(hovering ? 0.7 : 0.4), lineWidth: 1.5)
                    .background(Circle().fill(done ? Tok.done : .clear))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black.opacity(0.75))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: done)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct AttachmentChip: View {
    @EnvironmentObject var store: PlannerStore
    let link: String
    let taskID: UUID

    var body: some View {
        let url = URL(string: link)
        let isFile = url?.isFileURL ?? false
        Button { if let url { NSWorkspace.shared.open(url) } } label: {
            HStack(spacing: 3) {
                Image(systemName: isFile ? "doc" : "link").nfont(9, .semibold)
                Text(isFile ? url?.lastPathComponent ?? link : url?.host ?? link).nfont(10, .medium).lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Tok.fill(0.08), in: Capsule())
            .foregroundStyle(Tok.ink(0.7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Attachment") { store.mutate { $0.detach(link, from: taskID) } }
        }
        .help(link)
    }
}

struct TaskMenu: View {
    @EnvironmentObject var store: PlannerStore
    let task: TaskItem
    var onRename: (() -> Void)? = nil

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let onRename { Button("Rename", action: onRename) }
        Button(task.important ? "Unmark Important" : "Mark Important") { store.mutate { $0.toggleImportant(task.id) } }
        Menu("Remind Me") {
            ForEach([15, 30, 60, 120], id: \.self) { m in
                Button(m < 60 ? "In \(m) minutes" : "In \(m / 60) hour\(m > 60 ? "s" : "")") { store.mutate { $0.snooze(task.id, minutes: m) } }
            }
        }
        Divider()
        Button("Move to Today") { store.mutate { $0.move(task.id, to: today) } }
        Button("Move to Tomorrow") { store.mutate { $0.move(task.id, to: cal.date(byAdding: .day, value: 1, to: today)) } }
        Button("Move to Inbox") { store.mutate { $0.move(task.id, to: nil) } }
        Divider()
        Button("Delete", role: .destructive) { store.mutate { $0.delete(task.id) } }
    }
}

/// Quick-add field: natural language, dictation, Return to add.
struct AddTaskField: View {
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var speech: SpeechInput
    var placeholder = "Add a task — “call mom tomorrow at 5pm !”"
    /// Day for tasks typed without a date. nil = Inbox.
    var defaultDay: Date? = Date()
    var showsMic = true
    @State private var text = ""
    @FocusState private var focused: Bool

    private var preview: TaskParser.Result? {
        text.isEmpty ? nil : TaskParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill").nfont(14).foregroundStyle(focused ? Tok.accent : Tok.ink(0.35))
                TextField(placeholder, text: speech.isListening ? .constant(speech.transcript) : $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                if showsMic {
                    Button {
                        speech.toggle { spoken in
                            store.mutate { $0.addTask(parsing: spoken, defaultDay: defaultDay) }
                            model.haptic()
                        }
                    } label: {
                        Image(systemName: speech.isListening ? "waveform" : "mic")
                            .nfont(12, .semibold)
                            .foregroundStyle(speech.isListening ? Tok.danger : Tok.ink(0.5))
                            .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(speech.isListening ? "Stop and add" : "Add by voice")
                }
            }
            .nfont(13)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Tok.fill(focused ? 0.1 : 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(focused ? Tok.accent.opacity(0.5) : .clear)))

            if let p = preview, p.day != nil || p.important || !p.links.isEmpty {
                HStack(spacing: 6) {
                    if let due = p.due {
                        ParseChip(icon: "bell", text: due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    } else if let day = p.day {
                        ParseChip(icon: "calendar", text: day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    }
                    if p.important { ParseChip(icon: "star.fill", text: "Important") }
                    if !p.links.isEmpty { ParseChip(icon: "link", text: "\(p.links.count) link") }
                }
                .padding(.leading, 6)
                .transition(.opacity)
            }
            if let err = speech.error {
                Text(err).nfont(11).foregroundStyle(Tok.danger)
            }
        }
        .animation(.easeOut(duration: 0.15), value: preview)
    }

    private func add() {
        store.mutate { $0.addTask(parsing: text, defaultDay: defaultDay) }
        text = ""
    }
}

private struct ParseChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).nfont(9, .semibold)
            Text(text).nfont(10, .semibold)
        }
        .foregroundStyle(Tok.accent)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Tok.accent.opacity(0.14), in: Capsule())
    }
}
