import AppKit

// Renders the app icon PNGs that `scripts/build-app.sh` turns into Tichit.icns.
// Kept as a target so the icon has exactly one definition: Logo.swift.

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
NSAppearance.current = NSAppearance(named: .aqua)

func write(size: CGFloat, to path: String) {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    Logo.appIcon(size: size).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 64, 128, 256, 512, 1024] as [CGFloat] {
    write(size: size, to: "\(output)/icon_\(Int(size)).png")
}
print("icons written to \(output)")
