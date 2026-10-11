import AppKit

guard CommandLine.arguments.count == 3,
      let size = Int(CommandLine.arguments[1]) else {
    fputs("Usage: IconMaker <size> <output.png>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
let canvas = CGFloat(size)
let image = NSImage(size: NSSize(width: canvas, height: canvas))

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(3) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let inset = canvas * 0.055
let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let radius = canvas * 0.22
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.57, blue: 0.70, alpha: 1)
])!
gradient.draw(in: path, angle: -45)

NSGraphicsContext.saveGraphicsState()
let highlight = NSBezierPath(ovalIn: CGRect(x: canvas * 0.10, y: canvas * 0.45, width: canvas * 0.80, height: canvas * 0.60))
NSColor.white.withAlphaComponent(0.10).setFill()
highlight.fill()
NSGraphicsContext.restoreGraphicsState()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let font = NSFont.systemFont(ofSize: canvas * 0.54, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -canvas * 0.035
]
let label = "Aa" as NSString
let labelRect = CGRect(x: canvas * 0.07, y: canvas * 0.19, width: canvas * 0.86, height: canvas * 0.62)
label.draw(in: labelRect, withAttributes: attributes)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(4)
}
try png.write(to: output)

