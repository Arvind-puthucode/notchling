import AppKit
import SwiftUI

/// A character that lives in the notch: images for a few moods plus lines for app events.
///
/// Packs are folders with a `theme.json` and images. Built-in packs ship in the app; your own go in
/// `~/Library/Application Support/Notchling/Characters/<name>/` and never leave your Mac.
struct CharacterPack: Identifiable, Equatable {
    struct Manifest: Decodable {
        var name: String
        var credit: String?
        var accent: String?
        /// "paper" draws a cream card behind line art; "none" for transparent stickers.
        var frame: String?
        /// Mood -> one file name or a list of them (the avatar rotates through a list).
        var images: [String: ImageList]
        var lines: [String: [String]]
    }

    struct ImageList: Decodable {
        var files: [String]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let list = try? c.decode([String].self) { files = list } else { files = [try c.decode(String.self)] }
        }
    }

    enum Mood: String { case idle, happy, alert, focus }
    enum Event: String { case greeting, empty, allDone, done, reminder, focusStart, focusDone, focusing }

    let id: String
    let manifest: Manifest
    let folder: URL
    let builtIn: Bool
    private let images: [String: [NSImage]]

    init?(folder: URL, builtIn: Bool) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("theme.json")),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        id = (builtIn ? "builtin:" : "user:") + folder.lastPathComponent
        manifest = m
        self.folder = folder
        self.builtIn = builtIn
        var loaded: [String: [NSImage]] = [:]
        for (mood, list) in m.images {
            let imgs = list.files.compactMap { NSImage(contentsOf: folder.appendingPathComponent($0)) }
            if !imgs.isEmpty { loaded[mood] = imgs }
        }
        images = loaded
        guard !images.isEmpty else { return nil }
    }

    var name: String { manifest.name }
    var paperFrame: Bool { manifest.frame == "paper" }
    var accent: Color { manifest.accent.flatMap(Color.init(hex:)) ?? Tok.accent }

    /// One image for the mood; `seed` picks among several so the character changes poses.
    func image(_ mood: Mood, seed: Int = 0) -> NSImage {
        let list = images[mood.rawValue] ?? images["idle"] ?? images.values.first!
        return list[(seed & Int(Int32.max)) % list.count]
    }

    /// Changes every 20 minutes, so the idle pose rotates through the day without flickering.
    static var poseSeed: Int { Int(Date().timeIntervalSince1970 / 1200) }

    /// A line for an event with {open}, {done}, {total} filled in. `seed` keeps it stable between redraws.
    func line(_ event: Event, open: Int = 0, done: Int = 0, seed: Int = 0) -> String? {
        guard let options = manifest.lines[event.rawValue], !options.isEmpty else { return nil }
        return options[(seed & Int(Int32.max)) % options.count]
            .replacingOccurrences(of: "{open}", with: "\(open)")
            .replacingOccurrences(of: "{done}", with: "\(done)")
            .replacingOccurrences(of: "{total}", with: "\(open + done)")
    }

    static func == (a: CharacterPack, b: CharacterPack) -> Bool { a.id == b.id }
}

@MainActor
final class CharacterStore: ObservableObject {
    @Published private(set) var packs: [CharacterPack] = []
    @Published private(set) var current: CharacterPack?
    /// A short-lived reaction (task done, focus started) shown instead of the greeting.
    @Published private(set) var reaction: (event: CharacterPack.Event, mood: CharacterPack.Mood, seed: Int)?
    private var clearWork: DispatchWorkItem?

    static let prefKey = "look.character"
    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchling/Characters", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        var found: [CharacterPack] = []
        for (dir, builtIn) in [(Self.builtInFolder, true), (Self.userFolder, false)] {
            guard let dir, let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            found += items.sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { CharacterPack(folder: $0, builtIn: builtIn) }
        }
        packs = found
        select(Prefs.d.string(forKey: Self.prefKey) ?? "")
    }

    func select(_ id: String) {
        Prefs.d.set(id, forKey: Self.prefKey)
        current = packs.first { $0.id == id }
    }

    func react(_ event: CharacterPack.Event, mood: CharacterPack.Mood = .happy, for seconds: Double = 3.5) {
        guard current != nil else { return }
        withAnimation(Tok.spring) { reaction = (event, mood, Int.random(in: 0..<1000)) }
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(Tok.spring) { self?.reaction = nil } }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func openUserFolder() {
        try? FileManager.default.createDirectory(at: Self.userFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.userFolder)
    }

    /// Inside the .app: Contents/Resources/Characters. In `swift run`: the repo's Resources/Characters.
    private static var builtInFolder: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Characters"), FileManager.default.fileExists(atPath: r.path) { return r }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Characters")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The character's face. Line-art packs get a newsprint card so black ink reads on the dark notch.
struct CharacterAvatar: View {
    let pack: CharacterPack
    var mood: CharacterPack.Mood = .idle
    var size: CGFloat = 52
    var seed: Int = CharacterPack.poseSeed

    var body: some View {
        let img = Image(nsImage: pack.image(mood, seed: seed)).resizable().interpolation(.high)
        Group {
            if pack.paperFrame {
                img.scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color(red: 0.98, green: 0.95, blue: 0.86))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(pack.accent, lineWidth: 2))
            } else {
                img.scaledToFit().frame(width: size * 1.15, height: size * 1.15)
            }
        }
        .id("\(mood.rawValue)-\(seed)") // swap images with a little pop
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Character + speech bubble used at the top of Today.
struct CharacterCard: View {
    @EnvironmentObject var characters: CharacterStore
    let open: Int
    let done: Int
    var focusing = false

    var body: some View {
        if let pack = characters.current {
            let reaction = characters.reaction
            let seed = CharacterPack.poseSeed + open
            let line: String = {
                if let r = reaction { return pack.line(r.event, open: open, done: done, seed: r.seed) ?? "" }
                if focusing, let l = pack.line(.focusing, seed: seed) { return l }
                if open + done == 0 { return pack.line(.empty, seed: seed) ?? "" }
                if open == 0 { return pack.line(.allDone, open: open, done: done, seed: seed) ?? "" }
                return pack.line(.greeting, open: open, done: done, seed: seed) ?? ""
            }()
            HStack(alignment: .center, spacing: 8) {
                CharacterAvatar(pack: pack, mood: reaction?.mood ?? (focusing ? .focus : open == 0 && done > 0 ? .happy : .idle),
                                size: 50, seed: reaction?.seed ?? CharacterPack.poseSeed)
                Text(line)
                    .nfont(12, .semibold)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(SpeechBubble().fill(pack.accent.opacity(0.18)))
                    .overlay(SpeechBubble().stroke(pack.accent.opacity(0.45), lineWidth: 1))
                    .id(line)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                Spacer(minLength: 0)
            }
            .animation(Tok.spring, value: line)
        }
    }
}

/// Rounded bubble with a tail pointing left at the character.
struct SpeechBubble: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 10, style: .continuous)
        p.move(to: CGPoint(x: r.minX, y: r.midY - 5))
        p.addLine(to: CGPoint(x: r.minX - 6, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + 5))
        return p
    }
}
