import Foundation
import Testing
@testable import GrokBotLocator

/// The label seam and its always-empty fallback -- no network, no MapKit, deterministic.
@Suite
struct TriggerLabelTests {
    @Test
    func theFallbackProviderReturnsAnEmptyLabel() async {
        let provider = EmptyTriggerLabelProvider()

        let a = await provider.label(for: TriggerCoordinate(latitude: 0, longitude: 0))
        let b = await provider.label(for: TriggerCoordinate(latitude: 41.1171, longitude: 16.8719))
        let c = await provider.label(for: TriggerCoordinate(latitude: -33.8688, longitude: 151.2093))

        #expect(a == "")
        #expect(b == "")
        #expect(c == "")
    }

    @Test
    func aWhitespaceOnlyLabelNormalisesToEmpty() {
        #expect(normalisedTriggerLabel("") == "")
        #expect(normalisedTriggerLabel(" ") == "")
        #expect(normalisedTriggerLabel("\n\t ") == "")
        #expect(normalisedTriggerLabel(" \u{00A0}") == "")
    }

    @Test
    func aRealLocalityIsPassedThroughTrimmed() {
        #expect(normalisedTriggerLabel(" Alberobello \n") == "Alberobello")
    }

    @Test
    func aSlowProviderStillYieldsALabel() async {
        struct SlowProvider: TriggerLabelProviding {
            func label(for coordinate: TriggerCoordinate) async -> String {
                try? await Task.sleep(for: .milliseconds(1))
                return "Locorotondo"
            }
        }

        let result = await SlowProvider().label(for: TriggerCoordinate(latitude: 0, longitude: 0))

        #expect(result == "Locorotondo")
    }

    @Test
    func theSeamCannotThrow() async {
        struct InternallyThrowingProvider: TriggerLabelProviding {
            func label(for coordinate: TriggerCoordinate) async -> String {
                (try? await Self.riskyLookup()) ?? ""
            }

            static func riskyLookup() async throws -> String {
                throw CancellationError()
            }
        }

        // No `try` and no `do`/`catch` at this call site -- the property REQUIREMENTS.md:34's
        // "never a reason to drop a ping" rests on.
        let result = await InternallyThrowingProvider().label(for: TriggerCoordinate(latitude: 0, longitude: 0))

        #expect(result == "")
    }
}
