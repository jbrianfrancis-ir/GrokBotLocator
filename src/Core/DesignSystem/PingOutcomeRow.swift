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
    /// Why a `.failed` row failed, as a finished sentence. Defaulted, so a `.sent` row -- which
    /// never has one -- and every existing call site keep their shorter initialiser.
    var reason: String? = nil
    /// What produced this ping (REQ-07), or `nil` when not recorded -- a row hydrated from the
    /// offline queue carries no trigger, and renders no trigger line at all rather than
    /// claiming "Manual". Defaulted, so every existing call site keeps its shorter initialiser.
    var trigger: PingTrigger? = nil

    @Environment(\.colorScheme) private var colorScheme

    private static let timestampStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    private var coordinateText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
            outcomeBadge

            if let trigger {
                triggerLine(trigger)
            }

            // Body size, not `.secondary`: DESIGN.md requires a failure to say what happened and
            // what to do next in body-size text on screen, and `.secondary` would put a failure
            // reason on the 17pt floor meant for coordinates and timestamps. Nothing in this
            // file caps a line count, so the sentence wraps to as many lines as AX5 needs.
            if let reason {
                Text(reason)
                    .dsFont(.body)
                    .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
            }

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
        .accessibilityLabel(spokenText)
    }

    /// What VoiceOver reads for the whole row: outcome, the trigger (when recorded), label,
    /// coordinates, and -- when the row carries one -- the reason. The reason has to be in here,
    /// not only in the `Text` above: a failure sentence that is drawn but not spoken is
    /// visual-only, which is exactly what DESIGN.md's "errors state what happened and what to do
    /// next" rules out. The trigger is spoken right after the outcome for the same reason: drawn
    /// only is not enough (DESIGN.md).
    private var spokenText: String {
        let outcomePart: String
        if let trigger {
            outcomePart = "\(outcome.word), \(trigger.word): \(label)"
        } else {
            outcomePart = "\(outcome.word): \(label)"
        }
        var parts = [outcomePart, coordinateText]
        if let reason { parts.append(reason) }
        return parts.joined(separator: ". ")
    }

    /// Symbol + word together, never one alone (DESIGN.md), sized off the secondary token and
    /// placed directly under the outcome badge and above the reason.
    private func triggerLine(_ trigger: PingTrigger) -> some View {
        HStack(spacing: DSMetrics.spacingBase) {
            Image(systemName: trigger.symbolName)
                .accessibilityHidden(true)
            Text(trigger.word)
                .dsFont(.secondary)
        }
        .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
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

/// A real webhook rejection, not a placeholder word: the same sentence `PingClassifier` hands a
/// 401, long enough that the AX5 previews below show it wrapping rather than a short line that
/// would have fitted anyway.
private let previewFailureReason =
    "Rejected by the webhook (HTTP 401). Check the sender key and header name in Settings."

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
                    outcome: .queued,
                    trigger: .arrival
                )
                PingOutcomeRow(
                    timestamp: Date(timeIntervalSince1970: 1_700_001_200),
                    latitude: 40.77465,
                    longitude: 17.23107,
                    label: "Manual ping",
                    outcome: .failed,
                    reason: previewFailureReason
                )
            }
            .padding(DSMetrics.screenMargin)
        }
    }
}

/// Just the two rows that have to reflow -- a `.queued` badge and a `.failed` row carrying its
/// reason -- so the AX5 previews below show the wrap without scrolling past a `.sent` row first.
private struct PingOutcomeReasonPreviewStack: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
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
                    outcome: .failed,
                    reason: previewFailureReason
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

#Preview("Reason — Light, AX5") {
    PingOutcomeReasonPreviewStack()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Reason — Dark, AX5") {
    PingOutcomeReasonPreviewStack()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
