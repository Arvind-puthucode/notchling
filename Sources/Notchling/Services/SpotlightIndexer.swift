import CoreSpotlight
import NotchlingCore
import UniformTypeIdentifiers

/// Keeps open tasks searchable in Spotlight. Selecting one opens the notch on Today.
@MainActor
final class SpotlightIndexer {
    private let index = CSSearchableIndex(name: "Notchling")
    private var lastIndexed: [UUID: String] = [:]

    func update(_ data: PlannerData) {
        guard Prefs.d.bool(forKey: Prefs.spotlight) else {
            if !lastIndexed.isEmpty { index.deleteAllSearchableItems(); lastIndexed = [:] }
            return
        }
        let open = data.tasks.filter { !$0.isDone }
        var next: [UUID: String] = [:]
        var items: [CSSearchableItem] = []
        for t in open {
            let summary = [t.title, t.due?.formatted(date: .abbreviated, time: .shortened) ?? t.day?.formatted(date: .abbreviated, time: .omitted)]
                .compactMap { $0 }.joined(separator: "|")
            next[t.id] = summary
            guard lastIndexed[t.id] != summary else { continue }
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = t.title
            attrs.contentDescription = t.due.map { "Due \($0.formatted(date: .abbreviated, time: .shortened))" }
                ?? t.day.map { "Planned for \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Inbox"
            attrs.keywords = ["task", "todo", "notchling"]
            items.append(CSSearchableItem(uniqueIdentifier: t.id.uuidString, domainIdentifier: "tasks", attributeSet: attrs))
        }
        let removed = Set(lastIndexed.keys).subtracting(next.keys).map(\.uuidString)
        if !items.isEmpty { index.indexSearchableItems(items) }
        if !removed.isEmpty { index.deleteSearchableItems(withIdentifiers: removed) }
        lastIndexed = next
    }
}
