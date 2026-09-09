import Foundation

extension Double {
    /// This number as an `Int`, without the possibility of a crash.
    ///
    /// `Int(someDouble)` is a *trapping* conversion: NaN, an infinity, or a
    /// magnitude beyond `Int`'s range terminates the process. Not throws —
    /// terminates. Confirmed on this machine: converting a NaN exits with
    /// SIGTRAP.
    ///
    /// Every value in a widget arrives either from an endpoint or from an
    /// expression in a document, and documents are made to be shared. So both
    /// halves of that are reachable by someone other than the person running
    /// Fathom: an endpoint can send `1e30`, and `pow(-1, 0.5)` is NaN.
    ///
    /// Clamped at 2^53, the largest integer a `Double` represents exactly,
    /// which is far inside `Int`'s range and far outside anything a widget
    /// means. Nothing here is a number a design displays; these are counts,
    /// indices and digit places.
    var asInt: Int {
        let limit = 9_007_199_254_740_992.0
        // NaN has no magnitude to clamp towards, so it becomes zero. An
        // infinity does: `left(text, infinity)` means all of it, and answering
        // zero there would be a silent wrong answer rather than a safe one.
        if isNaN { return 0 }
        if self >= limit { return Int(limit) }
        if self <= -limit { return Int(-limit) }
        return Int(self)
    }
}
