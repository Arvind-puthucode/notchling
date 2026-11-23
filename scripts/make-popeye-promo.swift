// Popeye-themed share images.
//   swift scripts/make-popeye-promo.swift <popeye-strip.jpg> <captures-dir> <out-dir>
//
// Art: E. C. Segar, "Thimble Theatre", January 17, 1929 (Popeye's first appearance), via the
// East Liverpool Review scan on Wikimedia Commons. Public domain in the US. Not affiliated with
// or endorsed by King Features. Captures-dir holds shot-mcp.png and shot-alert.png from the real app.
import AppKit

let strip = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!
let caps = URL(fileURLWithPath: CommandLine.arguments[2])
let out = URL(fileURLWithPath: CommandLine.arguments[3])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let spinach = NSColor(red: 0.36, green: 0.72, blue: 0.33, alpha: 1)
let paper = NSColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1)
let sea = NSColor(red: 0.07, green: 0.16, blue: 0.27, alpha: 1)
let credit = "Popeye art: E. C. Segar, Thimble Theatre, Jan 17, 1929 (Popeye's first strip). Public domain in the US. Not affiliated with King Features."

/// Panel crop in strip pixel coordinates (top-left origin), from the 4660×1140 scan.
func panel(_ x0: Int, _ x1: Int) -> CGImage {
    strip.cropping(to: CGRect(x: x0, y: 38, width: x1 - x0, height: 1062))!
}

func shot(_ name: String) -> CGImage {
    let cg = NSImage(contentsOf: caps.appendingPathComponent("shot-\(name).png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = cg.width, h = cg.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
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

func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
          align: NSTextAlignment = .center, width: CGFloat = 3000, font: NSFont? = nil) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineSpacing = size * 0.12
    let f = font ?? NSFont.systemFont(ofSize: size, weight: weight)
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: para, .kern: -size * 0.015])
    let ox: CGFloat = align == .center ? x - width / 2 : x
    // `y` is the bottom of the text block; measure so multi-line text grows upward from it.
    let box = a.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin])
    a.draw(with: NSRect(x: ox, y: y, width: width, height: ceil(box.height)), options: [.usesLineFragmentOrigin])
}

func comicFont(_ size: CGFloat) -> NSFont {
    for name in ["ChalkboardSE-Bold", "MarkerFelt-Wide", "Noteworthy-Bold"] {
        if let f = NSFont(name: name, size: size) { return f }
    }
    return .systemFont(ofSize: size, weight: .heavy)
}

/// Deep-sea background with soft waves and a few rivets, nautical without borrowing anything.
func background(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    NSGradient(colors: [NSColor(red: 0.09, green: 0.21, blue: 0.34, alpha: 1), sea, NSColor(red: 0.03, green: 0.07, blue: 0.13, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
    NSColor.white.withAlphaComponent(0.05).setStroke()
    for row in 0..<6 {
        let p = NSBezierPath()
        p.lineWidth = 6
        let baseY = CGFloat(row) * 90 + 40
        p.move(to: NSPoint(x: 0, y: baseY))
        var x: CGFloat = 0
        while x < w {
            p.curve(to: NSPoint(x: x + 160, y: baseY), controlPoint1: NSPoint(x: x + 40, y: baseY + 26), controlPoint2: NSPoint(x: x + 120, y: baseY + 26))
            x += 160
        }
        p.stroke()
    }
}

/// A comic panel printed on aged paper, slightly rotated, with a drop shadow.
func paperPanel(_ img: CGImage, _ c: CGContext, center: CGPoint, height: CGFloat, angle: CGFloat) -> CGRect {
    let w = height * CGFloat(img.width) / CGFloat(img.height)
    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    c.rotate(by: angle)
    let pad: CGFloat = 26
    let card = CGRect(x: -w / 2 - pad, y: -height / 2 - pad, width: w + pad * 2, height: height + pad * 2)
    c.setShadow(offset: CGSize(width: 0, height: -20), blur: 50, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    paper.setFill()
    NSBezierPath(rect: card).fill()
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.setBlendMode(.multiply) // keeps the newsprint black and lets the paper tone show through
    c.draw(img, in: CGRect(x: -w / 2, y: -height / 2, width: w, height: height))
    c.restoreGState()
    return CGRect(x: center.x - w / 2 - pad, y: center.y - height / 2 - pad, width: w + pad * 2, height: height + pad * 2)
}

func place(_ img: CGImage, _ c: CGContext, centerX: CGFloat, top: CGFloat, width: CGFloat) -> CGRect {
    let h = width * CGFloat(img.height) / CGFloat(img.width)
    let r = CGRect(x: centerX - width / 2, y: top - h, width: width, height: h)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: NSColor.black.withAlphaComponent(0.7).cgColor)
    c.draw(img, in: r)
    c.restoreGState()
    return r
}

/// Screen top edge so the notch reads as "on a Mac".
func screen(_ c: CGContext, centerX: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
    let rect = CGRect(x: centerX - width / 2, y: top - height, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    c.saveGState()
    c.addPath(path)
    c.clip()
    NSGradient(colors: [NSColor(red: 0.62, green: 0.82, blue: 0.93, alpha: 1), NSColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1)])!
        .draw(in: rect, angle: -90)
    NSColor.black.withAlphaComponent(0.5).setFill()
    NSRect(x: rect.minX, y: rect.maxY - 34, width: rect.width, height: 34).fill()
    c.restoreGState()
    c.addPath(path)
    c.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
    c.setLineWidth(3)
    c.strokePath()
}

func arrow(_ from: CGPoint, _ to: CGPoint, color: NSColor) {
    color.setStroke()
    let p = NSBezierPath()
    p.lineWidth = 10
    p.lineCapStyle = .round
    p.move(to: from)
    p.curve(to: to, controlPoint1: CGPoint(x: from.x + 60, y: from.y + 70), controlPoint2: CGPoint(x: to.x - 80, y: to.y + 60))
    p.stroke()
    color.setFill()
    let a = atan2(to.y - (to.y + 60), to.x - (to.x - 80))
    let head = NSBezierPath()
    head.move(to: CGPoint(x: to.x + cos(a) * 30, y: to.y + sin(a) * 30))
    head.line(to: CGPoint(x: to.x + cos(a + 2.4) * 30, y: to.y + sin(a + 2.4) * 30))
    head.line(to: CGPoint(x: to.x + cos(a - 2.4) * 30, y: to.y + sin(a - 2.4) * 30))
    head.close()
    head.fill()
}

func chip(_ s: String, center: CGPoint) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let w = (s as NSString).size(withAttributes: [.font: font]).width + 48
    let r = NSRect(x: center.x - w / 2, y: center.y - 30, width: w, height: 60)
    NSColor.white.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: r, xRadius: 30, yRadius: 30).fill()
    text(s, x: center.x, y: center.y - 22, size: 30, weight: .semibold, color: NSColor.white.withAlphaComponent(0.9), width: w)
    return w
}

let orders = panel(3110, 4630)   // "YAS-YOU! You're the whole crew…"
let cowboy = panel(1560, 2335)   // "'Ja think I'm a cowboy?"
let notch = shot("mcp")
let alert = shot("alert")

// MARK: 1. The to-do list story

let story = canvas(3200, 1800) { c, w, h in
    background(c, w, h)
    text("Popeye's first day came with a to-do list.", x: w / 2, y: h - 200, size: 100, weight: .heavy)
    text("Thimble Theatre, January 17, 1929. He needed a notch app.", x: w / 2, y: h - 285, size: 46, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.65))

    let p = paperPanel(orders, c, center: CGPoint(x: 790, y: 860), height: 900, angle: 0.025)
    arrow(CGPoint(x: p.maxX + 20, y: 900), CGPoint(x: 1735, y: 900), color: spinach)
    text("“Claude,\nput those in\nmy notch”", x: (p.maxX + 1760) / 2, y: 960, size: 36, color: spinach, width: 320, font: comicFont(36))

    let panelW: CGFloat = 1300
    let ph = panelW * CGFloat(notch.height) / CGFloat(notch.width)
    screen(c, centerX: 2470, top: 1380, width: 1400, height: ph + 120)
    _ = place(notch, c, centerX: 2470, top: 1380, width: panelW)
    text("All six orders, timed, with “Go to helm” starred and a focus timer running.", x: 2470, y: 1380 - ph - 230, size: 34,
         weight: .medium, color: NSColor.white.withAlphaComponent(0.75), width: 1400)

    text("Notchling · free & open source · github.com/Arvind-puthucode/notchling", x: w / 2, y: 150, size: 40, weight: .bold, color: .white)
    text(credit, x: w / 2, y: 70, size: 24, color: NSColor.white.withAlphaComponent(0.45))
}
try! story.write(to: out.appendingPathComponent("popeye-todo.png"))

// MARK: 2. Hero: "'Ja think I'm a cowboy?"

let hero = canvas(3200, 1800) { c, w, h in
    background(c, w, h)
    _ = paperPanel(cowboy, c, center: CGPoint(x: 760, y: 920), height: 1250, angle: -0.03)

    // Answer bubble.
    let bubble = NSRect(x: 1360, y: 1180, width: 1640, height: 380)
    paper.setFill()
    let bp = NSBezierPath(roundedRect: bubble, xRadius: 190, yRadius: 190)
    bp.move(to: NSPoint(x: bubble.minX + 140, y: bubble.minY + 40))
    bp.line(to: NSPoint(x: bubble.minX - 90, y: bubble.minY - 40))
    bp.line(to: NSPoint(x: bubble.minX + 260, y: bubble.minY + 10))
    bp.fill()
    NSColor.black.setStroke()
    bp.lineWidth = 7
    bp.stroke()
    text("NAH. YOU'RE A SAILOR\nWITH A NOTCH APP.", x: bubble.midX, y: bubble.minY + 70, size: 92, color: .black, width: 1500,
         font: comicFont(92))

    text("Notchling", x: 2180, y: 900, size: 150, weight: .heavy)
    text("Tasks, notes, focus and your calendar, right in your Mac's notch.", x: 2180, y: 820, size: 44, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.7), width: 1700)

    _ = place(alert, c, centerX: 2180, top: 760, width: 1150)

    let chips = ["Free", "Open source · MIT", "macOS 14+", "MCP for AI agents"]
    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let widths = chips.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 48 }
    var x = 2180 - (widths.reduce(0, +) + 30 * CGFloat(chips.count - 1)) / 2
    for (s, cw) in zip(chips, widths) {
        _ = chip(s, center: CGPoint(x: x + cw / 2, y: 330))
        x += cw + 30
    }
    text("github.com/Arvind-puthucode/notchling", x: 2180, y: 210, size: 40, weight: .bold, color: spinach)
    text(credit, x: w / 2, y: 70, size: 24, color: NSColor.white.withAlphaComponent(0.45))
}
try! hero.write(to: out.appendingPathComponent("popeye-hero.png"))
print("wrote", out.path)
