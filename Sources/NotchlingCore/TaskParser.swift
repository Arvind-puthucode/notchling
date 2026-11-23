import Foundation

/// Turns a typed phrase such as "call mom tomorrow at 5pm !" into a task.
///
/// Rules:
/// - A date phrase found by `NSDataDetector` sets the day. If the phrase names a
///   time ("5pm", "17:30", "noon"), it also sets a reminder time.
/// - `!` anywhere marks the task important.
/// - URLs become attached links and are removed from the title.
public enum TaskParser {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var day: Date?
        public var due: Date?
        public var important: Bool
        public var links: [String]
    }

    private static let timeWords = try! NSRegularExpression(
        pattern: #"(\b\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)\b)|(\b\d{1,2}:\d{2}\b)|\b(noon|midnight|morning|afternoon|evening|tonight)\b"#,
        options: [.caseInsensitive])
    private static let danglingWords = try! NSRegularExpression(
        pattern: #"\s+(at|on|by|due|for|from|this|next)\s*$"#, options: [.caseInsensitive])

    public static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Result? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var important = false
        if text.contains("!") {
            important = true
            text = text.replacingOccurrences(of: "!", with: "")
        }

        var links: [String] = []
        var day: Date?
        var due: Date?
        let types: NSTextCheckingResult.CheckingType = [.date, .link]
        let detector = try! NSDataDetector(types: types.rawValue)
        let ns = text as NSString
        var removals: [NSRange] = []
        var dates: [(range: NSRange, date: Date, hasTime: Bool)] = []
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.resultType == .link, let url = match.url {
                links.append(url.absoluteString)
                removals.append(match.range)
            } else if match.resultType == .date, let date = match.date {
                // "tomorrow's standup" names a thing, not when the task happens.
                let after = NSMaxRange(match.range)
                if after + 1 < ns.length, ["'s", "’s"].contains(ns.substring(with: NSRange(location: after, length: 2))) { continue }
                let phrase = ns.substring(with: match.range)
                let hasTime = timeWords.firstMatch(in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length)) != nil
                dates.append((match.range, date, hasTime))
            }
        }
        // With several date phrases, the one that names a time wins ("prep Monday deck today at 5pm").
        if let pick = dates.first(where: \.hasTime) ?? dates.first {
            day = calendar.startOfDay(for: pick.date)
            due = pick.hasTime ? pick.date : nil
            removals.append(pick.range)
        }
        let mutable = NSMutableString(string: text)
        for range in removals.sorted(by: { $0.location > $1.location }) {
            mutable.replaceCharacters(in: range, with: " ")
        }
        var title = (mutable as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Drop prepositions left behind by the removed date ("call mom at").
        while let m = danglingWords.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) {
            title = (title as NSString).replacingCharacters(in: m.range, with: "")
        }
        title = title.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        if title.isEmpty { title = raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Result(title: title, day: day, due: due, important: important, links: links)
    }
}
