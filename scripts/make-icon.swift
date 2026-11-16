// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1),
                        NSColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1)])!.draw(in: shape, angle: -90)

    // three AI bands filling a capsule, like the storage bar in the app
    let bar = NSRect(x: rect.minX + rect.width * 0.16, y: rect.midY - rect.height * 0.07,
                     width: rect.width * 0.68, height: rect.height * 0.14)
    let track = NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
    NSColor(white: 1, alpha: 0.14).setFill(); track.fill()
    NSGraphicsContext.current?.saveGraphicsState()
    track.addClip()
    let tints = [NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1),
                 NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
                 NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)]
    var x = bar.minX
    for (i, c) in tints.enumerated() {
        let w = bar.width * [0.22, 0.14, 0.18][i]
        c.setFill(); NSRect(x: x, y: bar.minY, width: w, height: bar.height).fill()
        x += w + bar.height * 0.12
    }
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
