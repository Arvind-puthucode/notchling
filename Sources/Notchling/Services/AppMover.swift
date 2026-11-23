import AppKit

/// If Notchling is launched from the DMG, Downloads, or a quarantine-translocated
/// path, offer to move it to /Applications and relaunch from there.
///
/// Running from those places breaks launch at login, the MCP server path and updates,
/// and makes macOS show the app as "not installed".
@MainActor
enum AppMover {
    static func offerIfNeeded() {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard bundle.pathExtension == "app" else { return } // `swift run` dev builds
        let original = originalURL(of: bundle)
        let path = original.path
        let installed = ["/Applications/", NSHomeDirectory() + "/Applications/"].contains { path.hasPrefix($0) }
        let fromDMG = path.hasPrefix("/Volumes/")
        let fromDownloads = path.hasPrefix(NSHomeDirectory() + "/Downloads/")
        guard !installed, fromDMG || fromDownloads || original != bundle else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Notchling to Applications?"
        alert.informativeText = "Notchling is running from \(fromDMG ? "the disk image" : "Downloads"). Moving it lets it launch at login and keep your settings working."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let dest = URL(fileURLWithPath: "/Applications/Notchling.app")
        do {
            // Quit any other running copy before replacing it.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            where app != .current { app.terminate() }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: original, to: dest)
            removexattr(dest.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        } catch {
            let fail = NSAlert()
            fail.messageText = "Couldn't move Notchling"
            fail.informativeText = "\(error.localizedDescription)\n\nDrag Notchling into the Applications folder instead."
            fail.runModal()
            return
        }

        // Relaunch from /Applications after this process exits, then eject the DMG.
        var script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"\(dest.path)\""
        if fromDMG {
            let volume = "/Volumes/" + (path.dropFirst("/Volumes/".count).split(separator: "/").first.map(String.init) ?? "")
            script += "; hdiutil detach \"\(volume)\" -quiet"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Undo App Translocation (quarantined apps run from a random read-only path).
    private static func originalURL(of url: URL) -> URL {
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let fn = unsafeBitCast(sym, to: Fn.self)
        return (fn(url as CFURL, nil)?.takeRetainedValue() as URL?) ?? url
    }
}
