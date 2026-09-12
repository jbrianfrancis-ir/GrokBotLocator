import Foundation
import Testing
@testable import GrokBotLocator

/// Proves REQ-06's acceptance clause on a laptop, no device required: a 300 m move delivers no
/// ping and a 500 m move delivers one. Every test offsets latitude from a fixed origin (Bari)
/// and asserts the MEASURED distance lands in the intended band FIRST, then asserts the gate --
/// a bad offset arithmetic shows up as its own failure rather than as a wrong verdict.
///
/// The offset is found by bisecting on `DisplacementGate.distanceMetres` itself (60
/// iterations, converging to sub-micrometre error) rather than a flat `metres / 111_320`
/// degrees-of-latitude approximation: measured, the linear approximation is off by ~1.2 m at
/// 500 m (WGS84's meridian arc length per degree is latitude-dependent, not the equatorial
/// constant), which is enough to land the "exactly 500 m" case on the wrong side of `>=`. This
/// is deterministic and reads no clock -- the same two fixed coordinates every run.
@Suite
struct DisplacementGateTests {
    private static let originLatitude = 41.1171
    private static let originLongitude = 16.8719

    private static func origin() -> TriggerCoordinate {
        TriggerCoordinate(latitude: originLatitude, longitude: originLongitude)
    }

    private static func northOffset(metres: Double) -> TriggerCoordinate {
        guard metres > 0 else { return origin() }
        var lowDegrees = 0.0
        var highDegrees = metres / 50_000.0
        let reference = origin()
        for _ in 0..<60 {
            let midDegrees = (lowDegrees + highDegrees) / 2
            let candidate = TriggerCoordinate(
                latitude: originLatitude + midDegrees, longitude: originLongitude)
            if DisplacementGate.distanceMetres(from: reference, to: candidate) < metres {
                lowDegrees = midDegrees
            } else {
                highDegrees = midDegrees
            }
        }
        return TriggerCoordinate(latitude: originLatitude + highDegrees, longitude: originLongitude)
    }

    @Test
    func aThreeHundredMetreMoveDoesNotPing() {
        let reference = Self.origin()
        let candidate = Self.northOffset(metres: 300)

        let distance = DisplacementGate.distanceMetres(from: reference, to: candidate)
        #expect((295...305).contains(distance))
        #expect(DisplacementGate.shouldPing(from: reference, to: candidate) == false)
    }

    @Test
    func aMoveOfExactlyFiveHundredMetresPings() {
        let reference = Self.origin()
        let candidate = Self.northOffset(metres: 500)

        let distance = DisplacementGate.distanceMetres(from: reference, to: candidate)
        #expect((495...505).contains(distance))
        #expect(DisplacementGate.shouldPing(from: reference, to: candidate) == true)
    }

    @Test
    func aKilometreMovePings() {
        let reference = Self.origin()
        let candidate = Self.northOffset(metres: 1000)

        #expect(DisplacementGate.shouldPing(from: reference, to: candidate) == true)
    }

    @Test
    func aStationaryPhoneDoesNotPing() {
        let reference = Self.origin()
        let candidate = Self.origin()

        #expect(DisplacementGate.distanceMetres(from: reference, to: candidate) == 0)
        #expect(DisplacementGate.shouldPing(from: reference, to: candidate) == false)
    }

    @Test
    func noReferenceCoordinatePings() {
        #expect(DisplacementGate.shouldPing(from: nil, to: Self.origin()) == true)
    }

    @Test
    func theThresholdIsFiveHundredMetres() {
        #expect(DisplacementGate.minimumMetres == 500)
    }

    @Test
    func displacementIsSymmetric() {
        let a = Self.origin()
        let b = Self.northOffset(metres: 750)

        let forward = DisplacementGate.distanceMetres(from: a, to: b)
        let backward = DisplacementGate.distanceMetres(from: b, to: a)
        #expect(abs(forward - backward) < 0.5)
    }
}
