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

    /// Relative-order tripwire, PR #1 follow-up: pins how the four tokens render next to
    /// each other so a later curve or size change in DSTypography fails this gate instead
    /// of drifting unnoticed. `.large` is Dynamic Type's default, unscaled category, so
    /// `@ScaledMetric` applies no curve-specific factor here -- every token reads its base
    /// DESIGN.md size (17/20/28/34) and the rendered order follows directly from that.
    @Test
    func tokenOrderAtDefaultSize() {
        let secondary = height(of: Text("Ag").dsFont(.secondary), at: .large)
        let body = height(of: Text("Ag").dsFont(.body), at: .large)
        let actionLabel = height(of: Text("Ag").dsFont(.actionLabel), at: .large)
        let screenTitle = height(of: Text("Ag").dsFont(.screenTitle), at: .large)

        #expect(secondary < body, "secondary (\(secondary)) should render smaller than body (\(body)) at .large")
        #expect(body < actionLabel, "body (\(body)) should render smaller than actionLabel (\(actionLabel)) at .large")
        #expect(actionLabel < screenTitle, "actionLabel (\(actionLabel)) should render smaller than screenTitle (\(screenTitle)) at .large")
    }

    /// Measured 2026-09-10 at .accessibility5 via this suite's `height(of:at:)` harness:
    /// secondary 59.0, body 67.0, screenTitle 70.0, actionLabel 79.0 (points). These
    /// expectations describe that status quo deliberately -- this is a tripwire, so a later
    /// curve or size change fails here rather than drifting unnoticed -- and the
    /// `actionLabel` > `screenTitle` inversion they encode is accepted shipped behavior per
    /// the 2026-09-10 15:30 decision, not an open defect.
    @Test
    func tokenOrderAtAX5IsPinned() {
        let secondary = height(of: Text("Ag").dsFont(.secondary), at: .accessibility5)
        let body = height(of: Text("Ag").dsFont(.body), at: .accessibility5)
        let screenTitle = height(of: Text("Ag").dsFont(.screenTitle), at: .accessibility5)
        let actionLabel = height(of: Text("Ag").dsFont(.actionLabel), at: .accessibility5)

        #expect(secondary < body, "secondary (\(secondary)) should render smaller than body (\(body)) at .accessibility5")
        #expect(body < screenTitle, "body (\(body)) should render smaller than screenTitle (\(screenTitle)) at .accessibility5")
        #expect(screenTitle < actionLabel, "screenTitle (\(screenTitle)) should render smaller than actionLabel (\(actionLabel)) at .accessibility5 -- the accepted inversion, not a bug")
    }

    /// Surfaces the numbers behind the two pinned-order tests in the smoke log, not only in
    /// a comment. `print`, not `Issue.record`: recording an issue in Swift Testing fails
    /// the test, and ARCHITECTURE's no-logging rule and smoke.sh's guard both scope to
    /// `src/`, so a `print` in a test file is fine.
    @Test
    func tokenHeightsAtBothSizes() {
        let largeSecondary = height(of: Text("Ag").dsFont(.secondary), at: .large)
        let largeBody = height(of: Text("Ag").dsFont(.body), at: .large)
        let largeActionLabel = height(of: Text("Ag").dsFont(.actionLabel), at: .large)
        let largeScreenTitle = height(of: Text("Ag").dsFont(.screenTitle), at: .large)
        let ax5Secondary = height(of: Text("Ag").dsFont(.secondary), at: .accessibility5)
        let ax5Body = height(of: Text("Ag").dsFont(.body), at: .accessibility5)
        let ax5ActionLabel = height(of: Text("Ag").dsFont(.actionLabel), at: .accessibility5)
        let ax5ScreenTitle = height(of: Text("Ag").dsFont(.screenTitle), at: .accessibility5)

        #expect(largeSecondary > 0)
        #expect(largeBody > 0)
        #expect(largeActionLabel > 0)
        #expect(largeScreenTitle > 0)
        #expect(ax5Secondary > 0)
        #expect(ax5Body > 0)
        #expect(ax5ActionLabel > 0)
        #expect(ax5ScreenTitle > 0)

        print("token heights — large: secondary \(largeSecondary) body \(largeBody) actionLabel \(largeActionLabel) screenTitle \(largeScreenTitle); AX5: secondary \(ax5Secondary) body \(ax5Body) actionLabel \(ax5ActionLabel) screenTitle \(ax5ScreenTitle)")
    }
}
