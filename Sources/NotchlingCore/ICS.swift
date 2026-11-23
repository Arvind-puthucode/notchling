import Foundation

/// Minimal iCalendar (RFC 5545) reader for subscribed calendar links.
/// Handles line folding, UTC / TZID / floating / all-day dates, and common RRULEs
/// (DAILY, WEEKLY with BYDAY, MONTHLY, YEARLY with INTERVAL, COUNT, UNTIL) plus EXDATE.
public enum ICS {
    public struct Event: Equatable, Sendable {
        public var uid: String
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        public var location: String?
        public var url: String?
        public var notes: String?
    }

    /// Events overlapping [from, to), with recurrences expanded.
    public static func events(in text: String, from: Date, to: Date) -> [Event] {
        var out: [Event] = []
        var overridden = Set<String>() // uid@start of RECURRENCE-ID instances
        var masters: [(Event, [String: (String, [String: String])], [Date])] = []

        for block in blocks(unfold(text)) {
            guard let start = date(block["DTSTART"]) else { continue }
            let allDay = block["DTSTART"]?.1["VALUE"] == "DATE" || block["DTSTART"]?.0.count == 8
            let end = date(block["DTEND"])
                ?? duration(block["DURATION"]?.0).map { start.addingTimeInterval($0) }
                ?? start.addingTimeInterval(allDay ? 86400 : 3600)
            let e = Event(
                uid: block["UID"]?.0 ?? UUID().uuidString,
                title: unescape(block["SUMMARY"]?.0 ?? "Untitled"),
                start: start, end: end,
                isAllDay: allDay,
                location: block["LOCATION"].map { unescape($0.0) },
                url: block["URL"]?.0,
                notes: block["DESCRIPTION"].map { unescape($0.0) })
            if let rid = date(block["RECURRENCE-ID"]) {
                overridden.insert("\(e.uid)@\(rid.timeIntervalSince1970)")
                if e.end > from && e.start < to { out.append(e) }
                continue
            }
            if block["STATUS"]?.0 == "CANCELLED" { continue }
            let exdates = (block["EXDATE"].map { [$0] } ?? [])
                .flatMap { v in v.0.split(separator: ",").compactMap { date((String($0), v.1)) } }
            masters.append((e, block, exdates))
        }

        for (e, block, exdates) in masters {
            guard let rule = block["RRULE"]?.0 else {
                if e.end > from && e.start < to { out.append(e) }
                continue
            }
            let length = e.end.timeIntervalSince(e.start)
            for s in expand(rule: rule, start: e.start, until: to) {
                let key = "\(e.uid)@\(s.timeIntervalSince1970)"
                guard !overridden.contains(key), !exdates.contains(s) else { continue }
                let end = s.addingTimeInterval(length)
                guard end > from, s < to else { continue }
                var copy = e
                copy.start = s
                copy.end = end
                out.append(copy)
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Parsing

    typealias Props = [String: (String, [String: String])]

    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    static func blocks(_ lines: [String]) -> [Props] {
        var result: [Props] = []
        var current: Props?
        var depth = 0 // skip nested VALARM etc.
        for line in lines {
            if line == "BEGIN:VEVENT" { current = [:]; depth = 0; continue }
            if line == "END:VEVENT" { if let c = current { result.append(c) }; current = nil; continue }
            guard current != nil else { continue }
            if line.hasPrefix("BEGIN:") { depth += 1; continue }
            if line.hasPrefix("END:") { depth -= 1; continue }
            guard depth == 0, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].split(separator: ";")
            guard let name = head.first.map({ String($0).uppercased() }) else { continue }
            var params: [String: String] = [:]
            for p in head.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { params[String(kv[0]).uppercased()] = String(kv[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            let value = String(line[line.index(after: colon)...])
            if current![name] == nil { current![name] = (value, params) }
            else if name == "EXDATE" { current![name]!.0 += "," + value }
        }
        return result
    }

    /// UTC ("Z"), TZID, floating (local) and all-day values.
    static func date(_ prop: (String, [String: String])?) -> Date? {
        guard let (value, params) = prop else { return nil }
        let v = value.trimmingCharacters(in: .whitespaces)
        var cal = Calendar(identifier: .gregorian)
        let digits = v.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        let y = Int(digits.prefix(4))!, mo = Int(digits.dropFirst(4).prefix(2))!, d = Int(digits.dropFirst(6).prefix(2))!
        var c = DateComponents(year: y, month: mo, day: d)
        if digits.count >= 14 {
            c.hour = Int(digits.dropFirst(8).prefix(2))
            c.minute = Int(digits.dropFirst(10).prefix(2))
            c.second = Int(digits.dropFirst(12).prefix(2))
        }
        if v.hasSuffix("Z") {
            cal.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            cal.timeZone = tz
        } else {
            cal.timeZone = .current
        }
        return cal.date(from: c)
    }

    /// ISO 8601 duration such as PT1H30M or P1D.
    static func duration(_ s: String?) -> TimeInterval? {
        guard let s, s.hasPrefix("P") || s.hasPrefix("-P") else { return nil }
        var total: TimeInterval = 0, num = ""
        for ch in s {
            if ch.isNumber { num.append(ch); continue }
            let n = Double(num) ?? 0
            switch ch {
            case "W": total += n * 604_800
            case "D": total += n * 86400
            case "H": total += n * 3600
            case "M": total += n * 60
            case "S": total += n
            default: break
            }
            num = ""
        }
        return total
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Recurrence

    static func expand(rule: String, start: Date, until horizon: Date, calendar: Calendar = .current) -> [Date] {
        var parts: [String: String] = [:]
        for p in rule.split(separator: ";") {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[String(kv[0]).uppercased()] = String(kv[1]) }
        }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let count = parts["COUNT"].flatMap(Int.init)
        let until = parts["UNTIL"].flatMap { date(($0, [:])) }
        let limit = min(horizon, until.map { $0.addingTimeInterval(1) } ?? horizon)
        let weekdays: [Int] = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { day in
            ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][String(day.suffix(2))]
        }

        var out: [Date] = []
        func emit(_ d: Date) -> Bool {
            guard d < limit else { return false }
            if d >= start { out.append(d) }
            if let count, out.count >= count { return false }
            return true
        }
        let maxIterations = 5000
        switch parts["FREQ"] {
        case "DAILY":
            for i in 0..<maxIterations {
                guard emit(calendar.date(byAdding: .day, value: i * interval, to: start)!) else { break }
            }
        case "WEEKLY":
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: start)] : weekdays.sorted()
            let startWeekday = calendar.component(.weekday, from: start)
            let weekStart = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: start)!
            outer: for w in 0..<maxIterations {
                let base = calendar.date(byAdding: .day, value: 7 * w * interval, to: weekStart)!
                for wd in days {
                    guard emit(calendar.date(byAdding: .day, value: wd - 1, to: base)!) else { break outer }
                }
            }
        case "MONTHLY":
            for i in 0..<maxIterations {
                guard emit(calendar.date(byAdding: .month, value: i * interval, to: start)!) else { break }
            }
        case "YEARLY":
            for i in 0..<maxIterations {
                guard emit(calendar.date(byAdding: .year, value: i * interval, to: start)!) else { break }
            }
        default:
            out = [start]
        }
        return out
    }
}
