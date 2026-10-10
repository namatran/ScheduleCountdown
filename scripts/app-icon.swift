// Draws the app icon: a cream bell with a blue K on a blue rounded square.
// Usage: swift scripts/app-icon.swift <out.png> <pixels>
// The shapes use a 1024 × 1024 grid; docs/images/bell.svg is the same bell without the square.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let pixels = Int(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: app-icon.swift <out.png> <pixels>\n".utf8))
    exit(1)
}

let blue = CGColor(srgbRed: 0x1C / 255, green: 0x4F / 255, blue: 0xD1 / 255, alpha: 1)
let cream = CGColor(srgbRed: 1, green: 0xFD / 255, blue: 0xF9 / 255, alpha: 1)
let gold = CGColor(srgbRed: 0xFB / 255, green: 0xB8 / 255, blue: 0x30 / 255, alpha: 1)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: pixels, height: pixels)  // One point per pixel, so no 2x metadata.

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
// Draw on the 1024 grid, top-down like the SVG.
let scale = Double(pixels) / 1024
context.translateBy(x: 0, y: Double(pixels))
context.scaleBy(x: scale, y: -scale)

// Rounded square: 100pt margin on a 1024 canvas, like other macOS icons.
context.setFillColor(blue)
context.addPath(CGPath(
    roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
    cornerWidth: 185, cornerHeight: 185, transform: nil))
context.fillPath()

context.translateBy(x: 0, y: -13)  // Centers the bell and clapper together.

// Bell body.
let bell = CGMutablePath()
bell.move(to: CGPoint(x: 512, y: 232))
bell.addCurve(to: CGPoint(x: 322, y: 450), control1: CGPoint(x: 392, y: 232), control2: CGPoint(x: 322, y: 324))
bell.addCurve(to: CGPoint(x: 252, y: 676), control1: CGPoint(x: 322, y: 550), control2: CGPoint(x: 306, y: 610))
bell.addCurve(to: CGPoint(x: 276, y: 716), control1: CGPoint(x: 238, y: 694), control2: CGPoint(x: 250, y: 716))
bell.addLine(to: CGPoint(x: 748, y: 716))
bell.addCurve(to: CGPoint(x: 772, y: 676), control1: CGPoint(x: 774, y: 716), control2: CGPoint(x: 786, y: 694))
bell.addCurve(to: CGPoint(x: 702, y: 450), control1: CGPoint(x: 718, y: 610), control2: CGPoint(x: 702, y: 550))
bell.addCurve(to: CGPoint(x: 512, y: 232), control1: CGPoint(x: 702, y: 324), control2: CGPoint(x: 632, y: 232))
bell.closeSubpath()
context.setFillColor(cream)
context.addPath(bell)
context.fillPath()

// Clapper.
context.setFillColor(gold)
context.fillEllipse(in: CGRect(x: 472, y: 742, width: 80, height: 80))

// K, drawn in the Bearkats logo's own grid and scaled to fit the bell.
let letter: [(Double, Double)] = [
    (444, 341), (916, 341), (916, 527), (863, 527), (863, 709), (1092, 524), (1031, 524), (1031, 341),
    (1536, 341), (1536, 545), (1405, 545), (1215, 695), (1428, 1031), (1534, 1031), (1534, 1240),
    (1033, 1240), (1033, 1043), (1127, 1043), (1017, 855), (848, 985), (848, 1043), (924, 1043),
    (924, 1240), (440, 1240), (440, 1031), (533, 1031), (533, 545), (444, 545),
]
context.saveGState()
context.translateBy(x: 512, y: 480)
context.scaleBy(x: 0.225, y: 0.225)
context.translateBy(x: -988, y: -790)
context.setFillColor(blue)
context.addLines(between: letter.map { CGPoint(x: $0.0, y: $0.1) })
context.closePath()
context.fillPath()
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: arguments[1]))
