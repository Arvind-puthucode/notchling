import Foundation

/// The single JSON file that holds all planner data. The app and the MCP server
/// both read and write it; writes are atomic so a reader never sees half a file.
public struct DataFile: Sendable {
    public let url: URL

    /// `~/Library/Application Support/Notchling/data.json`, or `$NOTCHLING_DATA` when set (tests, dev builds).
    public static var standard: DataFile {
        if let override = ProcessInfo.processInfo.environment["NOTCHLING_DATA"], !override.isEmpty {
            return DataFile(url: URL(fileURLWithPath: override))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DataFile(url: base.appendingPathComponent("Notchling/data.json"))
    }

    public init(url: URL) { self.url = url }

    public func load() throws -> PlannerData {
        guard FileManager.default.fileExists(atPath: url.path) else { return PlannerData() }
        return try Self.decoder.decode(PlannerData.self, from: Data(contentsOf: url))
    }

    public func save(_ data: PlannerData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(data).write(to: url, options: .atomic)
    }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Load, mutate, save. Used by short-lived writers such as the MCP server.
    @discardableResult
    public func update<T>(_ body: (inout PlannerData) throws -> T) throws -> T {
        var data = try load()
        let result = try body(&data)
        try save(data)
        return result
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
