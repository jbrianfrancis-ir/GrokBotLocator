import SwiftUI

/// The fallback half of DESIGN.md's chrome rule. System navigation bars, tab bars, and sheets
/// pick up the platform's translucent chrome on their own -- no code, no opt-in, nothing to
/// build here for those. This modifier is for a *custom* surface that wants that same chrome
/// feel: a light translucent material normally, replaced by a fully opaque DSPalette fill the
/// moment `accessibilityReduceTransparency` or `colorSchemeContrast` asks for it. Nothing in
/// this phase applies it to a real screen yet -- that is a later phase's work; this plan only
/// proves the fallback itself. Never reach for the opt-in translucency style this modifier
/// exists to avoid: it is barred from body text, credential fields, and the primary action,
/// and every other surface should still prefer this fallback over calling it directly.
struct DSChromeModifier: ViewModifier {
    var fill: DSColorPair = DSPalette.body

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// Either accessibility setting is enough to force the opaque fallback -- DESIGN.md asks
    /// for both to be honoured, not just one.
    private var needsOpaqueFallback: Bool {
        reduceTransparency || contrast == .increased
    }

    func body(content: Content) -> some View {
        content.background {
            if needsOpaqueFallback {
                fill.background(for: colorScheme)
            } else {
                Color.clear.background(.thinMaterial)
            }
        }
    }
}

extension View {
    /// Gives a custom surface DESIGN.md's chrome fallback -- translucent by default, opaque
    /// under Reduce Transparency or Increase Contrast. `fill` picks which DSPalette pair backs
    /// the opaque state; defaults to `DSPalette.body`.
    func dsChrome(fill: DSColorPair = DSPalette.body) -> some View {
        modifier(DSChromeModifier(fill: fill))
    }
}

private struct DSChromePreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Custom chrome surface")
            .dsFont(.body)
            .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
            .padding(DSMetrics.screenMargin)
            .frame(maxWidth: .infinity)
            .dsChrome()
            .clipShape(RoundedRectangle(cornerRadius: DSMetrics.cornerRadius, style: .continuous))
            .padding(DSMetrics.screenMargin)
    }
}

// `accessibilityReduceTransparency`/`colorSchemeContrast` are get-only in EnvironmentValues --
// they mirror the real device setting Xcode's canvas "Environment Overrides" control flips,
// not something a view sets on itself. `_accessibilityReduceTransparency`/`_colorSchemeContrast`
// are that control's own writable keys, exposed the same way for driving a #Preview from code.
#Preview("Reduce Transparency off") {
    DSChromePreviewCard()
        .environment(\._accessibilityReduceTransparency, false)
}

#Preview("Reduce Transparency on") {
    DSChromePreviewCard()
        .environment(\._accessibilityReduceTransparency, true)
}

#Preview("Increase Contrast on") {
    DSChromePreviewCard()
        .environment(\._colorSchemeContrast, .increased)
}
