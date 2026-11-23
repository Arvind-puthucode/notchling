// Composes promo images from real app captures.
//   swift scripts/make-promo.swift <captures-dir> <out-dir>
// Expects shot-today/week/focus/insights/alert/pill.png (panel window captures with transparent margins).
import AppKit

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let accent = NSColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1)

struct Copy {
    var heroTitle = "Notchling"
    var heroSub = "Tasks, notes, focus and your calendar, right in your Mac's notch."
    var chips = ["Free", "Open source · MIT", "macOS 14+", "Apple silicon & Intel", "MCP for AI agents"]
    var gridTitle = "Everything lives in the notch"
    var gridSub = "Click it or press ⌥N. No account. Your data stays on your Mac."
    var tiles = [("Plan the week", "Drag tasks between days, beside your events"),
                 ("Know where your time went", "Streaks, focus minutes, best hours"),
                 ("Deep focus", "Timer, ambient sounds, app nudges")]
    var alertCaption = "Live reminders pop out of the notch"
    var pillCaption = "Your timer keeps running beside it"
    var claudeTitle = "Tell Claude. It lands in your notch."
    var claudeSub = "Notchling ships a local MCP server for Claude Code, the Claude app and Cursor."
    var prompt = "Plan the rest of my launch day in Notchling. I still need to record a 30s demo video, write the launch tweet thread, reply to GitHub issues, and prep tomorrow's standup notes. Add them for today from 5pm, mark the tweet thread important, then start a 25-minute focus session."
    var calls = [("add_task", "\"Record 30s demo video today at 5pm\""), ("add_task", "\"Write launch tweet thread today at 5:30pm !\""),
                 ("add_task", "\"Reply to GitHub issues today at 6:30pm\""), ("add_task", "\"Prep tomorrow's standup notes today at 7:30pm\""),
                 ("focus", "start · 25 min")]
    var reply = "Added 4 tasks for today: 5:00 demo video, 5:30 tweet thread (marked important), 6:30 GitHub issues, 7:30 standup notes. 25-minute focus timer is running."
}

let copy = Copy()

/// Loads a capture and trims fully transparent margins.
func shot(_ name: String) -> CGImage {
    let img = NSImage(contentsOf: src.appendingPathComponent("shot-\(name).png"))!
    let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = cg.width, h = cg.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    // Bitmap rows are top-down in memory; crop rect uses the same top-left origin.
    return cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    draw(g.cgContext, CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func background(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    NSGradient(colors: [NSColor(red: 0.07, green: 0.06, blue: 0.09, alpha: 1), NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
    // Warm glow behind the notch.
    let glow = NSGradient(colors: [accent.withAlphaComponent(0.28), accent.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: w / 2, y: h * 0.78), radius: 0, toCenter: NSPoint(x: w / 2, y: h * 0.78), radius: w * 0.42, options: [])
}

func text(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, center: Bool = true, width: CGFloat = 0) {
    let para = NSMutableParagraphStyle()
    para.alignment = center ? .center : .left
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: -size * 0.02])
    let w = width > 0 ? width : attr.size().width + 4
    attr.draw(in: NSRect(x: center ? p.x - w / 2 : p.x, y: p.y, width: w, height: size * 1.4))
}

func place(_ img: CGImage, _ c: CGContext, center x: CGFloat, top y: CGFloat, width: CGFloat, shadow: Bool = true) -> CGRect {
    let h = width * CGFloat(img.height) / CGFloat(img.width)
    let r = CGRect(x: x - width / 2, y: y - h, width: width, height: h)
    c.saveGState()
    if shadow { c.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: NSColor.black.withAlphaComponent(0.7).cgColor) }
    c.draw(img, in: r)
    c.restoreGState()
    return r
}

/// Screen top edge with a menu bar, so the notch reads as "in the Mac".
func screenEdge(_ c: CGContext, _ w: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, centerX: CGFloat? = nil, menuBar: CGFloat = 64) {
    let cx = centerX ?? w / 2
    let rect = CGRect(x: cx - width / 2, y: top - height, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    c.saveGState()
    c.addPath(path)
    c.clip()
    NSGradient(colors: [NSColor(red: 0.16, green: 0.12, blue: 0.22, alpha: 1), NSColor(red: 0.30, green: 0.16, blue: 0.18, alpha: 1),
                        NSColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1)])!
        .draw(in: rect, angle: -90)
    NSColor.black.withAlphaComponent(0.55).setFill()
    NSRect(x: rect.minX, y: rect.maxY - menuBar, width: rect.width, height: menuBar).fill()
    c.restoreGState()
    c.addPath(path)
    c.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    c.setLineWidth(3)
    c.strokePath()
}

func chip(_ s: String, center: NSPoint, _ c: CGContext) {
    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let w = (s as NSString).size(withAttributes: [.font: font]).width + 48
    let r = NSRect(x: center.x - w / 2, y: center.y - 30, width: w, height: 60)
    NSColor.white.withAlphaComponent(0.08).setFill()
    NSBezierPath(roundedRect: r, xRadius: 30, yRadius: 30).fill()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 29, yRadius: 29).stroke()
    text(s, at: NSPoint(x: center.x, y: center.y - 22), size: 30, weight: .semibold, color: NSColor.white.withAlphaComponent(0.85))
}

// MARK: 1. Hero (16:9)

let today = shot("today")
let hero = canvas(3200, 1800) { c, w, h in
    background(c, w, h)
    screenEdge(c, w, top: h - 70, width: 2500, height: 1020)
    _ = place(today, c, center: w / 2, top: h - 70, width: 1900)
    text(copy.heroTitle, at: NSPoint(x: w / 2, y: 470), size: 150, weight: .heavy, color: .white)
    text(copy.heroSub, at: NSPoint(x: w / 2, y: 380), size: 54, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.7))
    let chips = copy.chips
    let spacing: CGFloat = 40
    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let widths = chips.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 48 }
    var x = w / 2 - (widths.reduce(0, +) + spacing * CGFloat(chips.count - 1)) / 2
    for (s, cw) in zip(chips, widths) {
        chip(s, center: NSPoint(x: x + cw / 2, y: 230), c)
        x += cw + spacing
    }
}
try! hero.write(to: out.appendingPathComponent("notchling-hero.png"))

// MARK: 2. Feature grid (16:9)

let tiles: [(String, String, CGImage)] = [
    (copy.tiles[0].0, copy.tiles[0].1, shot("week")),
    (copy.tiles[1].0, copy.tiles[1].1, shot("insights")),
    (copy.tiles[2].0, copy.tiles[2].1, shot("focus")),
]
let alert = shot("alert"), pill = shot("pill")
let grid = canvas(3200, 1800) { c, w, h in
    background(c, w, h)
    text(copy.gridTitle, at: NSPoint(x: w / 2, y: h - 190), size: 96, weight: .heavy, color: .white)
    text(copy.gridSub, at: NSPoint(x: w / 2, y: h - 270), size: 44, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.6))
    let tileW: CGFloat = 960, gap: CGFloat = 70
    let startX = (w - (tileW * 3 + gap * 2)) / 2
    for (i, t) in tiles.enumerated() {
        let cx = startX + tileW / 2 + CGFloat(i) * (tileW + gap)
        let panelH = (tileW - 80) * CGFloat(t.2.height) / CGFloat(t.2.width)
        screenEdge(c, w, top: h - 380, width: tileW, height: panelH + 60, centerX: cx, menuBar: 26)
        var r = place(t.2, c, center: cx, top: h - 380, width: tileW - 80)
        r.origin.y -= 60
        text(t.0, at: NSPoint(x: cx, y: r.minY - 90), size: 46, weight: .bold, color: .white)
        text(t.1, at: NSPoint(x: cx, y: r.minY - 148), size: 32, weight: .regular, color: NSColor.white.withAlphaComponent(0.55))
    }
    // Bottom row: live activity + timer beside the closed notch.
    let rowTop: CGFloat = 600
    screenEdge(c, w, top: rowTop, width: 1400, height: 300, centerX: w * 0.36, menuBar: 40)
    screenEdge(c, w, top: rowTop, width: 1000, height: 300, centerX: w * 0.78, menuBar: 40)
    var a = place(alert, c, center: w * 0.36, top: rowTop, width: 1100)
    a.origin.y = rowTop - 300
    text(copy.alertCaption, at: NSPoint(x: w * 0.36, y: a.minY - 80), size: 36, weight: .semibold,
         color: NSColor.white.withAlphaComponent(0.8))
    var p = place(pill, c, center: w * 0.78, top: rowTop, width: 640)
    p.origin.y = rowTop - 300
    text(copy.pillCaption, at: NSPoint(x: w * 0.78, y: p.minY - 80), size: 36, weight: .semibold,
         color: NSColor.white.withAlphaComponent(0.8))
}
try! grid.write(to: out.appendingPathComponent("notchling-features.png"))
print("wrote", out.path)

// MARK: 3. Claude + MCP use case (16:9), from a real `claude -p` run against notchling-mcp

if FileManager.default.fileExists(atPath: src.appendingPathComponent("shot-mcp.png").path) {
    let notch = shot("mcp")
    let mono = { (size: CGFloat, w: NSFont.Weight) in NSFont.monospacedSystemFont(ofSize: size, weight: w) }

    func block(_ s: NSAttributedString, in r: NSRect) { s.draw(with: r, options: [.usesLineFragmentOrigin]) }
    func line(_ parts: [(String, NSColor, NSFont)]) -> NSAttributedString {
        let a = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 10
        for (t, c, f) in parts { a.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: para])) }
        return a
    }

    let img = canvas(3200, 1800) { c, w, h in
        background(c, w, h)
        text(copy.claudeTitle, at: NSPoint(x: w / 2, y: h - 200), size: 104, weight: .heavy, color: .white)
        text(copy.claudeSub, at: NSPoint(x: w / 2, y: h - 285),
             size: 44, weight: .medium, color: NSColor.white.withAlphaComponent(0.6))

        // Terminal card.
        let term = NSRect(x: 130, y: 1380 - 830, width: 1500, height: 830)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: term, xRadius: 28, yRadius: 28).fill()
        c.restoreGState()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        NSBezierPath(roundedRect: term.insetBy(dx: 1, dy: 1), xRadius: 27, yRadius: 27).stroke()
        for (i, col) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            col.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: term.minX + 36 + CGFloat(i) * 40, y: term.maxY - 56, width: 24, height: 24)).fill()
        }
        text("claude", at: NSPoint(x: term.midX, y: term.maxY - 60), size: 28, weight: .semibold, color: NSColor.white.withAlphaComponent(0.4))

        let dim = NSColor.white.withAlphaComponent(0.5), body = NSColor.white.withAlphaComponent(0.92)
        let orange = accent, green = NSColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1)
        let f = mono(29, .regular), fb = mono(29, .semibold)
        var y = term.maxY - 110
        func put(_ a: NSAttributedString, height: CGFloat) {
            block(a, in: NSRect(x: term.minX + 50, y: y - height, width: term.width - 100, height: height))
            y -= height + 22
        }
        put(line([("> ", orange, fb), (copy.prompt, body, f)]), height: 200)
        let calls: [(String, String)] = [
            ("add_task", "\"Record 30s demo video today at 5pm\""),
            ("add_task", "\"Write launch tweet thread today at 5:30pm !\""),
            ("add_task", "\"Reply to GitHub issues today at 6:30pm\""),
            ("add_task", "\"Prep tomorrow's standup notes today at 7:30pm\""),
            ("focus", "start · 25 min"),
        ]
        for (tool, arg) in calls {
            put(line([("● ", green, fb), ("notchling.\(tool)", body, fb), ("  \(arg)", dim, f)]), height: 44)
        }
        y -= 14
        y -= 6
        put(line([("● ", orange, fb), (copy.reply, body, f)]), height: 160)

        // Arrow.
        accent.setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 8
        arrow.lineCapStyle = .round
        arrow.move(to: NSPoint(x: 1680, y: 980))
        arrow.line(to: NSPoint(x: 1790, y: 980))
        arrow.stroke()
        accent.setFill()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 1820, y: 980)); head.line(to: NSPoint(x: 1786, y: 1004)); head.line(to: NSPoint(x: 1786, y: 956)); head.close()
        head.fill()

        // The notch, on a screen.
        let cx: CGFloat = 2470, top: CGFloat = 1380
        let panelW: CGFloat = 1180
        let panelH = panelW * CGFloat(notch.height) / CGFloat(notch.width)
        screenEdge(c, w, top: top, width: 1320, height: panelH + 120, centerX: cx, menuBar: 34)
        _ = place(notch, c, center: cx, top: top, width: panelW)

        // Setup line.
        let cmd = "claude mcp add notchling -- /Applications/Notchling.app/Contents/MacOS/notchling-mcp"
        let cf = mono(30, .medium)
        let cw = (cmd as NSString).size(withAttributes: [.font: cf]).width + 70
        let r = NSRect(x: w / 2 - cw / 2, y: 260, width: cw, height: 76)
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: r, xRadius: 38, yRadius: 38).fill()
        NSAttributedString(string: cmd, attributes: [.font: cf, .foregroundColor: NSColor.white.withAlphaComponent(0.75)])
            .draw(at: NSPoint(x: r.minX + 35, y: r.minY + 20))
    }
    try! img.write(to: out.appendingPathComponent("notchling-claude.png"))
}
