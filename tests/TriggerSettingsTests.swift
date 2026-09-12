import Foundation
import Testing
@testable import GrokBotLocator

/// Each test opens its own throwaway `UserDefaults(suiteName:)` under a fresh UUID and tears it
/// down with `removePersistentDomain(forName:)`, so no test sees another's keys and nothing
/// touches the app's real domain (.planning/LEARNINGS.md: no test may depend on real
/// `UserDefaults` global state leaking between cases).
@Suite struct TriggerSettingsTests {
    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "TriggerSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, name)
    }

    private func teardown(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
    }

    @Test func afreshInstallHasEveryTriggerOffAtSixtySeconds() {
        let settings = TriggerSettings.initial
        #expect(settings.significantChangeEnabled == false)
        #expect(settings.visitsEnabled == false)
        #expect(settings.geofenceEnabled == false)
        #expect(settings.minimumIntervalSeconds == PingRateLimiter.defaultInterval)
        #expect(settings.anyTriggerEnabled == false)
    }

    @Test func loadingAnEmptyStoreYieldsTheInitialSettings() {
        let (defaults, name) = makeSuite()
        defer { teardown(name) }

        let store = UserDefaultsTriggerSettingsStore(defaults: defaults)
        #expect(store.load() == TriggerSettings.initial)
    }

    @Test func settingsSurviveARoundTrip() {
        let (defaults, name) = makeSuite()
        defer { teardown(name) }

        var settings = TriggerSettings.initial
        settings.significantChangeEnabled = true
        settings.visitsEnabled = false
        settings.geofenceEnabled = true
        settings.setMinimumInterval(120)

        UserDefaultsTriggerSettingsStore(defaults: defaults).save(settings)

        // A second store instance over the SAME suite -- proves persistence, not memory.
        let reloaded = UserDefaultsTriggerSettingsStore(defaults: defaults).load()
        #expect(reloaded == settings)
    }

    @Test func eachTriggerSwitchesIndependently() {
        let (defaults, name) = makeSuite()
        defer { teardown(name) }
        let store = UserDefaultsTriggerSettingsStore(defaults: defaults)

        var significantChangeOnly = TriggerSettings.initial
        significantChangeOnly.significantChangeEnabled = true
        store.save(significantChangeOnly)
        var reloaded = store.load()
        #expect(reloaded.significantChangeEnabled == true)
        #expect(reloaded.visitsEnabled == false)
        #expect(reloaded.geofenceEnabled == false)

        var visitsOnly = TriggerSettings.initial
        visitsOnly.visitsEnabled = true
        store.save(visitsOnly)
        reloaded = store.load()
        #expect(reloaded.significantChangeEnabled == false)
        #expect(reloaded.visitsEnabled == true)
        #expect(reloaded.geofenceEnabled == false)

        var geofenceOnly = TriggerSettings.initial
        geofenceOnly.geofenceEnabled = true
        store.save(geofenceOnly)
        reloaded = store.load()
        #expect(reloaded.significantChangeEnabled == false)
        #expect(reloaded.visitsEnabled == false)
        #expect(reloaded.geofenceEnabled == true)
    }

    @Test func anIntervalBelowTheFloorIsClampedOnWrite() {
        let (defaults, name) = makeSuite()
        defer { teardown(name) }
        let store = UserDefaultsTriggerSettingsStore(defaults: defaults)

        for candidate: TimeInterval in [5, 0, -30] {
            var settings = TriggerSettings.initial
            settings.setMinimumInterval(candidate)
            store.save(settings)
            #expect(store.load().minimumIntervalSeconds == PingRateLimiter.hardFloor)
        }
    }

    @Test func anIntervalHandEditedBelowTheFloorIsClampedOnRead() {
        let (defaults, name) = makeSuite()
        defer { teardown(name) }

        // Written DIRECTLY, bypassing TriggerSettingsStoring.save entirely -- this is the one
        // that proves the clamp is on the read path, not only on the write path.
        defaults.set(3.0, forKey: "triggers.minimumIntervalSeconds")

        let loaded = UserDefaultsTriggerSettingsStore(defaults: defaults).load()
        #expect(loaded.minimumIntervalSeconds == PingRateLimiter.hardFloor)
    }

    @Test func aNonFiniteIntervalIsClamped() {
        var settings = TriggerSettings.initial
        settings.setMinimumInterval(.nan)
        #expect(settings.minimumIntervalSeconds == PingRateLimiter.hardFloor)

        settings.setMinimumInterval(.infinity)
        #expect(settings.minimumIntervalSeconds.isFinite)
    }
}
