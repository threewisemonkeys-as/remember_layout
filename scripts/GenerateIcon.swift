import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 205, yRadius: 205)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 35; shadow.shadowOffset = NSSize(width: 0, height: -15); shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.61, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.37, alpha: 1))!.draw(in: tile, angle: -65)
    shadow.shadowColor = .clear; shadow.set()
    let screen = NSBezierPath(roundedRect: NSRect(x: 212, y: 303, width: 600, height: 428), xRadius: 44, yRadius: 44)
    NSColor.white.withAlphaComponent(0.92).setStroke(); screen.lineWidth = 26; screen.stroke()
    let left = NSBezierPath(roundedRect: NSRect(x: 253, y: 345, width: 238, height: 344), xRadius: 16, yRadius: 16)
    NSColor.white.withAlphaComponent(0.92).setFill(); left.fill()
    let right = NSBezierPath(roundedRect: NSRect(x: 516, y: 345, width: 254, height: 344), xRadius: 16, yRadius: 16)
    NSColor(calibratedRed: 0.72, green: 0.91, blue: 0.82, alpha: 1).setFill(); right.fill()
    let stand = NSBezierPath(roundedRect: NSRect(x: 445, y: 244, width: 134, height: 23), xRadius: 11, yRadius: 11)
    NSColor.white.withAlphaComponent(0.92).setFill(); stand.fill()
    let neck = NSBezierPath(rect: NSRect(x: 500, y: 264, width: 24, height: 39)); neck.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        try render(pixels: points * density).write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

// Write the documented, big-endian icon family container directly. This also
// works in build environments where IconServices cannot access a GUI session.
func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

if CommandLine.arguments.count > 2 {
    var elements = Data()
    for (type, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                           ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                           ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
        let png = render(pixels: pixels)
        elements.append(Data(type.utf8))
        elements.append(bigEndian(UInt32(png.count + 8)))
        elements.append(png)
    }
    var icon = Data("icns".utf8)
    icon.append(bigEndian(UInt32(elements.count + 8)))
    icon.append(elements)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
