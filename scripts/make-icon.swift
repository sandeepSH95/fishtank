// Generates the app icon with a random tank inhabitant on a random sea gradient:
//   swift scripts/make-icon.swift <output.png> [emoji]
import AppKit

let inhabitants = ["🐠", "🐟", "🐡", "🦈", "🐙", "🦑", "🪼", "🐳", "🐬", "🦐", "🐢", "🦞", "🐌", "🦀"]
let creature = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : inhabitants.randomElement()!
let hue = CGFloat.random(in: 0.45...0.62)

let size: CGFloat = 1024
let inset: CGFloat = 100
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).addClip()
NSGradient(colors: [
    NSColor(calibratedHue: hue, saturation: 0.9, brightness: 0.3, alpha: 1),
    NSColor(calibratedHue: hue - 0.06, saturation: 0.8, brightness: 0.6, alpha: 1),
])!.draw(in: tile, angle: 90)

let stamp = NSAttributedString(string: creature, attributes: [.font: NSFont.systemFont(ofSize: 500)])
let stampSize = stamp.size()
stamp.draw(at: NSPoint(x: (size - stampSize.width) / 2, y: (size - stampSize.height) / 2))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("icon: \(creature) hue \(String(format: "%.2f", hue))")
