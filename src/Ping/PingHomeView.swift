// CoreLocation is imported for the #Preview fakes at the bottom of this file only: reading
// `LocationAuthorizationNotice.notice(for: .authorizedWhenInUse)` shows REQ-10's real sentence
// in the canvas instead of a paraphrase that could drift from it. No location manager and no
// location work of any kind lives in this view -- ARCHITECTURE.md keeps all of that in the one
// actor-isolated coordinator, and `./scripts/smoke.sh`'s location guard proves this file has
// none of it.
import CoreLocation
import SwiftUI

/// The "I'm here" screen: label, button, history. A `ScrollView` over a `VStack`, never a
/// `Form`, so AX5 reflows vertically with nothing clipped -- the same shape `SettingsView`
/// uses, and the reason its screen title lives in the scrolling content rather than in a bar.
///
/// The title is deliberately NOT in the chrome bar. Two DESIGN.md rules collide there: "chrome:
/// navigation and toolbars only" invites a title bar, while "no text over photographic or
/// variable backgrounds" and the 7:1 contrast floor cannot be met by text sitting over content
/// scrolling beneath a material -- there is no fixed background to measure the ratio against.
/// The arithmetic rules it out independently: `.screenTitle` renders ~64pt at AX5, and an
/// unbreakable 14-character app name needs 400pt+ against ~290-410pt of portrait content width.
/// So the bar carries the Settings control alone -- an SF Symbol is not text to contrast-check
/// and has no truncation behaviour -- and "Send a ping" wraps in the content as a three-word
/// string. DESIGN.md is satisfied as written and is not amended.
///
/// This screen is where three phase-01 components finally get a production call site:
/// `PingButton`'s in-flight state, `PingOutcomeRow`, and the chrome fallback modifier. That
/// modifier is applied exactly once in this file, on the bar below -- the primary action gets an
/// opaque `DSPalette` fill instead, because DESIGN.md forbids Liquid Glass behind it. The count
/// is the guard: one application means the bar has it and the action does not.
struct PingHomeView: View {
    @Bindable var model: PingModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                // The screen's only title, and a multi-word one on purpose: three words wrap
                // across lines at AX5 where a single long word could only truncate.
                Text("Send a ping")
                    .dsFont(.screenTitle)
                    .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                    .accessibilityAddTraits(.isHeader)

                // DESIGN.md's only Input component. Not secure and no saved indicator: a place
                // name is not a credential, so it is shown and edited like ordinary text.
                CredentialField(
                    label: "Ping label",
                    text: $model.label,
                    footnote: "Sent with every ping and remembered between pings."
                )

                if let notice = model.authorizationNotice {
                    noticeBlock(
                        symbolName: "info.circle.fill", text: notice, pair: DSPalette.pending)
                }

                if let guidance = model.guidance {
                    noticeBlock(
                        symbolName: "exclamationmark.triangle.fill", text: guidance,
                        pair: DSPalette.failure)
                }

                history
            }
            .padding(DSMetrics.screenMargin)
        }
        .safeAreaInset(edge: .top) { PingChromeBar() }
        .safeAreaInset(edge: .bottom) { actionBar }
        // The system bar would otherwise sit empty above the custom chrome bar. SettingsView
        // keeps its own bar -- and its Back button -- when it is pushed from here.
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.refreshAuthorizationNotice() }
        // DESIGN.md: the ping outcome is announced, not just rendered.
        .onChange(of: model.lastAnnouncement) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    /// Newest first, which is the order `PingHistoryLog` already keeps -- nothing here sorts.
    /// An empty log says what to do rather than showing a bare heading with nothing under it.
    @ViewBuilder
    private var history: some View {
        if model.log.entries.isEmpty {
            Text("No pings yet. Tap I'm here to send one.")
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
        } else {
            ForEach(model.log.entries) { entry in
                PingOutcomeRow(
                    timestamp: entry.timestamp,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    label: entry.label,
                    outcome: entry.outcome,
                    reason: entry.reason
                )
            }
        }
    }

    /// The primary action, full-width in the bottom third for one-handed reach. The fill is an
    /// opaque `DSPalette` pair and never a material of any kind: DESIGN.md bars Liquid Glass from
    /// behind the primary action, so the chrome modifier stays on the bar above and off this.
    private var actionBar: some View {
        PingButton(
            title: "I'm here", inFlightTitle: "Pinging…", isInFlight: model.isInFlight
        ) {
            Task { await model.ping() }
        }
        .padding(DSMetrics.screenMargin)
        .frame(maxWidth: .infinity)
        .background(DSPalette.body.background(for: colorScheme))
    }

    /// Symbol + sentence + colour on the pair's own opaque fill -- never colour alone, and on
    /// screen in body-size text rather than a toast or an alert (DESIGN.md). Same shape as
    /// `SettingsView`'s status badge. No line cap: at AX5 these sentences have to wrap.
    private func noticeBlock(symbolName: String, text: String, pair: DSColorPair) -> some View {
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

/// Where plan 02-13's `RootView` registers `SettingsView` as a navigation destination. Empty on
/// purpose: the route carries no parameters, only the fact that Settings was asked for.
struct SettingsRoute: Hashable {}

/// The app's only production application of the chrome fallback modifier, and the bar carries NO
/// text -- just the gear. That is what keeps a translucent surface with content scrolling beneath
/// it inside DESIGN.md: an SF Symbol is not text to contrast-check and cannot truncate.
private struct PingChromeBar: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Spacer()
            NavigationLink(value: SettingsRoute()) {
                // `minWidth`/`minHeight`, never a fixed `width`/`height`: `.dsFont` resolves
                // through `@ScaledMetric` and an SF Symbol takes its size from the applied
                // font, so a 28pt base reaches ~59pt at AX5. SwiftUI does not clip, so a fixed
                // 60pt box would let the glyph draw outside its frame and overlap the content
                // scrolling beneath -- which DESIGN.md forbids. 60pt is the tap-target floor
                // the glyph may grow past, the shape SettingsView's Clear button already uses,
                // and the frame lives INSIDE the label so the whole area takes the tap.
                Image(systemName: "gearshape")
                    .dsFont(.actionLabel)
                    .frame(minWidth: DSMetrics.minTapTarget, minHeight: DSMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
            .accessibilityLabel("Settings")
        }
        .padding(DSMetrics.screenMargin)
        .dsChrome()
    }
}

// MARK: - Previews

/// One fixed fix for every preview send -- `accuracyMetres` is a plausible city reading, and
/// the coordinates are the same Puglia pair the other design-system previews use.
private let previewFix = LocationFix(
    latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12,
    timestamp: Date(timeIntervalSince1970: 1_700_000_000))

private let previewSentAttempt = PingAttempt(
    fix: previewFix, disposition: .sent, statusCode: 200, responseBody: "")

/// `PingClassifier`'s own 401 sentence, long enough that the AX5 previews show the reason line
/// wrapping rather than a short phrase that would have fitted anyway.
private let previewFailedAttempt = PingAttempt(
    fix: previewFix,
    disposition: .permanentFailure(
        reason:
            "Rejected by the webhook (HTTP 401). Check the sender key and header name in Settings."
    ),
    statusCode: 401, responseBody: nil)

/// Answers each `send` with the next attempt in the list, so one preview produces a sent row
/// and a failed row. Preview-only: no credential, no network, no disk.
///
/// `@unchecked Sendable` for the same reason `SettingsView`'s preview store carries it: the
/// protocol is `Sendable` and this fake is touched only by one preview's `.task`.
private final class PreviewPingSending: PingSending, @unchecked Sendable {
    private let attempts: [PingAttempt]
    private var index = 0

    init(attempts: [PingAttempt]) {
        self.attempts = attempts
    }

    func send(label: String) async -> PingAttempt {
        let attempt = attempts[min(index, attempts.count - 1)]
        index += 1
        return attempt
    }
}

/// In memory only -- never `UserDefaults`, so a preview cannot write into the real app's label.
private final class PreviewPingLabelStore: PingLabelStore, @unchecked Sendable {
    private var stored: String

    init(stored: String) {
        self.stored = stored
    }

    func loadLabel() -> String { stored }
    func save(_ label: String) { stored = label }
}

/// Hands back the fixed fix and the real "When In Use" notice (REQ-10), so the canvas shows the
/// production sentence at AX5. Touches no location manager and no device.
private struct PreviewFixProvider: LocationFixProvider {
    func currentFix() async throws -> LocationFix { previewFix }

    func authorizationNotice() async -> String? {
        LocationAuthorizationNotice.notice(for: .authorizedWhenInUse)
    }
}

/// `PingModel.log` is `private(set)`, so a preview cannot assign history -- it has to produce it
/// the way the app does, by running `ping()`. Two sends give one sent row and one failed row,
/// newest first, which is what the AX5 previews need on screen.
private struct PreviewPingHome: View {
    @State private var model: PingModel

    @MainActor
    init() {
        _model = State(
            initialValue: PingModel(
                sender: PreviewPingSending(
                    attempts: [previewSentAttempt, previewFailedAttempt]),
                labelStore: PreviewPingLabelStore(stored: "Gallipoli"),
                fixes: PreviewFixProvider()))
    }

    var body: some View {
        NavigationStack {
            PingHomeView(model: model)
                // Preview scaffolding for the gear link only; the app registers the real
                // SettingsView here (plan 02-13). Without a destination the link renders
                // disabled, which would misreport the bar in the canvas.
                .navigationDestination(for: SettingsRoute.self) { _ in
                    Text("Settings")
                        .dsFont(.body)
                }
        }
        .task {
            await model.ping()
            await model.ping()
        }
    }
}

#Preview("Light — default") {
    PreviewPingHome()
}

#Preview("Dark — default") {
    PreviewPingHome()
        .preferredColorScheme(.dark)
}

#Preview("Light — AX5") {
    PreviewPingHome()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — AX5") {
    PreviewPingHome()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
