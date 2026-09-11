import SwiftUI

/// The settings screen (01-12): the app's only screen for this phase. A `ScrollView` over a
/// `VStack`, never a `Form` -- AX5 reflows vertically with nothing clipped. Three
/// `CredentialField`s bind straight to `SettingsModel`; the sender key never carries a stored
/// value back into the view (D-10), only `model.hasStoredKey` does.
///
/// The save action is a pinned `safeAreaInset(edge: .bottom)`, the same shape `PingHomeView`
/// uses for "I'm here". It was a trailing `Spacer` inside the scroll until 2026-09-10: because
/// `statusView` sat in that same stack, a save INSERTED the "Saved" badge into the flow, grew
/// the content past the screen, and pushed "Save settings" below the fold -- the feedback for
/// an action displacing the action, at the one moment the user was looking for it. Pinned, the
/// badge grows upward and the button cannot move. `connectionReportView` stays in the scroll
/// deliberately: it renders a whole 401 body, and PingHomeView's actionBar comment gives the
/// reason -- a wrapped sentence in the bottom bar eats the budget the 88pt action floor needs
/// at AX5. Only the one-word `savedBadge` shares the bar; `errorView` was split out of it at PR
/// review, because a validation sentence at AX5 runs the bar past the height of a small phone.
///
/// No glass anywhere here -- every fill is an opaque `DSPalette` pair, matching CredentialField
/// and PingButton; navigation chrome is the system's own and needs no code from this file.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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

                errorView

                automaticPingsSection

                VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
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
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .task {
            model.load()
            await model.loadTriggers()
        }
    }

    /// REQ-09/REQ-10: three independent switches, the shared interval, and (when there is one)
    /// the sentence explaining what the current authorization does not allow. Sits between the
    /// credential errors and the Clear/Test group, in its own `DSMetrics.groupGap`-spaced
    /// section like the credential fields above it.
    ///
    /// Every switch and the stepper route through a `Binding` whose setter fires a `Task`
    /// calling the matching `SettingsModel` method -- the model moves the value locally before
    /// awaiting the coordinator, so the control itself never waits on CoreLocation. The interval
    /// control's `in:` range is how REQ-09's floor is expressed here: the Stepper cannot reach a
    /// value below `PingRateLimiter.hardFloor`, so there is no error state to write for it.
    private var automaticPingsSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
            Text("Automatic pings")
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                .accessibilityAddTraits(.isHeader)

            // Three independent switches, each its own 60pt row -- the frame and content live
            // INSIDE the toggle's label, the same shape Clear and Test connection use above.
            VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                Toggle(
                    isOn: Binding(
                        get: { model.triggerSettings.significantChangeEnabled },
                        set: { newValue in Task { await model.setSignificantChange(newValue) } }
                    )
                ) {
                    Text("Big moves (500 m)")
                        .dsFont(.body)
                        .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget, alignment: .leading)
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                }
                .accessibilityLabel("Big moves, 500 metres")
                .accessibilityHint(
                    "Pings when you have moved at least 500 metres from the last ping.")

                Text("Pings when you have moved at least 500 metres from the last ping.")
                    .dsFont(.secondary)
                    .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                Toggle(
                    isOn: Binding(
                        get: { model.triggerSettings.visitsEnabled },
                        set: { newValue in Task { await model.setVisits(newValue) } }
                    )
                ) {
                    Text("Arrivals")
                        .dsFont(.body)
                        .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget, alignment: .leading)
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                }
                .accessibilityLabel("Arrivals")
                .accessibilityHint("Pings when you arrive somewhere and stay a while.")

                Text("Pings when you arrive somewhere and stay a while.")
                    .dsFont(.secondary)
                    .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                Toggle(
                    isOn: Binding(
                        get: { model.triggerSettings.geofenceEnabled },
                        set: { newValue in Task { await model.setGeofence(newValue) } }
                    )
                ) {
                    Text("Leaving the last spot")
                        .dsFont(.body)
                        .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget, alignment: .leading)
                        .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                }
                .accessibilityLabel("Leaving the last spot")
                .accessibilityHint("Pings when you leave the area around the last ping.")

                Text("Pings when you leave the area around the last ping.")
                    .dsFont(.secondary)
                    .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
                Stepper(
                    value: Binding(
                        get: { model.triggerSettings.minimumIntervalSeconds },
                        set: { newValue in Task { await model.setMinimumInterval(newValue) } }
                    ),
                    in: PingRateLimiter.hardFloor...300,
                    step: 15
                ) {
                    Text(
                        "Minimum gap between pings: \(Int(model.triggerSettings.minimumIntervalSeconds)) seconds"
                    )
                    .dsFont(.body)
                    .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget, alignment: .leading)
                    .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                }
                .accessibilityLabel("Minimum gap between pings")
                .accessibilityValue("\(Int(model.triggerSettings.minimumIntervalSeconds)) seconds")

                Text("This gap covers the I'm here button too, not just automatic pings.")
                    .dsFont(.secondary)
                    .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
            }

            if let triggerNotice = model.triggerNotice {
                // Body size, not secondary: DESIGN.md requires a failure to say what happened
                // and what to do next in body-size text on screen. No line limit, so it
                // reflows at AX5 instead of clipping.
                Text(triggerNotice)
                    .dsFont(.body)
                    .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The primary action, pinned to the bottom so the status badge grows upward instead of
    /// displacing it. Mirrors `PingHomeView.actionBar` -- same opaque `DSPalette` fill, same
    /// screen margin, and never a material: DESIGN.md bars Liquid Glass from behind the primary
    /// action. `savedBadge` is the ONLY thing allowed to share the bar, and only because it is one
    /// word. Everything that can render a sentence stays in the scroll: `errorView` (a validation
    /// message naming a field) and `connectionReportView` (a whole 401 body).
    private var saveBar: some View {
        VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
            savedBadge

            PingButton(title: "Save settings") {
                model.save()
            }
        }
        .padding(DSMetrics.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSPalette.body.background(for: colorScheme))
    }

    /// The bar's half: one word, never a sentence.
    ///
    /// Split from the error half at PR review. `statusView` used to render BOTH here, and an
    /// error is a full validation sentence at `.dsFont(.body)` -- e.g. "Header name cannot be
    /// empty — enter the header the key rides in, e.g. Authorization." At AX5 that wraps to
    /// roughly nine lines and the bar alone runs past the height of an iPhone SE, taking the
    /// 88pt action floor with it. `PingHomeView.actionBar`'s badge is `.secondary` and word-only
    /// for exactly this reason; this file's own rule ("only the short status badge is allowed to
    /// share the bar") was written and then broken in the same commit.
    @ViewBuilder
    private var savedBadge: some View {
        if case .saved = model.status {
            statusBadge(symbolName: "checkmark.circle.fill", text: "Saved", pair: DSPalette.success)
        }
    }

    /// The scroll's half: the sentence, next to the fields it names.
    ///
    /// Every error `SettingsModel` produces names a specific field ("Webhook URL must start with
    /// https://…", "Sender key is missing…"), so the scroll is where the user needs it anyway --
    /// beside the field they have to fix, not pinned 600pt below it next to a button.
    @ViewBuilder
    private var errorView: some View {
        if case .error(let message) = model.status {
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

/// A preview-only sender that answers with a fixed attempt and touches no network. It exists
/// because `connectionReport` is `private(set)`: a `#Preview` cannot assign a report, so it has
/// to produce one the way the app does -- through `testConnection()`.
private struct StubPingSending: PingSending {
    let attempt: PingAttempt

    func send(label: String) async -> PingAttempt { attempt }
    func send(label: String, using fix: LocationFix) async -> PingAttempt { attempt }
}

@MainActor
private func previewModel(
    hasStoredKey: Bool, sender: PingSending? = nil, triggers: (any TriggerControlling)? = nil
) -> SettingsModel {
    let store = PreviewCredentialStore(
        stored: hasStoredKey
            ? WebhookCredentials(
                url: URL(string: "https://example.invalid/webhook")!,
                senderKey: "preview-key-not-real.invalid",
                headerName: WebhookCredentials.defaultHeaderName)
            : nil
    )
    let model = SettingsModel(store: store, sender: sender, triggers: triggers)
    model.load()
    return model
}

/// A preview-only trigger control that answers with a fixed settings/notice pair and touches
/// no coordinator. `update(_:)` is a no-op -- previews never need it to change what's on screen.
private struct StubTriggerControl: TriggerControlling {
    let settings: TriggerSettings
    let notice: String?

    func update(_ settings: TriggerSettings) async {}
    func currentSettings() async -> TriggerSettings { settings }
    func authorizationNotice() async -> String? { notice }
}

/// Drives one `loadTriggers()` as the canvas appears so the toggles and notice are on screen by
/// the time the preview draws -- the same shape `PreviewTestedSettings` uses for a test result.
private struct PreviewSettingsWithTriggers: View {
    @State private var model: SettingsModel

    @MainActor
    init(hasStoredKey: Bool, triggerSettings: TriggerSettings, notice: String?) {
        _model = State(
            initialValue: previewModel(
                hasStoredKey: hasStoredKey,
                triggers: StubTriggerControl(settings: triggerSettings, notice: notice)))
    }

    var body: some View {
        SettingsView(model: model)
            .task { await model.loadTriggers() }
    }
}

/// All three triggers on, at the default interval, with the "you chose While Using" sentence
/// showing -- the one state this plan's must_haves require a preview for.
private let previewAllTriggersOnWithNotice = TriggerSettings(
    significantChangeEnabled: true,
    visitsEnabled: true,
    geofenceEnabled: true,
    minimumIntervalSeconds: PingRateLimiter.defaultInterval
)

/// Drives one `testConnection()` as the canvas appears so the report is on screen by the time
/// the preview draws. Preview scaffolding only -- in the app the button is what runs a test.
private struct PreviewTestedSettings: View {
    @State private var model: SettingsModel

    @MainActor
    init(hasStoredKey: Bool, attempt: PingAttempt) {
        _model = State(
            initialValue: previewModel(
                hasStoredKey: hasStoredKey, sender: StubPingSending(attempt: attempt)))
    }

    var body: some View {
        SettingsView(model: model)
            .task { await model.testConnection() }
    }
}

/// A wrong sender key as the webhook actually answers it: `PingClassifier`'s own 401 sentence,
/// the exact code, and a multi-line body -- so the AX5 previews show the body wrapping rather
/// than a short line that would have fitted anyway.
private let previewUnauthorizedAttempt = PingAttempt(
    fix: nil,
    disposition: .permanentFailure(
        reason:
            "Rejected by the webhook (HTTP 401). Check the sender key and header name in Settings."
    ),
    statusCode: 401,
    responseBody: """
        {
          "error": "unauthorized",
          "detail": "the value in the Authorization header did not match the routine's own"
        }
        """
)

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

#Preview("Light — test 401") {
    NavigationStack {
        PreviewTestedSettings(hasStoredKey: true, attempt: previewUnauthorizedAttempt)
    }
}

#Preview("Light — test 401, AX5") {
    NavigationStack {
        PreviewTestedSettings(hasStoredKey: true, attempt: previewUnauthorizedAttempt)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — test 401, AX5") {
    NavigationStack {
        PreviewTestedSettings(hasStoredKey: true, attempt: previewUnauthorizedAttempt)
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Light — all triggers on, notice") {
    NavigationStack {
        PreviewSettingsWithTriggers(
            hasStoredKey: true,
            triggerSettings: previewAllTriggersOnWithNotice,
            notice: TriggerAuthorizationNotice.notice(
                for: .authorizedWhenInUse, alwaysWasRequested: true))
    }
}

#Preview("Light — all triggers on, notice, AX5") {
    NavigationStack {
        PreviewSettingsWithTriggers(
            hasStoredKey: true,
            triggerSettings: previewAllTriggersOnWithNotice,
            notice: TriggerAuthorizationNotice.notice(
                for: .authorizedWhenInUse, alwaysWasRequested: true))
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
