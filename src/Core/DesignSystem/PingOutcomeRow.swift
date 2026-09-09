import SwiftUI

/// One ping's result (DESIGN.md "Status"): timestamp, coordinates, a caller-supplied label,
/// and an outcome that is always symbol + word + colour together -- never colour alone. Pure
/// presentation: it stores nothing, fetches nothing, triggers nothing. History -- persisting
/// and listing many of these -- is a later phase.
struct PingOutcomeRow: View {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let label: String
    let outcome: PingOutcome

    @Environment(\.colorScheme) private var colorScheme

    private static let timestampStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    private var coordinateText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
            outcomeBadge

            Text(label)
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))

            Text(coordinateText)
                .dsFont(.secondary)
                .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))

            Text(timestamp.formatted(Self.timestampStyle))
                .dsFont(.secondary)
                .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(outcome.word): \(label)")
    }

    /// Symbol + word on the outcome's own opaque fill -- the pair DesignSystemContrastTests
    /// already proves, not a bare colour dropped on the screen background.
    private var outcomeBadge: some View {
        HStack(spacing: DSMetrics.spacingBase) {
            Image(systemName: outcome.symbolName)
                .accessibilityHidden(true)
            Text(outcome.word)
                .dsFont(.secondary)
        }
        .foregroundStyle(outcome.pair.foreground(for: colorScheme))
        .padding(.horizontal, DSMetrics.spacingBase)
        .padding(.vertical, DSMetrics.spacingBase / 2)
        .background(outcome.pair.background(for: colorScheme))
        .clipShape(Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Each case supplies its symbol, word, and DSPalette colour together -- there is no way to
/// read a colour off a `PingOutcome` without also getting the symbol and word that must always
/// accompany it (DESIGN.md: never convey state by colour alone).
enum PingOutcome {
    case sent
    case queued
    case failed

    var symbolName: String {
        switch self {
        case .sent: return "checkmark.circle.fill"
        case .queued: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var word: String {
        switch self {
        case .sent: return "Sent"
        case .queued: return "Queued"
        case .failed: return "Failed"
        }
    }

    var pair: DSColorPair {
        switch self {
        case .sent: return DSPalette.success
        case .queued: return DSPalette.pending
        case .failed: return DSPalette.failure
        }
    }
}

private struct PingOutcomeRowPreviewStack: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                PingOutcomeRow(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    latitude: 40.77465,
                    longitude: 17.23107,
                    label: "Manual ping",
                    outcome: .sent
                )
                PingOutcomeRow(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_600),
                    latitude: 40.77465,
                    longitude: 17.23107,
                    label: "Automatic ping — left region",
                    outcome: .queued
                )
                PingOutcomeRow(
                    timestamp: Date(timeIntervalSince1970: 1_700_001_200),
                    latitude: 40.77465,
                    longitude: 17.23107,
                    label: "Manual ping",
                    outcome: .failed
                )
            }
            .padding(DSMetrics.screenMargin)
        }
    }
}

#Preview("Light — default") {
    PingOutcomeRowPreviewStack()
}

#Preview("Dark — default") {
    PingOutcomeRowPreviewStack()
        .preferredColorScheme(.dark)
}

#Preview("Light — AX5") {
    PingOutcomeRowPreviewStack()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — AX5") {
    PingOutcomeRowPreviewStack()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
