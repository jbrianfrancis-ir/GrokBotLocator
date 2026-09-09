import Foundation
import Testing
@testable import GrokBotLocator

/// Measures the sRGB components DSPalette publishes directly -- WCAG 2.x luminance and the
/// (L1+0.05)/(L2+0.05) contrast ratio are computed here, not trusted from DSPalette, so this
/// proves the shipped colours meet DESIGN.md's floors rather than asserting it in a comment.
@Suite
struct DesignSystemContrastTests {

    /// WCAG 2.x relative luminance of an sRGB colour.
    private static func luminance(_ c: DSRGB) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG contrast ratio between two colours, lighter over darker.
    private static func ratio(_ a: DSRGB, _ b: DSRGB) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        let (hi, lo) = la > lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
    }

    private struct PairCase {
        let name: String
        let pair: DSColorPair
        let minRatio: Double
    }

    private static let cases: [PairCase] = [
        PairCase(name: "body", pair: DSPalette.body, minRatio: 7.0),
        PairCase(name: "secondary", pair: DSPalette.secondary, minRatio: 4.5),
        PairCase(name: "primaryAction", pair: DSPalette.primaryAction, minRatio: 7.0),
        PairCase(name: "success", pair: DSPalette.success, minRatio: 7.0),
        PairCase(name: "failure", pair: DSPalette.failure, minRatio: 7.0),
        PairCase(name: "pending", pair: DSPalette.pending, minRatio: 7.0),
    ]

    /// All twelve pair-appearance combinations against DESIGN.md's floors: body, action
    /// text, success, failure, and pending >= 7:1; secondary >= 4.5:1. Each appearance is
    /// checked independently so a failure names the exact pair, appearance, and ratio.
    @Test
    func allPairsMeetContrastFloors() {
        for c in Self.cases {
            let lightRatio = Self.ratio(c.pair.lightForeground, c.pair.lightBackground)
            #expect(
                lightRatio >= c.minRatio,
                "\(c.name) (light): \(String(format: "%.1f", lightRatio)):1 is below the \(c.minRatio):1 floor"
            )

            let darkRatio = Self.ratio(c.pair.darkForeground, c.pair.darkBackground)
            #expect(
                darkRatio >= c.minRatio,
                "\(c.name) (dark): \(String(format: "%.1f", darkRatio)):1 is below the \(c.minRatio):1 floor"
            )
        }
    }
}
