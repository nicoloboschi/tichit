import AppKit

/// What the menu bar icon is telling you right now.
enum Status: Equatable {
    case idle
    case working
    case ready

    var color: NSColor {
        switch self {
        case .idle: return NSColor.secondaryLabelColor
        case .working: return NSColor.systemYellow
        case .ready: return NSColor.systemGreen
        }
    }
}

/// The mark: a speech bubble with a rising underline through it — something said,
/// being corrected. Drawn rather than shipped as a PNG so it stays sharp at any
/// size and can pick up the status colour.
enum Logo {
    /// Menu bar icon. The bubble follows the menu bar's own colour; only the status
    /// dot is tinted, so it reads correctly in both light and dark menu bars.
    static func statusItemImage(_ status: Status) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let bubble = bubblePath(in: NSRect(x: 1, y: 4.5, width: 14, height: 11), cornerRadius: 3.5)
            bubble.lineWidth = 1.4
            NSColor.labelColor.setStroke()
            bubble.stroke()

            // The correction stroke: a check rising out of the bubble.
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: 4.6, y: 9))
            tick.line(to: NSPoint(x: 7, y: 6.6))
            tick.line(to: NSPoint(x: 11.6, y: 12))
            tick.lineWidth = 1.6
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.labelColor.setStroke()
            tick.stroke()

            let dot = NSBezierPath(ovalIn: NSRect(x: 14, y: 11, width: 5, height: 5))
            status.color.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// App icon, drawn at whatever size the .icns pipeline asks for.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let unit = size / 1024

            let background = NSBezierPath(
                roundedRect: rect.insetBy(dx: 40 * unit, dy: 40 * unit),
                xRadius: 200 * unit,
                yRadius: 200 * unit
            )
            let gradient = NSGradient(
                colors: [
                    NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.72, alpha: 1),
                ]
            )
            gradient?.draw(in: background, angle: -90)

            let bubbleRect = NSRect(
                x: 210 * unit, y: 300 * unit, width: 600 * unit, height: 440 * unit
            )
            let bubble = bubblePath(in: bubbleRect, cornerRadius: 120 * unit)
            bubble.lineWidth = 46 * unit
            NSColor.white.setStroke()
            bubble.stroke()

            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: 340 * unit, y: 520 * unit))
            tick.line(to: NSPoint(x: 450 * unit, y: 410 * unit))
            tick.line(to: NSPoint(x: 690 * unit, y: 660 * unit))
            tick.lineWidth = 62 * unit
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
            return true
        }
    }

    /// One closed outline for the whole bubble: a rounded rectangle whose bottom
    /// edge is interrupted by the tail, so stroking it leaves no seam across the
    /// mouth and the inside stays hollow.
    private static func bubblePath(in rect: NSRect, cornerRadius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let tailRight = NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY)
        let tailLeft = NSPoint(x: rect.minX + rect.width * 0.24, y: rect.minY)
        let tip = NSPoint(x: rect.minX + rect.width * 0.14, y: rect.minY - rect.height * 0.34)

        path.move(to: NSPoint(x: rect.minX, y: rect.minY + r))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - r))
        path.appendArc(
            withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: 180, endAngle: 90, clockwise: true
        )
        path.line(to: NSPoint(x: rect.maxX - r, y: rect.maxY))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: 90, endAngle: 0, clockwise: true
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r, startAngle: 0, endAngle: -90, clockwise: true
        )
        // Bottom edge, right to left, detouring through the tail.
        path.line(to: tailRight)
        path.line(to: tip)
        path.line(to: tailLeft)
        path.line(to: NSPoint(x: rect.minX + r, y: rect.minY))
        path.appendArc(
            withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r, startAngle: -90, endAngle: 180, clockwise: true
        )
        path.close()
        path.lineJoinStyle = .round
        return path
    }
}
