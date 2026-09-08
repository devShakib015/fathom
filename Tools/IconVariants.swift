import AppKit
import CoreGraphics

// Three balances for the widget-layout mark. Same grid, same shapes; only which
// tile carries the weight changes.

let bgTop = NSColor(srgbRed: 0.063, green: 0.114, blue: 0.098, alpha: 1)
let bgBottom = NSColor(srgbRed: 0.020, green: 0.035, blue: 0.031, alpha: 1)
let accent = NSColor(srgbRed: 0.239, green: 0.863, blue: 0.592, alpha: 1)
let accentAlt = NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 1)

func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for step in 0...720 {
        let t = Double(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        path.addLine(to: CGPoint(x: cx + a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1),
                                 y: cy + b * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)))
        if step == 0 { path.move(to: CGPoint(x: cx + a, y: cy)) }
    }
    path.closeSubpath()
    return path
}

func tile(_ ctx: CGContext, _ rect: CGRect, radius: Double,
          fill: NSColor, gradientTo: NSColor? = nil) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let gradientTo {
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [fill.cgColor, gradientTo.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        ctx.restoreGState()
    } else {
        ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath()
    }
}

enum Balance: Int, CaseIterable {
    case heroLarge, heroSmall, evenTint
    var name: String {
        switch self {
        case .heroLarge: "1 — weight at the bottom"
        case .heroSmall: "2 — weight at the top-left"
        case .evenTint: "3 — even, one tint apart"
        }
    }
}

/// The three widget sizes on one 3×3 grid: a small square and a wide tile above,
/// a large tile below. The arrangement is the product's own vocabulary, which is
/// why it needs no explaining.
func drawLayout(_ ctx: CGContext, plate: CGRect, balance: Balance, small: Bool) {
    let w = plate.width
    let unit = w * 0.205
    let gap = w * (small ? 0.075 : 0.058)
    let total = unit * 3 + gap * 2
    let left = plate.midX - total / 2
    let top = plate.midY + total / 2
    let radius = unit * (small ? 0.30 : 0.26)

    let smallRect = CGRect(x: left, y: top - unit, width: unit, height: unit)
    let wideRect = CGRect(x: left + unit + gap, y: top - unit, width: unit * 2 + gap, height: unit)
    let largeRect = CGRect(x: left, y: top - total, width: total, height: unit * 2 + gap)

    // Dim tiles have to stay legible at sixteen points, where a 30% tint
    // disappears into the plate entirely.
    let quiet = accent.withAlphaComponent(small ? 0.55 : 0.34)

    switch balance {
    case .heroLarge:
        tile(ctx, smallRect, radius: radius, fill: quiet)
        tile(ctx, wideRect, radius: radius, fill: quiet)
        tile(ctx, largeRect, radius: radius, fill: accent, gradientTo: accentAlt)
    case .heroSmall:
        tile(ctx, smallRect, radius: radius, fill: accent, gradientTo: accentAlt)
        tile(ctx, wideRect, radius: radius, fill: quiet)
        tile(ctx, largeRect, radius: radius, fill: quiet)
    case .evenTint:
        tile(ctx, smallRect, radius: radius, fill: accent)
        tile(ctx, wideRect, radius: radius, fill: accent.withAlphaComponent(0.72))
        tile(ctx, largeRect, radius: radius, fill: accentAlt.withAlphaComponent(0.9))
    }
}

func icon(_ balance: Balance, size: Int) -> CGImage? {
    let s = Double(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    let inset = s * 0.09
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = squircle(in: plate)

    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                       colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: plate.midX, y: plate.maxY),
                           end: CGPoint(x: plate.midX, y: plate.minY), options: [])
    ctx.restoreGState()

    ctx.saveGState(); ctx.addPath(shape)
    ctx.setLineWidth(s * 0.006); ctx.setStrokeColor(NSColor(white: 1, alpha: 0.14).cgColor)
    ctx.strokePath(); ctx.restoreGState()

    drawLayout(ctx, plate: plate, balance: balance, small: size <= 40)
    return ctx.makeImage()
}

let cell = 430.0, pad = 36.0
let sheetW = Int(cell * 3 + pad), sheetH = Int(cell * 0.98 + pad)
guard let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
sheet.setFillColor(NSColor(white: 0.09, alpha: 1).cgColor)
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

for (index, balance) in Balance.allCases.enumerated() {
    let x = pad / 2 + Double(index) * cell
    let y = pad / 2
    if let big = icon(balance, size: 620) {
        sheet.draw(big, in: CGRect(x: x, y: y + 60, width: 290, height: 290))
    }
    if let tiny = icon(balance, size: 32) {
        sheet.interpolationQuality = .none
        sheet.draw(tiny, in: CGRect(x: x + 300, y: y + 250, width: 96, height: 96))
        sheet.interpolationQuality = .high
        sheet.draw(tiny, in: CGRect(x: x + 300, y: y + 200, width: 32, height: 32))
    }
    let label = NSAttributedString(string: balance.name, attributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .medium),
        .foregroundColor: NSColor(white: 0.75, alpha: 1)])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
    label.draw(at: NSPoint(x: x + 6, y: y + 20))
    NSGraphicsContext.restoreGraphicsState()
}

if let image = sheet.makeImage() {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/icon-balance.png"))
    print("wrote build/icon-balance.png")
}
