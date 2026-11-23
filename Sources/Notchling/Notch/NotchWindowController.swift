import AppKit
import Combine
import SwiftUI

/// Borderless panel that floats above the menu bar at the top center of a screen.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    // Lets text fields take typing without activating the app (Spotlight-style).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    var isBuiltin: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    /// Hardware notch size, or a menu-bar-height stand-in on displays without one.
    var notchInfo: (size: CGSize, hardware: Bool) {
        if safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            return (CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top), true)
        }
        let menuBar = frame.maxY - visibleFrame.maxY
        return (CGSize(width: 190, height: menuBar > 4 ? menuBar : 25), false)
    }

    /// A full-screen app (or auto-hide) has hidden the menu bar on this display.
    var menuBarHidden: Bool { visibleFrame.maxY >= frame.maxY - 1 }
}

@MainActor
final class NotchWindowController {
    static let sidePill: CGFloat = 64 // extra width each side when a timer shows while closed
    private static let margin: CGFloat = 30

    private let model: AppModel
    private let panel = NotchPanel()
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var hoverWork: DispatchWorkItem?
    private var previousApp: NSRunningApplication?
    private lazy var workspaceWindow = WorkspaceWindowController(model: model)

    init(model: AppModel) {
        self.model = model
        screen = NSScreen.screens.first(where: \.isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]

        let host = NSHostingView(rootView: NotchRootView().withServices(model))
        host.sizingOptions = []
        panel.contentView = host

        model.showWindow = { [weak self] in self?.workspaceWindow.show() }
        screen = pinnedScreen() ?? screen
        layout()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        model.$isOpen.removeDuplicates().sink { [weak self] open in
            self?.apply(open: open)
        }.store(in: &bag)

        let nc = NotificationCenter.default
        nc.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &bag)
        nc.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prefsChanged() }.store(in: &bag)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .delay(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }.store(in: &bag)

        installMonitors()
    }

    // MARK: Geometry

    private var maxOpenSize: CGSize {
        CGSize(width: Prefs.d.double(forKey: Prefs.width), height: Prefs.d.double(forKey: Prefs.height))
    }

    private func layout() {
        let info = screen.notchInfo
        if model.notchSize != info.size { model.notchSize = info.size }
        if model.screenHasHardwareNotch != info.hardware { model.screenHasHardwareNotch = info.hardware }
        let hidden = !info.hardware && screen.menuBarHidden
        if model.menuBarHidden != hidden { model.menuBarHidden = hidden }
        let size = maxOpenSize
        let w = max(size.width, 520, info.size.width + 2 * Self.sidePill) + 2 * Self.margin
        let h = size.height + Self.margin
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Clickable area of the closed notch on a screen, in global coordinates.
    private func closedHitRect(on s: NSScreen) -> NSRect {
        let info = s.notchInfo
        let extra = model.focus.clock.isActive ? Self.sidePill : 0
        let w = info.size.width + 2 * extra
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - info.size.height - 4, width: w, height: info.size.height + 4)
    }

    /// Visible area of the open notch, in global coordinates.
    private var openContentRect: NSRect {
        let size = model.openSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func prefsChanged() {
        if let pinned = pinnedScreen(), pinned != screen { screen = pinned }
        layout()
    }

    private func screensChanged() {
        if let pinned = pinnedScreen() {
            screen = pinned
        } else if !NSScreen.screens.contains(screen) {
            screen = NSScreen.screens.first(where: \.isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]
        }
        layout()
    }

    /// The display chosen under Settings › Show on, or nil to follow the pointer.
    private func pinnedScreen() -> NSScreen? {
        let pin = Prefs.d.string(forKey: Prefs.displayPin) ?? "pointer"
        switch pin {
        case "pointer": return nil
        case "builtin": return NSScreen.screens.first(where: \.isBuiltin) ?? NSScreen.main
        default: return NSScreen.screens.first { String($0.displayID) == pin }
        }
    }

    private func moveTo(_ s: NSScreen) {
        guard s != screen else { return }
        screen = s
        layout()
    }

    private func screenUnderPointer() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    /// Screens whose closed notch responds to the pointer.
    private var activeScreens: [NSScreen] {
        if let pinned = pinnedScreen() { return [pinned] }
        return NSScreen.screens.filter { $0.notchInfo.hardware || !$0.menuBarHidden }
    }

    // MARK: Open / close

    func toggleFromHotKey() {
        if !model.isOpen, pinnedScreen() == nil, let s = screenUnderPointer() { moveTo(s) }
        model.toggle()
    }

    private func apply(open: Bool) {
        panel.ignoresMouseEvents = !open
        if open {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.resignKey()
            panel.orderFrontRegardless()
            // Give typing focus back to whatever app the user was in.
            previousApp?.activate()
            previousApp = nil
        }
    }

    private func installMonitors() {
        // Global monitors see events headed to other apps; mouse ones need no permission.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.globalClick() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.globalMove() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53, self?.panel.isKeyWindow == true else { return event } // Esc
            MainActor.assumeIsolated { self?.model.close() }
            return nil
        }) { monitors.append(m) }
    }

    private func globalClick() {
        let p = NSEvent.mouseLocation
        if model.isOpen {
            // Clicks on the panel's transparent margin fall through to other apps and land here too.
            if !NSMouseInRect(p, openContentRect, false) { model.close() }
            return
        }
        if let s = activeScreens.first(where: { NSMouseInRect(p, closedHitRect(on: $0), false) }) {
            moveTo(s)
            model.hoveringClosedNotch = false
            model.open()
        }
    }

    private func globalMove() {
        guard !model.isOpen else {
            if model.hoveringClosedNotch { model.hoveringClosedNotch = false }
            return
        }
        let p = NSEvent.mouseLocation
        let hit = activeScreens.first(where: { NSMouseInRect(p, closedHitRect(on: $0), false) })
        if (hit != nil && hit == screen) != model.hoveringClosedNotch {
            model.hoveringClosedNotch = hit != nil && hit == screen
            if model.hoveringClosedNotch { model.haptic() }
        }
        guard Prefs.d.bool(forKey: Prefs.hoverToOpen) else { return }
        guard let s = hit else {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard NSMouseInRect(NSEvent.mouseLocation, self.closedHitRect(on: s), false) else { return }
            self.moveTo(s)
            self.model.open()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

/// Window mode: the same workspace in a normal resizable window.
@MainActor
final class WorkspaceWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 620, height: 380)
            w.contentView = NSHostingView(rootView: WorkspaceWindowView().withServices(model))
            w.center()
            w.setFrameAutosaveName("NotchlingWorkspace")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WorkspaceWindowView: View {
    @AppStorage(Prefs.appearance) private var appearance = "dark"
    @AppStorage(Prefs.textScale) private var textScale = 1.0

    var body: some View {
        ExpandedView(inNotch: false)
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .background(NotchBackground.color(light: appearance == "light"))
            .environment(\.colorScheme, appearance == "light" ? .light : .dark)
            .environment(\.textScale, textScale)
    }
}

extension View {
    /// Injects every service the workspace views read.
    @MainActor func withServices(_ model: AppModel) -> some View {
        environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.focus)
            .environmentObject(model.calendar)
            .environmentObject(model.clips)
            .environmentObject(model.speech)
            .environmentObject(model.external)
            .environmentObject(model.reminders)
            .environmentObject(model.characters)
    }
}
