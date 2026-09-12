import Foundation
import Testing
@testable import GrokBotLocator

/// MapKit's geocoding service cannot be faked or stubbed, so this suite asserts the CONTRACT
/// that holds with or without a network -- never that a particular place name comes back.
/// RESEARCH.md `## Unverified`: `MKReverseGeocodingRequest`'s rate-limit and offline error
/// semantics are not established, so this plan's backstop_truths pins only "any failure ⇒
/// empty label" -- no numeric throttle, no specific error case -- and neither is asserted here.
@Suite
struct MapKitTriggerLabelProviderTests {
    @Test
    func anInvalidCoordinateYieldsAnEmptyLabel() async {
        let provider = MapKitTriggerLabelProvider()

        let result = await provider.label(for: TriggerCoordinate(latitude: 200, longitude: 200))

        #expect(result == "")
    }

    @Test
    func aSecondInvalidCoordinateAlsoYieldsAnEmptyLabelAndDoesNotTrap() async {
        let provider = MapKitTriggerLabelProvider()

        let result = await provider.label(
            for: TriggerCoordinate(latitude: .nan, longitude: .infinity))

        #expect(result == "")
    }

    @Test
    func aLabelAttemptRespectsItsBudget() async {
        let provider = MapKitTriggerLabelProvider(budget: .milliseconds(50))
        let coordinate = TriggerCoordinate(latitude: 41.1171, longitude: 16.8719)

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await provider.label(for: coordinate)
        }

        #expect(elapsed < .seconds(2))
    }

    @Test
    func theResultIsAlwaysAStringAndNeverThrows() async {
        let provider = MapKitTriggerLabelProvider()
        let coordinate = TriggerCoordinate(latitude: 41.1171, longitude: 16.8719)

        // No `try`, no `do`/`catch` at this call site. `result` is either "" or a trimmed
        // non-empty string -- either way it is already normalised, so re-normalising it is a
        // no-op.
        let result = await provider.label(for: coordinate)

        #expect(result == normalisedTriggerLabel(result))
    }

    @Test
    func theDefaultBudgetIsThreeSeconds() {
        #expect(MapKitTriggerLabelProvider.budget == .seconds(3))
    }
}
