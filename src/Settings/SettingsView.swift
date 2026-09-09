import SwiftUI

/// The settings screen (01-12): the app's only screen for this phase. A `ScrollView` over a
/// `VStack`, never a `Form` -- AX5 reflows vertically with nothing clipped. Three
/// `CredentialField`s bind straight to `SettingsModel`; the sender key never carries a stored
/// value back into the view (D-10), only `model.hasStoredKey` does. The save action sits in
/// the bottom third for one-handed reach: a `GeometryReader` gives the content a `minHeight`
/// (never a fixed height) so a trailing `Spacer` pushes the outcome/save/clear group down when
/// the screen has room, while AX5's taller content simply scrolls past that minimum. No glass
/// anywhere here -- every fill is an opaque `DSPalette` pair, matching CredentialField and
/// PingButton; navigation chrome is the system's own and needs no code from this file.
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
                            savedIndicator: model.hasStoredKey ? "Key saved" : nil
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

                        Button("Clear") {
                            model.clear()
                        }
                        .dsFont(.body)
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget)
                        .accessibilityLabel("Clear settings")
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
