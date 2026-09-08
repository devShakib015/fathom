import AppKit
import CoreGraphics

// Draws Fathom's app icon and writes an iconset.
//
// The icon is generated rather than committed as a binary nobody can open,
// edit or explain. Run it with:
//
//     swift Tools/MakeIcon.swift && \
//     iconutil -c icns -o App/Resources/Fathom.icns build/Fathom.iconset
//
// **A letterform, deliberately, and not a picture of what the app does.**
// Fathom started as a widget builder and is becoming a tool for customising
// macOS generally — menu bar, island, and more. A mark depicting three widget
// tiles would be wrong the week the second surface ships, the way an icon of a
// floppy disk went wrong. A brand mark survives the product growing; a
// depiction dates with the feature it draws.
//
// The F is built from rounded bars, which is the app's own vocabulary — a bar
// is one of the primitives you compose with — and the crossbar carries the
// second accent so the mark is not one flat colour at a glance.

let background = (top: NSColor(srgbRed: 0.063, green: 0.114, blue: 0.098, alpha: 1),   // #101E1A
                  bottom: NSColor(srgbRed: 0.020, green: 0.035, blue: 0.031, alpha: 1)) // #050908
let accent = NSColor(srgbRed: 0.239, green: 0.863, blue: 0.592, alpha: 1)               // #3DDC97
let accentAlt = NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 1)            // #4FC3E8

/// A superellipse, not a rounded rectangle. macOS icon corners are continuous,
/// and the difference between the two is the difference between an icon that
/// sits among Apple's own and one that looks slightly wrong beside them.
func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = cx + a * pow(abs(cosT), 2 / n) * (cosT < 0 ? -1 : 1)
        let y = cy + b * pow(abs(sinT), 2 / n) * (sinT < 0 ? -1 : 1)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: Int) -> Data? {
    let s = Double(size)
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Apple's grid: the shape occupies about 82% of the canvas, centred, and
    // the rest is the breathing room every other icon has.
    let inset = s * 0.09
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = squircle(in: plate)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [background.top.cgColor, background.bottom.cgColor] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    context.restoreGState()

    // A hairline along the top edge, the way a physical object catches light.
    // Without it the plate reads as a flat hole at large sizes.
    context.saveGState()
    context.addPath(shape)
    context.setLineWidth(s * 0.006)
    context.setStrokeColor(NSColor(white: 1, alpha: 0.14).cgColor)
    context.strokePath()
    context.restoreGState()

    // The F, on its own grid so the proportions are decided rather than
    // eyeballed: a full-height stem, a full-width arm, a shorter crossbar.
    let dense = size > 40
    let stroke = plate.width * (dense ? 0.132 : 0.155)
    let height = plate.height * 0.60
    let width = plate.width * 0.44
    let left = plate.midX - width / 2
    let bottom = plate.midY - height / 2
    let radius = stroke / 2

    func bar(_ rect: CGRect, _ colour: NSColor) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
        context.setFillColor(colour.cgColor)
        context.fillPath()
    }

    bar(CGRect(x: left, y: bottom, width: stroke, height: height), accent)
    bar(CGRect(x: left, y: bottom + height - stroke, width: width, height: stroke), accent)
    // The crossbar sits a touch above the optical centre; placed at the true
    // middle an F always reads as sagging.
    bar(CGRect(x: left, y: bottom + height * 0.50 - stroke / 2,
               width: width * 0.70, height: stroke), accentAlt)

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let out = URL(fileURLWithPath: "build/Fathom.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = drawIcon(size: variant.size) else {
        print("failed at \(variant.name)"); exit(1)
    }
    try data.write(to: out.appendingPathComponent("\(variant.name).png"))
}
print("wrote \(variants.count) sizes to \(out.path)")
