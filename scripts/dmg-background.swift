// Draws the disk image window's background: an arrow from the app to Applications, plus a hint.
// Usage: swift scripts/dmg-background.swift <out.png> <scale>
// The layout matches the icon positions package.sh gives Finder (660×400 window, 128pt icons).
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <out.png> <scale>\n".utf8))
    exit(1)
}

let size = NSSize(width: 660, height: 400)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size  // Sets the DPI (72 × scale) that tiffutil uses to pair the two sizes.

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// The context already maps points to pixels from rep.size, so draw in points.
let context = NSGraphicsContext.current!.cgContext
// Finder positions are measured from the top, so draw that way too.
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)

NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Arrow between the icons, which Finder centers at (170, 180) and (490, 180).
let arrowY = 172.0
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: arrowY))
arrow.line(to: NSPoint(x: 392, y: arrowY))
arrow.move(to: NSPoint(x: 372, y: arrowY - 18))
arrow.line(to: NSPoint(x: 396, y: arrowY))
arrow.line(to: NSPoint(x: 372, y: arrowY + 18))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.6, green: 0.6, blue: 0.63, alpha: 1).setStroke()
arrow.stroke()

// Text draws upside down in the flipped context, so flip back just for it.
func drawCentered(_ text: String, y: Double, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let textSize = (text as NSString).size(withAttributes: attributes)
    context.saveGState()
    context.translateBy(x: 0, y: y + textSize.height)
    context.scaleBy(x: 1, y: -1)
    (text as NSString).draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 0), withAttributes: attributes)
    context.restoreGState()
}
drawCentered("Drag ScheduleCountdown into Applications", y: 300,
             font: .systemFont(ofSize: 17, weight: .semibold), color: NSColor(white: 0.2, alpha: 1))
drawCentered("Then open it from Applications.", y: 328,
             font: .systemFont(ofSize: 13), color: NSColor(white: 0.45, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[1]))
