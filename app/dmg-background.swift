import AppKit

// Finder places icons in points; the TIFF includes a Retina representation.
let width: CGFloat = 640
let height: CGFloat = 360
var representations: [NSBitmapImageRep] = []

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context

    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let instruction = NSAttributedString(string: "Drag Zero-K to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    instruction.draw(in: NSRect(x: 0, y: 282, width: width, height: 30))

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 282, y: 181))
    arrow.line(to: NSPoint(x: 356, y: 181))
    arrow.move(to: NSPoint(x: 342, y: 195))
    arrow.line(to: NSPoint(x: 356, y: 181))
    arrow.line(to: NSPoint(x: 342, y: 167))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}
let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
