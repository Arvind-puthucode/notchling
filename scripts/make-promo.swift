// Composes promo images from real app captures.
//   swift scripts/make-promo.swift <captures-dir> <out-dir>
// Expects shot-today/week/focus/insights/alert/pill.png (panel window captures with transparent margins).
import AppKit

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let accent = NSColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1)

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
    text("Notchling", at: NSPoint(x: w / 2, y: 470), size: 150, weight: .heavy, color: .white)
    text("Tasks, notes, focus and your calendar, right in your Mac's notch.", at: NSPoint(x: w / 2, y: 380), size: 54, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.7))
    let chips = ["Free", "Open source · MIT", "macOS 14+", "Apple silicon & Intel", "MCP for AI agents"]
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
    ("Plan the week", "Drag tasks between days, beside your events", shot("week")),
    ("Know where your time went", "Streaks, focus minutes, best hours", shot("insights")),
    ("Deep focus", "Timer, ambient sounds, app nudges", shot("focus")),
]
let alert = shot("alert"), pill = shot("pill")
let grid = canvas(3200, 1800) { c, w, h in
    background(c, w, h)
    text("Everything lives in the notch", at: NSPoint(x: w / 2, y: h - 190), size: 96, weight: .heavy, color: .white)
    text("Click it or press ⌥N. No account. Your data stays on your Mac.", at: NSPoint(x: w / 2, y: h - 270), size: 44, weight: .medium,
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
    text("Live reminders pop out of the notch", at: NSPoint(x: w * 0.36, y: a.minY - 80), size: 36, weight: .semibold,
         color: NSColor.white.withAlphaComponent(0.8))
    var p = place(pill, c, center: w * 0.78, top: rowTop, width: 640)
    p.origin.y = rowTop - 300
    text("Your timer keeps running beside it", at: NSPoint(x: w * 0.78, y: p.minY - 80), size: 36, weight: .semibold,
         color: NSColor.white.withAlphaComponent(0.8))
}
try! grid.write(to: out.appendingPathComponent("notchling-features.png"))
print("wrote", out.path)
