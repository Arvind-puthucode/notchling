// Draws the DMG window background: swift scripts/make-dmg-background.swift <out.png> <scale>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let scale = CGFloat(Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1") ?? 1)
let size = NSSize(width: 640, height: 400)
let px = NSSize(width: size.width * scale, height: size.height * scale)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(white: 0.99, alpha: 1), NSColor(white: 0.93, alpha: 1)])!.draw(in: bounds, angle: -90)

// Notch hint at the top.
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 90, y: size.height - 26, width: 180, height: 40), xRadius: 14, yRadius: 14).fill()

func text(_ s: String, _ y: CGFloat, _ font: NSFont, _ color: NSColor) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    attr.draw(in: NSRect(x: 0, y: y, width: size.width, height: font.pointSize * 1.5))
}
text("Drag Notchling into Applications", 322, .systemFont(ofSize: 20, weight: .semibold), NSColor(white: 0.1, alpha: 1))
text("Then open it from Applications or Launchpad", 300, .systemFont(ofSize: 12, weight: .regular), NSColor(white: 0, alpha: 0.45))

// Arrow between the two icon slots (icons sit at x=170 and x=470, y=190 from the top).
let accent = NSColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1)
accent.setStroke()
accent.setFill()
let y = size.height - 190
let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 262, y: y))
shaft.line(to: NSPoint(x: 366, y: y))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 382, y: y))
head.line(to: NSPoint(x: 362, y: y + 13))
head.line(to: NSPoint(x: 362, y: y - 13))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
