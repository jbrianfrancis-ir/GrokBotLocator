import SwiftUI

/// Type tokens from DESIGN.md, reached only through `.dsFont(_:)`.
///
/// A `Font` resolved outside a View's `body` never sees `\.dynamicTypeSize`, so it never
/// scales — `Font.system(size: 20)` stored as a `static let` reads 1.00x at AX5 no matter
/// what the environment says. `@ScaledMetric` only resolves correctly as a View property,
/// which is why the size lives in a `ViewModifier` and not a token table of `Font` values.
/// No `Font` is ever declared `static` in this file.
enum DSTextStyle {
    case body
    case secondary
    case actionLabel
    case screenTitle

    var size: CGFloat {
        switch self {
        case .body: return 20
        case .secondary: return 17
        case .actionLabel: return 28
        case .screenTitle: return 34
        }
    }

    var weight: Font.Weight {
        switch self {
        case .body: return .regular
        case .secondary: return .regular
        case .actionLabel: return .semibold
        case .screenTitle: return .bold
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .body: return .body
        case .secondary: return .callout
        case .actionLabel: return .title2
        case .screenTitle: return .largeTitle
        }
    }
}

/// Resolves the scaled size inside the View body, where `\.dynamicTypeSize` is visible.
private struct DSFontModifier: ViewModifier {
    let style: DSTextStyle
    @ScaledMetric private var scaled: CGFloat

    init(style: DSTextStyle) {
        self.style = style
        _scaled = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaled, weight: style.weight))
    }
}

extension View {
    /// Applies a DESIGN.md type token. This is the only supported way to put a token font
    /// on a view — never construct a `Font` from a raw size literal at a call site.
    func dsFont(_ s: DSTextStyle) -> some View {
        modifier(DSFontModifier(style: s))
    }
}
