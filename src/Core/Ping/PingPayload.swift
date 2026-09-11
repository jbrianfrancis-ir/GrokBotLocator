import Foundation

/// Thrown by `encoded()` when a coordinate or accuracy is not finite -- `inf`/`nan` are not
/// valid JSON numbers, and a fail-closed refusal beats handing the routine a body it cannot
/// parse.
enum PingPayloadError: Error, Equatable {
    case nonFiniteValue
}

/// The wire format: the one type that knows what the Grok routine receives. `Codable` stays
/// because ARCHITECTURE makes phase 03's offline queue a `Codable` array, but the synthesized
/// `Encoder`/`Decoder` conformance is NOT the wire format -- `encoded()` is, and it composes
/// the JSON object itself rather than going through `JSONEncoder`, because `JSONEncoder`'s
/// keyed container is dictionary-backed and does not serialize in `CodingKeys` order: key
/// order is non-deterministic per process under Swift's hash seeding (measured on the iOS 26
/// simulator runtime across six consecutive runs of this exact struct), and sorting the keys
/// alphabetically does not recover ARCHITECTURE's required order either.
struct PingPayload: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMetres: Double
    let label: String
    let capturedAt: Date

    private enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case accuracyMetres = "accuracy_m"
        case label
        case capturedAt = "at"
    }

    /// Composes the wire bytes directly, in ARCHITECTURE's exact key order --
    /// `lat, lng, accuracy_m, label, at` -- rather than delegating object construction to
    /// `JSONEncoder`. `label` is always present, empty string included; it is never optional
    /// and never omitted.
    func encoded() throws -> Data {
        guard latitude.isFinite, longitude.isFinite, accuracyMetres.isFinite else {
            throw PingPayloadError.nonFiniteValue
        }

        // Swift's `Double` description is the shortest round-trippable decimal form --
        // 40.77465 stays "40.77465" and an integral value renders "17.0" -- both valid JSON
        // numbers, so plain string interpolation is sufficient here.
        let latText = "\(latitude)"
        let lngText = "\(longitude)"
        let accuracyText = "\(accuracyMetres)"

        // Escape the label via Foundation, never by hand. Encoding a single-element ARRAY
        // (rather than the label alone in a keyed container) sidesteps the dictionary-backed
        // keyed-container non-determinism entirely, because an array's element order is
        // defined. The result is `["<escaped label>"]`; dropping the outer brackets leaves
        // the label as a complete, correctly escaped JSON string literal.
        let quotedArray = try JSONEncoder().encode([label])
        let quotedLabel = String(decoding: quotedArray.dropFirst().dropLast(), as: UTF8.self)

        // `at` is the ISO-8601 UTC instant of the FIX (`capturedAt`), never of this encode
        // call -- ARCHITECTURE's D-12. Escaped through the same single-element-array trick as
        // `label`, so exactly one rule governs string escaping in this file.
        let atText = capturedAt.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
        let quotedAtArray = try JSONEncoder().encode([atText])
        let quotedAt = String(decoding: quotedAtArray.dropFirst().dropLast(), as: UTF8.self)

        let json =
            "{\"lat\":\(latText),\"lng\":\(lngText),\"accuracy_m\":\(accuracyText),\"label\":\(quotedLabel),\"at\":\(quotedAt)}"
        return Data(json.utf8)
    }
}
