import Foundation

/// UserDefaults keys. Views read them with @AppStorage, services with `Prefs.*`.
enum Prefs {
    static let width = "notch.width"
    static let height = "notch.height"
    static let hoverToOpen = "notch.hoverToOpen"
    static let fakeNotch = "notch.fakeNotchOnPlainDisplays"
    static let followPointer = "notch.followPointer"
    static let dayPrompts = "day.prompts"
    static let workdayEndHour = "day.endHour"
    static let focusStartShortcut = "focus.startShortcut"
    static let focusEndShortcut = "focus.endShortcut"
    static let clipsEnabled = "clips.enabled"
    static let clipsScreenshots = "clips.screenshots"
    static let calendarEnabled = "calendar.enabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            width: 680.0, height: 360.0, hoverToOpen: false, fakeNotch: true, followPointer: true,
            dayPrompts: true, workdayEndHour: 18, focusStartShortcut: "", focusEndShortcut: "",
            clipsEnabled: true, clipsScreenshots: true, calendarEnabled: true,
        ])
    }

    static var d: UserDefaults { .standard }
}
