import SwiftUI

/// The primary action (DESIGN.md "Primary action"): full-width, at least 88pt tall, a 28pt
/// semibold label, and an opaque fill from DSPalette.primaryAction -- nothing translucent or
/// blurred behind it. The pressed state swaps to a genuinely different fill (foreground and
/// background trade places) rather than dimming, and the in-flight state pairs a spinner with
/// a changed word so state is never carried by motion alone.
struct PingButton: View {
    let title: String
    var inFlightTitle: String = "Pinging…"
    var isInFlight: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        inFlightTitle: String = "Pinging…",
        isInFlight: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.inFlightTitle = inFlightTitle
        self.isInFlight = isInFlight
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSMetrics.spacingBase) {
                if isInFlight {
                    ProgressView()
                        .tint(DSPalette.primaryAction.foreground(for: colorScheme))
                }
                Text(isInFlight ? inFlightTitle : title)
                    .dsFont(.actionLabel)
            }
            .frame(maxWidth: .infinity, minHeight: DSMetrics.primaryActionHeight)
        }
        .buttonStyle(PingButtonStyle(colorScheme: colorScheme))
        .disabled(isInFlight)
        .accessibilityLabel(title)
        .accessibilityValue(isInFlight ? "In progress" : "Ready")
    }
}

/// Gives the pressed state its own fill by trading DSPalette.primaryAction's foreground and
/// background -- a real colour swap, not an opacity dip, so the change stays visible under
/// Increase Contrast and keeps the pair's already-proven contrast ratio (it's symmetric).
private struct PingButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let pair = DSPalette.primaryAction
        let pressed = configuration.isPressed
        let fill = pressed ? pair.foreground(for: colorScheme) : pair.background(for: colorScheme)
        let label = pressed ? pair.background(for: colorScheme) : pair.foreground(for: colorScheme)

        return configuration.label
            .foregroundStyle(label)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: DSMetrics.primaryActionRadius, style: .continuous))
    }
}

private struct PingButtonPreviewStack: View {
    var body: some View {
        VStack(spacing: DSMetrics.groupGap) {
            PingButton(title: "Ping now", action: {})
            PingButton(title: "Ping now", isInFlight: true, action: {})
        }
        .padding(DSMetrics.screenMargin)
    }
}

#Preview("Light — default") {
    PingButtonPreviewStack()
}

#Preview("Dark — default") {
    PingButtonPreviewStack()
        .preferredColorScheme(.dark)
}

#Preview("Light — AX5") {
    PingButtonPreviewStack()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — AX5") {
    PingButtonPreviewStack()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
