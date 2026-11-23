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
        return (CGSize(width: 190, height: menuBar > 0 ? menuBar : 25), false)
    }
}

@MainActor
final class NotchWindowController {
    static let sidePill: CGFloat = 64 // extra width each side when a timer shows while closed
    private static let margin: CGFloat = 24

    private let model: AppModel
    private let panel = NotchPanel()
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var hoverWork: DispatchWorkItem?
    private var previousApp: NSRunningApplication?

    init(model: AppModel) {
        self.model = model
        screen = NSScreen.screens.first(where: \.isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]

        let host = NSHostingView(rootView: NotchRootView()
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.focus)
            .environmentObject(model.calendar)
            .environmentObject(model.clips))
        host.sizingOptions = []
        panel.contentView = host

        layout()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        model.$isOpen.removeDuplicates().sink { [weak self] open in
            self?.apply(open: open)
        }.store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }.store(in: &bag)

        installMonitors()
    }

    // MARK: Geometry

    private var expandedSize: CGSize {
        CGSize(width: Prefs.d.double(forKey: Prefs.width), height: Prefs.d.double(forKey: Prefs.height))
    }

    private func layout() {
        let info = screen.notchInfo
        if model.notchSize != info.size { model.notchSize = info.size }
        if model.screenHasHardwareNotch != info.hardware { model.screenHasHardwareNotch = info.hardware }
        let size = expandedSize
        let w = max(size.width, info.size.width + 2 * Self.sidePill) + 2 * Self.margin
        let h = size.height + Self.margin
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Clickable area of the closed notch on a screen, in global coordinates.
    private func closedHitRect(on s: NSScreen) -> NSRect {
        let info = s.notchInfo
        let extra = model.focus.clock.isActive ? Self.sidePill : 0
        let w = info.size.width + 2 * extra
        // A little taller than the notch so the very top pixel row is easy to hit.
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - info.size.height - 4, width: w, height: info.size.height + 4)
    }

    private func screensChanged() {
        if !NSScreen.screens.contains(screen) {
            screen = NSScreen.screens.first(where: \.isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]
        }
        layout()
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

    /// Screens where the closed notch is clickable.
    private var activeScreens: [NSScreen] {
        Prefs.d.bool(forKey: Prefs.followPointer) ? NSScreen.screens : [screen]
    }

    // MARK: Open / close

    func toggleFromHotKey() {
        if !model.isOpen, Prefs.d.bool(forKey: Prefs.followPointer), let s = screenUnderPointer() { moveTo(s) }
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
            guard event.keyCode == 53 else { return event } // Esc
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
            model.open()
        }
    }

    /// Visible area of the open notch, in global coordinates.
    private var openContentRect: NSRect {
        let size = expandedSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func globalMove() {
        guard Prefs.d.bool(forKey: Prefs.hoverToOpen), !model.isOpen else { return }
        let p = NSEvent.mouseLocation
        guard let s = activeScreens.first(where: { NSMouseInRect(p, closedHitRect(on: $0), false) }) else {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
