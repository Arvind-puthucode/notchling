import AppKit
import NotchlingCore
import SwiftUI

/// Daily notepad. Autosaves; ⌘↩ turns the current line into a task.
struct NotesView: View {
    @EnvironmentObject var store: PlannerStore
    @EnvironmentObject var model: AppModel
    @Environment(\.textScale) private var scale
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        let cal = Calendar.current
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "Previous day") { go(-1) }
                Text(cal.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month()))
                    .nfont(15, .bold)
                IconButton(systemName: "chevron.right", help: "Next day") { go(1) }
                if !cal.isDateInToday(day) {
                    Button("Today") { load(cal.startOfDay(for: Date())) }.buttonStyle(.pill)
                }
                Spacer()
                Label("⌘↩ turns a line into a task", systemImage: "return")
                    .nfont(10, .medium).foregroundStyle(Tok.ink(0.4))
            }
            NoteEditor(text: $text, fontSize: 13 * scale) { line in
                store.mutate { $0.addTask(parsing: line, defaultDay: day) }
                model.haptic()
            }
            .padding(10)
            .background(Tok.fill(0.05), in: RoundedRectangle(cornerRadius: Tok.radius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write anything. Meeting notes, ideas, a brain dump…")
                        .nfont(13).foregroundStyle(Tok.ink(0.3))
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear { load(day) }
        .onChange(of: text) { _, new in
            saveTask?.cancel()
            let target = day
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                store.mutate { $0.setNote(new, for: target) }
            }
        }
        .onDisappear(perform: flush)
    }

    private func go(_ delta: Int) {
        load(Calendar.current.date(byAdding: .day, value: delta, to: day)!)
    }

    private func load(_ newDay: Date) {
        flush()
        day = newDay
        text = store.data.note(for: newDay)
    }

    private func flush() {
        saveTask?.cancel()
        store.mutate { $0.setNote(text, for: day) }
    }
}

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var onCommandReturn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.string = text
        tv.delegate = context.coordinator
        style(tv)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text { tv.string = text }
        style(tv)
    }

    private func style(_ tv: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        if tv.font != font { tv.font = font }
        tv.textColor = .labelColor
        tv.insertionPointColor = NSColor(Tok.accent)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)),
                  NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return false }
            let ns = tv.string as NSString
            let range = ns.lineRange(for: tv.selectedRange())
            let line = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return true }
            tv.insertText("", replacementRange: range)
            parent.onCommandReturn(line.hasPrefix("- ") ? String(line.dropFirst(2)) : line)
            return true
        }
    }
}
