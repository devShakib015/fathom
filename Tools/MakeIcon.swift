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
// The mark is an echo sounding: a pulse at the top and three returns spreading
// downward. Fathoms are measured by sounding, which is where the name comes
// from, and it puts the icon in the same nautical family as Helm's wheel
// without repeating it. It is also the shape of the thing the whole product
// rests on — a signal sent at a fixed interval, coming back.

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

    // The sounding: one pulse, three returns.
    let originX = plate.midX
    let originY = plate.minY + plate.height * 0.775
    // Three returns at large sizes, two at small. Apple simplifies its own
    // icons the same way, and for the same reason: at sixteen points a third
    // arc is not detail, it is mud.
    let dense = size > 40
    let radii: [Double] = dense ? [0.20, 0.325, 0.45] : [0.22, 0.40]
    let opacities: [Double] = dense ? [1.0, 0.62, 0.30] : [1.0, 0.55]
    let weight = dense ? 0.052 : 0.075
    let sweep = 126.0 * .pi / 180

    for (index, factor) in radii.enumerated() {
        let radius = plate.width * factor
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: originX, y: originY),
                    radius: radius,
                    startAngle: -.pi / 2 - sweep / 2,
                    endAngle: -.pi / 2 + sweep / 2,
                    clockwise: false)
        context.addPath(path)
        context.setLineWidth(plate.width * weight)
        context.setLineCap(.round)
        // The nearest return carries the second accent, so the mark is not one
        // flat colour at a glance.
        let colour = index == 0
            ? accent.blended(withFraction: 0.25, of: accentAlt) ?? accent
            : accent
        context.setStrokeColor(colour.withAlphaComponent(opacities[index]).cgColor)
        context.strokePath()
    }

    // The pulse itself.
    let dot = plate.width * (dense ? 0.052 : 0.070)
    context.setFillColor(accent.cgColor)
    context.fillEllipse(in: CGRect(x: originX - dot, y: originY - dot,
                                   width: dot * 2, height: dot * 2))

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
