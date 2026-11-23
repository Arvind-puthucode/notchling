import AppKit
import NotchlingCore
import Security

/// API keys live in the login Keychain, never in preferences.
enum Keychain {
    private static let service = "dev.notchling.app"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Events from subscribed ICS links and Calendly / Cal.com bookings.
@MainActor
final class ExternalCalendars: ObservableObject {
    static let calendlyKey = "calendly.token"
    static let calcomKey = "calcom.key"

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var errors: [String] = []
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        Task { await load() }
    }

    private func load() async {
        let from = Calendar.current.startOfDay(for: Date())
        let to = Calendar.current.date(byAdding: .day, value: 14, to: from)!
        var all: [CalEvent] = []
        var errs: [String] = []

        let links = (Prefs.d.string(forKey: Prefs.icsLinks) ?? "")
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for link in links {
            let fixed = link.hasPrefix("webcal://") ? "https://" + link.dropFirst("webcal://".count) : link
            guard let url = URL(string: fixed) else { errs.append("Bad link: \(link)"); continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(decoding: data, as: UTF8.self)
                all += ICS.events(in: text, from: from, to: to).map { e in
                    CalEvent(id: "ics-\(e.uid)-\(e.start.timeIntervalSince1970)", title: e.title, start: e.start, end: e.end,
                             isAllDay: e.isAllDay, color: .systemTeal, location: e.location,
                             joinURL: MeetingLink.find(in: [e.url, e.location, e.notes]))
                }
            } catch {
                errs.append("\(url.host ?? link): \(error.localizedDescription)")
            }
        }
        if let token = Keychain.get(Self.calendlyKey) {
            do { all += try await calendly(token: token, from: from, to: to) } catch { errs.append("Calendly: \(error.localizedDescription)") }
        }
        if let key = Keychain.get(Self.calcomKey) {
            do { all += try await calcom(key: key) } catch { errs.append("Cal.com: \(error.localizedDescription)") }
        }
        events = all
        errors = errs
    }

    // MARK: Calendly (API v2, personal access token)

    private func calendly(token: String, from: Date, to: Date) async throws -> [CalEvent] {
        let me = try await getJSON("https://api.calendly.com/users/me", bearer: token)
        guard let resource = me["resource"] as? [String: Any], let user = resource["uri"] as? String else { throw APIError.unexpected }
        var c = URLComponents(string: "https://api.calendly.com/scheduled_events")!
        let iso = ISO8601DateFormatter()
        c.queryItems = [
            .init(name: "user", value: user), .init(name: "status", value: "active"),
            .init(name: "min_start_time", value: iso.string(from: from)), .init(name: "max_start_time", value: iso.string(from: to)),
            .init(name: "count", value: "100"),
        ]
        let list = try await getJSON(c.url!.absoluteString, bearer: token)
        let rows = list["collection"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let s = (row["start_time"] as? String).flatMap(Self.parseISO),
                  let e = (row["end_time"] as? String).flatMap(Self.parseISO) else { return nil }
            let loc = row["location"] as? [String: Any]
            let join = (loc?["join_url"] as? String).flatMap(URL.init(string:))
            return CalEvent(id: "calendly-\(row["uri"] as? String ?? UUID().uuidString)", title: row["name"] as? String ?? "Calendly booking",
                            start: s, end: e, isAllDay: false, color: .systemBlue, location: loc?["location"] as? String,
                            joinURL: join ?? MeetingLink.find(in: [loc?["location"] as? String]))
        }
    }

    // MARK: Cal.com (API v2)

    private func calcom(key: String) async throws -> [CalEvent] {
        let json = try await getJSON("https://api.cal.com/v2/bookings?status=upcoming&take=100", bearer: key,
                                     headers: ["cal-api-version": "2024-08-13"])
        let rows = json["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let s = (row["start"] as? String).flatMap(Self.parseISO),
                  let e = (row["end"] as? String).flatMap(Self.parseISO) else { return nil }
            let location = row["location"] as? String
            let join = (row["meetingUrl"] as? String).flatMap(URL.init(string:)) ?? MeetingLink.find(in: [location])
            return CalEvent(id: "calcom-\(row["uid"] as? String ?? "\(row["id"] ?? UUID())")", title: row["title"] as? String ?? "Cal.com booking",
                            start: s, end: e, isAllDay: false, color: .systemIndigo, location: location, joinURL: join)
        }
    }

    enum APIError: LocalizedError {
        case http(Int), unexpected
        var errorDescription: String? {
            switch self {
            case let .http(code): return code == 401 ? "key rejected (401)" : "HTTP \(code)"
            case .unexpected: return "unexpected response"
            }
        }
    }

    private func getJSON(_ url: String, bearer: String, headers: [String: String] = [:]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw APIError.http(http.statusCode) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.unexpected }
        return obj
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
