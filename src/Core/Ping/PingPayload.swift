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

    private enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case accuracyMetres = "accuracy_m"
        case label
    }

    /// Composes the wire bytes directly, in ARCHITECTURE's exact key order --
    /// `lat, lng, accuracy_m, label` -- rather than delegating object construction to
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

        let json = "{\"lat\":\(latText),\"lng\":\(lngText),\"accuracy_m\":\(accuracyText),\"label\":\(quotedLabel)}"
        return Data(json.utf8)
    }
}
