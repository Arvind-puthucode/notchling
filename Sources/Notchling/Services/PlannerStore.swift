import Foundation
import NotchlingCore

/// Observable wrapper around the data file. Every mutation is saved at once;
/// writes made by the MCP server are picked up by `reloadIfChangedExternally`.
@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var data: PlannerData
    let file: DataFile
    private var lastSeenModification: Date?

    init(file: DataFile = .standard) {
        self.file = file
        data = (try? file.load()) ?? PlannerData()
        lastSeenModification = file.modificationDate
        mutate { $0.carryForward() }
    }

    func mutate(_ body: (inout PlannerData) -> Void) {
        var copy = data
        body(&copy)
        guard copy != data else { return }
        data = copy
        do {
            try file.save(copy)
        } catch {
            NSLog("Notchling: save failed: \(error)")
        }
        lastSeenModification = file.modificationDate
    }

    func reloadIfChangedExternally() {
        guard let m = file.modificationDate, m != lastSeenModification else { return }
        lastSeenModification = m
        if let fresh = try? file.load(), fresh != data { data = fresh }
    }

    func exportJSON(to url: URL) throws {
        try DataFile.encoder.encode(data).write(to: url, options: .atomic)
    }
}
