import AppKit
import NotchlingCore
import SwiftUI

/// Daily notepad. Autosaves; ⌘↩ turns the current line into a task.
struct NotesView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var text = ""
    @State private var day = Date()
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Notes · \(day.formatted(.dateTime.weekday(.wide).day().month()))")
                Spacer()
                Text("⌘↩ makes the line a task").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            NoteEditor(text: $text) { line in
                store.mutate { $0.addTask(parsing: line, defaultDay: Date()) }
            }
            .padding(8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .onAppear {
            day = Date()
            text = store.data.note(for: day)
        }
        .onChange(of: text) { _, new in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                store.mutate { $0.setNote(new, for: day) }
            }
        }
        .onDisappear {
            saveTask?.cancel()
            store.mutate { $0.setNote(text, for: day) }
        }
    }
}

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommandReturn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.string = text
        tv.delegate = context.coordinator
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text { tv.string = text }
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
            parent.onCommandReturn(line)
            return true
        }
    }
}
