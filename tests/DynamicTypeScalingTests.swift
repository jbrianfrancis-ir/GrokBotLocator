import Testing
import SwiftUI
@testable import GrokBotLocator

/// Proves DSTypography's tokens actually scale under Dynamic Type, and that the
/// measurement itself is capable of failing (a harness that always reports 1.00x would
/// pass silently otherwise). `ImageRenderer` and its `.uiImage` are MainActor-isolated,
/// so the whole suite must be `@MainActor` -- it will not compile otherwise.
@MainActor
@Suite
struct DynamicTypeScalingTests {

    /// Renders `view` at a fixed dynamic type size and returns its rendered height.
    private func height(of view: some View, at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let renderer = ImageRenderer(content: view.dynamicTypeSize(dynamicTypeSize))
        renderer.scale = 1
        return renderer.uiImage?.size.height ?? 0
    }

    @Test(arguments: [DSTextStyle.body, .secondary, .actionLabel, .screenTitle])
    func tokenScalesFromDefaultToAX5(style: DSTextStyle) {
        let defaultHeight = height(of: Text("Ag").dsFont(style), at: .large)
        let ax5Height = height(of: Text("Ag").dsFont(style), at: .accessibility5)

        #expect(defaultHeight > 0)
        #expect(ax5Height / defaultHeight >= 1.5)
    }

    /// Negative control: a fixed-size font over the same measurement. If this also read
    /// >= 1.5, the harness itself would be broken -- unable to tell a scaling token from
    /// a non-scaling one -- and the assertions above would prove nothing.
    @Test
    func fixedSizeControlDoesNotScale() {
        let fixed = Text("Ag").font(.custom("Helvetica", fixedSize: 20))
        let defaultHeight = height(of: fixed, at: .large)
        let ax5Height = height(of: fixed, at: .accessibility5)

        let ratio = ax5Height / defaultHeight
        #expect(abs(ratio - 1.0) < 0.05)
    }
}
