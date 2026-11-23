import Foundation

/// Finds a video-call URL in calendar event fields.
public enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "around.co", "meet.jit.si", "facetime.apple.com", "chime.aws",
    ]

    public static func find(in fields: [String?]) -> URL? {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for field in fields.compactMap({ $0 }) {
            let range = NSRange(location: 0, length: (field as NSString).length)
            for match in detector.matches(in: field, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}
