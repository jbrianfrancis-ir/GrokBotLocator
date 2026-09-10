import SwiftUI

/// The settings screen (01-12): the app's only screen for this phase. A `ScrollView` over a
/// `VStack`, never a `Form` -- AX5 reflows vertically with nothing clipped. Three
/// `CredentialField`s bind straight to `SettingsModel`; the sender key never carries a stored
/// value back into the view (D-10), only `model.hasStoredKey` does. The save action sits in
/// the bottom third for one-handed reach: a `GeometryReader` gives the content a `minHeight`
/// (never a fixed height) so a trailing `Spacer` pushes the outcome/save/clear/test group down
/// when the screen has room, while AX5's taller content simply scrolls past that minimum. No
/// glass anywhere here -- every fill is an opaque `DSPalette` pair, matching CredentialField
/// and PingButton; navigation chrome is the system's own and needs no code from this file.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                    Text("Settings")
                        .dsFont(.screenTitle)
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                        CredentialField(
                            label: "Webhook URL",
                            text: $model.urlText,
                            footnote: "Where pings are sent. Must start with https://."
                        )
                        .keyboardType(.URL)

                        CredentialField(
                            label: "Sender key",
                            text: $model.senderKey,
                            isSecure: true,
                            savedIndicator: model.hasStoredKey ? "Key saved" : nil,
                            footnote:
                                "Type the whole header value the routine expects, for example Bearer abc123 — it is sent exactly as typed."
                        )

                        CredentialField(
                            label: "Header name",
                            text: $model.headerName,
                            footnote:
                                "The header the sender key rides in. Defaults to \(WebhookCredentials.defaultHeaderName)."
                        )
                    }

                    Spacer(minLength: DSMetrics.groupGap)

                    VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                        statusView

                        PingButton(title: "Save settings") {
                            model.save()
                        }

                        // The 60pt frame and the content shape live INSIDE the label, as in
                        // PingButton: a `.frame` applied to the Button from outside enlarges the
                        // layout slot but leaves the extra area non-hittable, so the real target
                        // stays the width of the word. `.contentShape` makes the whole frame take
                        // the tap. An Accessibility Inspector audit cannot catch the outside form
                        // -- it measures the accessibility element, which the outer frame does
                        // enlarge -- so this pattern is the guard, not the audit.
                        Button {
                            model.clear()
                        } label: {
                            Text("Clear")
                                .dsFont(.body)
                                .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                        .accessibilityLabel("Clear settings")

                        // Same inside-the-label frame and content shape as Clear, for the reason
                        // the comment above gives. The word changes while the test is in flight:
                        // a disabled button whose label never moves reads as a dead control.
                        Button {
                            Task { await model.testConnection() }
                        } label: {
                            Text(model.isTesting ? "Testing…" : "Test connection")
                                .dsFont(.body)
                                .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                        .accessibilityLabel("Test connection")
                        .disabled(model.isTesting)

                        connectionReportView
                    }
                }
                .padding(DSMetrics.screenMargin)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .task { model.load() }
    }

    /// Symbol + word/sentence + colour, on its own opaque fill -- never colour alone, never a
    /// toast or alert. `.idle` renders nothing: the field group is the whole screen until a
    /// save or clear happens.
    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .saved:
            statusBadge(symbolName: "checkmark.circle.fill", text: "Saved", pair: DSPalette.success)
        case .error(let message):
            statusBadge(symbolName: "exclamationmark.triangle.fill", text: message, pair: DSPalette.failure)
        }
    }

    /// REQ-11: what the webhook itself answered, on screen. The headline goes through the same
    /// symbol + word + colour badge as a save outcome; below it sit the exact status code and
    /// the exact body. Never an `alert` and never a toast (DESIGN.md), and deliberately no
    /// `lineLimit` -- at AX5 a 401's body has to wrap, not clip. Renders nothing until a test
    /// has run. Nothing here reads `model.senderKey` (D-10).
    @ViewBuilder
    private var connectionReportView: some View {
        if let report = model.connectionReport {
            VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                statusBadge(
                    symbolName: report.succeeded
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: report.headline,
                    pair: report.succeeded ? DSPalette.success : DSPalette.failure)

                VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                    if let code = report.statusCode {
                        Text("HTTP \(code)")
                            .dsFont(.secondary)
                    }
                    if let body = report.responseBody {
                        // Verbatim. An empty body is a fact about the response, so it is named
                        // as a rendering note -- never substituted for a value that didn't come.
                        Text(body.isEmpty ? "(empty response body)" : body)
                            .dsFont(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
                // One announcement for the whole answer: VoiceOver reads the code and the body
                // together, the way a sighted user reads the two lines.
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func statusBadge(symbolName: String, text: String, pair: DSColorPair) -> some View {
        HStack(alignment: .top, spacing: DSMetrics.spacingBase) {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.body)
        }
        .foregroundStyle(pair.foreground(for: colorScheme))
        .padding(DSMetrics.spacingBase)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pair.background(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: DSMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An in-memory store for previews only -- never the Keychain, never shared with the app or
/// test targets (their own fakes live in `tests/`).
private final class PreviewCredentialStore: CredentialStore, @unchecked Sendable {
    private var stored: WebhookCredentials?

    init(stored: WebhookCredentials? = nil) {
        self.stored = stored
    }

    func load() throws -> WebhookCredentials? { stored }
    func save(_ credentials: WebhookCredentials) throws { stored = credentials }
    func clear() throws { stored = nil }
}

@MainActor
private func previewModel(hasStoredKey: Bool) -> SettingsModel {
    let store = PreviewCredentialStore(
        stored: hasStoredKey
            ? WebhookCredentials(
                url: URL(string: "https://example.invalid/webhook")!,
                senderKey: "preview-key-not-real.invalid",
                headerName: WebhookCredentials.defaultHeaderName)
            : nil
    )
    let model = SettingsModel(store: store)
    model.load()
    return model
}

#Preview("Light — default") {
    NavigationStack {
        SettingsView(model: previewModel(hasStoredKey: true))
    }
}

#Preview("Dark — default") {
    NavigationStack {
        SettingsView(model: previewModel(hasStoredKey: false))
    }
    .preferredColorScheme(.dark)
}

#Preview("Light — AX5") {
    NavigationStack {
        SettingsView(model: previewModel(hasStoredKey: true))
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — AX5") {
    NavigationStack {
        SettingsView(model: previewModel(hasStoredKey: false))
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility5)
}
