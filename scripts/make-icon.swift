// Draws the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.22, alpha: 1), NSColor(red: 0.93, green: 0.30, blue: 0.36, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // Notch: black tab hanging from the top edge.
    let nw = body.width * 0.5, nh = body.height * 0.2
    let notch = NSBezierPath(roundedRect: NSRect(x: body.midX - nw / 2, y: body.maxY - nh, width: nw, height: nh + s * 0.1),
                             xRadius: nh * 0.5, yRadius: nh * 0.5)
    NSGraphicsContext.current?.cgContext.saveGState()
    bg.addClip()
    NSColor.black.setFill()
    notch.fill()
    NSGraphicsContext.current?.cgContext.restoreGState()
    // Three task lines.
    NSColor.white.withAlphaComponent(0.92).setFill()
    for i in 0..<3 {
        let y = body.minY + body.height * (0.18 + CGFloat(i) * 0.17)
        let dot = NSRect(x: body.minX + body.width * 0.18, y: y, width: body.width * 0.09, height: body.width * 0.09)
        NSBezierPath(ovalIn: dot).fill()
        NSBezierPath(roundedRect: NSRect(x: dot.maxX + body.width * 0.06, y: y + dot.height * 0.25,
                                         width: body.width * (0.5 - CGFloat(i) * 0.08), height: dot.height * 0.5),
                     xRadius: dot.height * 0.25, yRadius: dot.height * 0.25).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
