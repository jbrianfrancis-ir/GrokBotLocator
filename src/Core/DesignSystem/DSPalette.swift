import SwiftUI

/// A colour as sRGB components in 0...1 -- readable by tests directly, not hidden inside an
/// opaque `Color`. DesignSystemContrastTests measures these numbers, not a `Color` it has to
/// reverse-engineer, so the test proves the shipped values rather than trusting DSPalette.
struct DSRGB {
    let r: Double
    let g: Double
    let b: Double

    /// `hex` is a 24-bit RGB literal, e.g. "#1A1A1A". No alpha.
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// One foreground-on-background pair, with an explicit light and dark value for each side.
struct DSColorPair {
    let lightForeground: DSRGB
    let lightBackground: DSRGB
    let darkForeground: DSRGB
    let darkBackground: DSRGB

    /// Resolves by ColorScheme -- the only way a view should pull a token's `Color`.
    func foreground(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? darkForeground : lightForeground).color
    }

    func background(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? darkBackground : lightBackground).color
    }
}

/// DESIGN.md's entire colour vocabulary -- six foreground-on-background pairs, each proven
/// against the contrast floors by DesignSystemContrastTests. No state, no view code: a later
/// plan needing another colour adds a pair here, proven by the same test.
enum DSPalette {
    static let body = DSColorPair(
        lightForeground: DSRGB(hex: "#1A1A1A"), lightBackground: DSRGB(hex: "#FFFFFF"),
        darkForeground: DSRGB(hex: "#F2F2F2"), darkBackground: DSRGB(hex: "#000000")
    )
    static let secondary = DSColorPair(
        lightForeground: DSRGB(hex: "#4A4A4A"), lightBackground: DSRGB(hex: "#FFFFFF"),
        darkForeground: DSRGB(hex: "#B0B0B0"), darkBackground: DSRGB(hex: "#000000")
    )
    static let primaryAction = DSColorPair(
        lightForeground: DSRGB(hex: "#FFFFFF"), lightBackground: DSRGB(hex: "#0A3D91"),
        darkForeground: DSRGB(hex: "#000000"), darkBackground: DSRGB(hex: "#7FB3FF")
    )
    static let success = DSColorPair(
        lightForeground: DSRGB(hex: "#FFFFFF"), lightBackground: DSRGB(hex: "#1B5E20"),
        darkForeground: DSRGB(hex: "#000000"), darkBackground: DSRGB(hex: "#7BE38A")
    )
    static let failure = DSColorPair(
        lightForeground: DSRGB(hex: "#FFFFFF"), lightBackground: DSRGB(hex: "#8E0000"),
        darkForeground: DSRGB(hex: "#000000"), darkBackground: DSRGB(hex: "#FF9A94")
    )
    static let pending = DSColorPair(
        lightForeground: DSRGB(hex: "#FFFFFF"), lightBackground: DSRGB(hex: "#6B4A00"),
        darkForeground: DSRGB(hex: "#000000"), darkBackground: DSRGB(hex: "#FFC95C")
    )
}
