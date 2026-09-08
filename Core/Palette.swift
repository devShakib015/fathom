import SwiftUI

/// The house palette, shared with the owner's site and with Helm. Kept as hex
/// strings rather than `Color` so that document defaults and SwiftUI chrome
/// are provably the same values.
enum Palette {
    static let backgroundHex = "#060B0A"
    static let surfaceHex    = "#101E1A"
    static let accentHex     = "#3DDC97"
    static let accentAltHex  = "#4FC3E8"
    static let textHex       = "#E8F2EE"
    static let textDimHex    = "#9BB3AB"
    static let hairlineHex   = "#0D1815"

    static let background = ColorSpec(backgroundHex).color
    static let surface    = ColorSpec(surfaceHex).color
    static let accent     = ColorSpec(accentHex).color
    static let accentAlt  = ColorSpec(accentAltHex).color
    static let text       = ColorSpec(textHex).color
    static let textDim    = ColorSpec(textDimHex).color
    static let hairline   = ColorSpec(hairlineHex).color
}
