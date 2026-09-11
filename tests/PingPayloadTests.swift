import Foundation
import Testing
@testable import GrokBotLocator

/// Pins the wire format `PingPayload.encoded()` produces -- the exact shape ARCHITECTURE.md's
/// smoke gate names. Every fixture is synthetic; none is a real coordinate or credential.
@Suite
struct PingPayloadTests {

    private static let fixture = PingPayload(
        latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5, label: "Gallipoli",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000))

    @Test
    func encodesExactlyTheFiveKeysWithTheRightTypes() throws {
        let data = try Self.fixture.encoded()
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("expected a JSON object, got \(parsed)")
            return
        }

        #expect(Set(dict.keys) == ["lat", "lng", "accuracy_m", "label", "at"])

        #expect(dict["lat"] is NSNumber)
        #expect(dict["lng"] is NSNumber)
        #expect(dict["accuracy_m"] is NSNumber)
        #expect(dict["label"] is String)
        #expect(dict["at"] is String)

        #expect((dict["lat"] as? NSNumber)?.doubleValue == 40.77465)
        #expect((dict["lng"] as? NSNumber)?.doubleValue == 17.23107)
        #expect((dict["accuracy_m"] as? NSNumber)?.doubleValue == 12.5)
        #expect(dict["label"] as? String == "Gallipoli")
        // The literal, not a re-derivation through the same format style, so a format change
        // fails this test instead of moving with it.
        #expect(dict["at"] as? String == "2023-11-14T22:13:20Z")
    }

    @Test
    func keysAppearInTheOrderArchitectureNames() throws {
        let data = try Self.fixture.encoded()
        let json = String(decoding: data, as: UTF8.self)

        guard let latRange = json.range(of: "\"lat\""),
            let lngRange = json.range(of: "\"lng\""),
            let accuracyRange = json.range(of: "\"accuracy_m\""),
            let labelRange = json.range(of: "\"label\""),
            let atRange = json.range(of: "\"at\"")
        else {
            Issue.record("expected all five keys present in \(json)")
            return
        }

        #expect(latRange.lowerBound < lngRange.lowerBound)
        #expect(lngRange.lowerBound < accuracyRange.lowerBound)
        #expect(accuracyRange.lowerBound < labelRange.lowerBound)
        #expect(labelRange.lowerBound < atRange.lowerBound)
    }

    @Test
    func atCarriesTheFixTimeNotTheEncodeTime() throws {
        let payload = PingPayload(
            latitude: 1, longitude: 2, accuracyMetres: 3, label: "x",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try payload.encoded()
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("expected a JSON object, got \(parsed)")
            return
        }

        #expect(dict["at"] as? String == "2023-11-14T22:13:20Z")

        // The fix time is years in the past relative to now -- nowhere near "within a minute"
        // of the encode call, which is exactly the drift a bug reaching for `Date()` at encode
        // time would erase.
        guard let atText = dict["at"] as? String,
            let atDate = try? Date(atText, strategy: Date.ISO8601FormatStyle(timeZone: .gmt))
        else {
            Issue.record("expected `at` to parse as ISO-8601, got \(dict["at"] ?? "nil")")
            return
        }
        #expect(abs(atDate.timeIntervalSinceNow) > 60)
    }

    @Test
    func encodingIsByteStableAcrossCalls() throws {
        let first = try Self.fixture.encoded()
        for _ in 0..<50 {
            #expect(try Self.fixture.encoded() == first)
        }
    }

    @Test
    func anEmptyLabelStillEmitsTheKey() throws {
        let payload = PingPayload(
            latitude: 1, longitude: 2, accuracyMetres: 3, label: "",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try payload.encoded()
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("expected a JSON object, got \(parsed)")
            return
        }

        #expect(dict.keys.contains("label"))
        #expect(dict["label"] as? String == "")
    }

    @Test
    func foundationEscapesAnAwkwardLabel() throws {
        let awkward = "Santa Maria di \"Leuca\"\nPuglia — café"
        let payload = PingPayload(
            latitude: 1, longitude: 2, accuracyMetres: 3, label: awkward,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try payload.encoded()

        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("expected a JSON object, got \(parsed)")
            return
        }
        #expect(dict["label"] as? String == awkward)

        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("\\\""))
        #expect(raw.contains("\\n"))
        #expect(!raw.contains("di \"Leuca\""))
    }

    @Test
    func refusesNonFiniteValues() {
        let nonFiniteValues: [Double] = [.infinity, -.infinity, .nan]

        for value in nonFiniteValues {
            let badLatitude = PingPayload(
                latitude: value, longitude: 2, accuracyMetres: 3, label: "x",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
            #expect(throws: PingPayloadError.nonFiniteValue) { try badLatitude.encoded() }

            let badLongitude = PingPayload(
                latitude: 1, longitude: value, accuracyMetres: 3, label: "x",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
            #expect(throws: PingPayloadError.nonFiniteValue) { try badLongitude.encoded() }

            let badAccuracy = PingPayload(
                latitude: 1, longitude: 2, accuracyMetres: value, label: "x",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
            #expect(throws: PingPayloadError.nonFiniteValue) { try badAccuracy.encoded() }
        }
    }
}
