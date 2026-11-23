import Foundation

/// UserDefaults keys. Views read them with @AppStorage, services with `Prefs.*`.
enum Prefs {
    static let width = "notch.width"
    static let height = "notch.height"
    static let hoverToOpen = "notch.hoverToOpen"
    static let fakeNotch = "notch.fakeNotchOnPlainDisplays"
    /// "pointer", "builtin" or a CGDirectDisplayID as a string.
    static let displayPin = "notch.display"
    /// "notch" or "window".
    static let openMode = "notch.openMode"
    static let appearance = "look.appearance" // "dark" | "light"
    static let textScale = "look.textScale"
    static let haptics = "look.haptics"
    static let dayPrompts = "day.prompts"
    static let workdayEndHour = "day.endHour"
    static let taskSort = "day.sort"
    static let remindersSync = "day.remindersSync"
    static let focusStartShortcut = "focus.startShortcut"
    static let focusEndShortcut = "focus.endShortcut"
    /// Comma-separated bundle identifiers that trigger a nudge during focus.
    static let distractionApps = "focus.distractionApps"
    static let clipsEnabled = "clips.enabled"
    static let clipsScreenshots = "clips.screenshots"
    static let calendarEnabled = "calendar.enabled"
    /// Newline-separated ICS / webcal links.
    static let icsLinks = "calendar.icsLinks"
    static let travelAlerts = "calendar.travelAlerts"
    static let spotlight = "around.spotlight"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            width: 700.0, height: 380.0, hoverToOpen: false, fakeNotch: true, displayPin: "pointer",
            openMode: "notch", appearance: "dark", textScale: 1.0, haptics: true,
            dayPrompts: true, workdayEndHour: 18, taskSort: "smart", remindersSync: false,
            focusStartShortcut: "", focusEndShortcut: "", distractionApps: "",
            clipsEnabled: true, clipsScreenshots: true, calendarEnabled: true, icsLinks: "",
            travelAlerts: false, spotlight: true, "look.character": "builtin:popeye",
        ])
    }

    static var d: UserDefaults { .standard }
}
