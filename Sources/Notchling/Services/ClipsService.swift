import AppKit
import UniformTypeIdentifiers

struct Clip: Identifiable {
    enum Kind {
        case text(String)
        case image(NSImage)
        case file(URL)
    }

    let id = UUID()
    let kind: Kind
    let date = Date()

    var label: String {
        switch kind {
        case let .text(s): return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return "Image"
        case let .file(url): return url.lastPathComponent
        }
    }

    var itemProvider: NSItemProvider {
        switch kind {
        case let .text(s): return NSItemProvider(object: s as NSString)
        case let .image(img): return NSItemProvider(object: img)
        case let .file(url): return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}

/// Recent clipboard items plus new screenshots and screen recordings.
@MainActor
final class ClipsService: ObservableObject {
    @Published private(set) var clips: [Clip] = []

    private let pasteboard = NSPasteboard.general
    private var lastChange: Int
    private var pollTimer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    private var knownFiles = Set<String>()
    private let maxClips = 24

    init() {
        lastChange = pasteboard.changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        applyPrefs()
    }

    func applyPrefs() {
        if Prefs.d.bool(forKey: Prefs.clipsEnabled) && Prefs.d.bool(forKey: Prefs.clipsScreenshots) {
            watchScreenshots()
        } else {
            dirSource?.cancel()
            dirSource = nil
        }
    }

    func copy(_ clip: Clip) {
        pasteboard.clearContents()
        switch clip.kind {
        case let .text(s): pasteboard.setString(s, forType: .string)
        case let .image(img): pasteboard.writeObjects([img])
        case let .file(url): pasteboard.writeObjects([url as NSURL])
        }
        lastChange = pasteboard.changeCount // don't re-capture our own copy
    }

    func remove(_ clip: Clip) { clips.removeAll { $0.id == clip.id } }
    func clear() { clips.removeAll() }

    private func push(_ clip: Clip) {
        clips.insert(clip, at: 0)
        if clips.count > maxClips { clips.removeLast(clips.count - maxClips) }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard Prefs.d.bool(forKey: Prefs.clipsEnabled) else { return }
        // Respect apps that mark items as secret (password managers).
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first {
            push(Clip(kind: .file(url)))
        } else if let img = NSImage(pasteboard: pasteboard), types.contains(.png) || types.contains(.tiff) {
            push(Clip(kind: .image(img)))
        } else if let s = pasteboard.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if case let .text(last)? = clips.first?.kind, last == s { return }
            push(Clip(kind: .text(s)))
        }
    }

    // MARK: Screenshots

    private var screenshotFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func watchScreenshots() {
        guard dirSource == nil else { return }
        let folder = screenshotFolder
        knownFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan(folder) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
    }

    private func scan(_ folder: URL) {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let added = names.subtracting(knownFiles)
        knownFiles = names
        for name in added.sorted() where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            guard let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image) || type.conforms(to: .movie) else { continue }
            push(Clip(kind: .file(url)))
        }
    }
}
