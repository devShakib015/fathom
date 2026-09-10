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
    /// Separators, lifted from #0D1815.
    ///
    /// Measured at 1.09:1 against the background — close enough to invisible
    /// that the panels had no structure at all. Not a WCAG failure, since a
    /// divider is decoration rather than text or a control, but a separator
    /// nobody can see is not separating anything. 1.50:1 is still quiet and is
    /// actually there.
    ///
    /// Everything that carries meaning already passes AA comfortably: body text
    /// 15.0:1 on surface, dim text 7.7:1, the accent 9.7:1 against a 3:1 bar.
    static let hairlineHex   = "#243330"

    static let background = ColorSpec(backgroundHex).color
    static let surface    = ColorSpec(surfaceHex).color
    static let accent     = ColorSpec(accentHex).color
    static let accentAlt  = ColorSpec(accentAltHex).color
    static let text       = ColorSpec(textHex).color
    static let textDim    = ColorSpec(textDimHex).color
    static let hairline   = ColorSpec(hairlineHex).color
}
