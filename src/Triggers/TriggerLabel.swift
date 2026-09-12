import Foundation

/// The label seam for AUTOMATIC pings (04-10). REQUIREMENTS.md:34 makes the label best-effort:
/// an empty label is a NORMAL outcome, never a reason to drop or delay a ping, and geocoding
/// must stay off the delivery critical path. `label(for:)` is therefore non-throwing on
/// purpose -- a requirement, not a convenience -- so no caller ever has to handle a geocoding
/// failure to send a ping. A conformer that cannot produce a name returns "".
///
/// The shipping conformer performs reverse geocoding (D-15) and lives in its own sibling file
/// in this directory, because ARCHITECTURE.md's Forbidden entry confines that framework's
/// import to that one file and nowhere else -- this file imports only Foundation.
protocol TriggerLabelProviding: Sendable {
    /// Best-effort locality name for `coordinate`. Never throws, never crashes. "" means no
    /// label was produced -- absence, a failure, and a timed-out attempt are all the same
    /// outcome from a caller's point of view.
    func label(for coordinate: TriggerCoordinate) async -> String
}

/// The always-empty fallback. It stays in the codebase: it is what a caller injects when
/// geocoding is unwanted, and it is the test double 04-10's and 04-13's tests inject. Do not
/// delete it as dead code just because a real, geocoding-backed provider exists -- both
/// conformers ship.
struct EmptyTriggerLabelProvider: TriggerLabelProviding {
    func label(for coordinate: TriggerCoordinate) async -> String {
        ""
    }
}

/// Trims whitespace and newlines, collapsing anything that trims to empty -- including a
/// non-breaking space or other whitespace a geocoder-shaped string can carry -- to "". A
/// provider returning " " must never put a blank-looking label on the wire.
func normalisedTriggerLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed
}
