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
    func encodesExactlyTheFourKeysWithTheRightTypes() throws {
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

        #expect((dict["lat"] as? NSNumber)?.doubleValue == 40.77465)
        #expect((dict["lng"] as? NSNumber)?.doubleValue == 17.23107)
        #expect((dict["accuracy_m"] as? NSNumber)?.doubleValue == 12.5)
        #expect(dict["label"] as? String == "Gallipoli")
    }

    @Test
    func keysAppearInTheOrderArchitectureNames() throws {
        let data = try Self.fixture.encoded()
        let json = String(decoding: data, as: UTF8.self)

        guard let latRange = json.range(of: "\"lat\""),
            let lngRange = json.range(of: "\"lng\""),
            let accuracyRange = json.range(of: "\"accuracy_m\""),
            let labelRange = json.range(of: "\"label\"")
        else {
            Issue.record("expected all four keys present in \(json)")
            return
        }

        #expect(latRange.lowerBound < lngRange.lowerBound)
        #expect(lngRange.lowerBound < accuracyRange.lowerBound)
        #expect(accuracyRange.lowerBound < labelRange.lowerBound)
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
