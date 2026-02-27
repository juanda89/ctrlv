import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "dmg-background.png"
let canvasSize = NSSize(width: 680, height: 430)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

let image = NSImage(size: canvasSize)
image.lockFocus()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.97, blue: 1.0, alpha: 1.0),
    NSColor(calibratedRed: 0.95, green: 0.99, blue: 0.97, alpha: 1.0)
])
gradient?.draw(in: canvasRect, angle: -20)

let title = "Install ctrl+v"
let subtitle = "Drag ctrlv.app to Applications"
let hint = "Then open it from /Applications"

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
    .paragraphStyle: paragraph
]
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1.0),
    .paragraphStyle: paragraph
]
let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1.0),
    .paragraphStyle: paragraph
]

NSAttributedString(string: title, attributes: titleAttrs)
    .draw(in: NSRect(x: 0, y: 338, width: canvasSize.width, height: 48))
NSAttributedString(string: subtitle, attributes: subtitleAttrs)
    .draw(in: NSRect(x: 0, y: 305, width: canvasSize.width, height: 30))
NSAttributedString(string: hint, attributes: hintAttrs)
    .draw(in: NSRect(x: 0, y: 283, width: canvasSize.width, height: 24))

let lane = NSBezierPath(roundedRect: NSRect(x: 82, y: 80, width: 516, height: 178), xRadius: 20, yRadius: 20)
NSColor.white.withAlphaComponent(0.78).setFill()
lane.fill()
NSColor(calibratedWhite: 0.80, alpha: 0.7).setStroke()
lane.lineWidth = 1.0
lane.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 292, y: 170))
arrow.line(to: NSPoint(x: 388, y: 170))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.22, green: 0.53, blue: 0.98, alpha: 0.85).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 377, y: 182))
arrowHead.line(to: NSPoint(x: 398, y: 170))
arrowHead.line(to: NSPoint(x: 377, y: 158))
arrowHead.close()
NSColor(calibratedRed: 0.22, green: 0.53, blue: 0.98, alpha: 0.85).setFill()
arrowHead.fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let pngData = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to render DMG background image.\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Failed to write DMG background to \(outputPath): \(error)\n", stderr)
    exit(1)
}
