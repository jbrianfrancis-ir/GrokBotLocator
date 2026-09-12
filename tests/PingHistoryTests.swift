import Foundation
import Testing
@testable import GrokBotLocator

/// Exercises `UserDefaultsPingLabelStore` and `PingHistoryLog` -- label memory across two
/// store instances over the same defaults, and log ordering/capping -- never against the
/// app's real defaults. Every `UserDefaults` case builds its own throwaway suite
/// ("test." + a fresh UUID) and removes it when done, exactly as `KeychainCredentialStoreTests`
/// uses a throwaway Keychain service string.
@Suite
struct PingHistoryTests {

    private static func throwawaySuiteName() -> String {
        "test." + UUID().uuidString
    }

    /// Builds a throwaway `UserDefaults` suite and returns it alongside a teardown closure --
    /// callers `defer { teardown() }` so a failed assertion still cleans up.
    private static func throwawayDefaults() -> (defaults: UserDefaults, teardown: () -> Void) {
        let suiteName = throwawaySuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    // MARK: - PingLabelStore

    @Test
    func freshStoreOverEmptyDefaultsReturnsEmptyLabel() {
        let (defaults, teardown) = Self.throwawayDefaults()
        defer { teardown() }

        let store = UserDefaultsPingLabelStore(defaults: defaults)
        #expect(store.loadLabel() == "")
    }

    /// The real claim behind REQ-03: the value outlives the object that wrote it. A second,
    /// independently-constructed store over the SAME defaults must read back what the first
    /// one saved.
    @Test
    func savedLabelOutlivesTheStoreThatWroteIt() {
        let (defaults, teardown) = Self.throwawayDefaults()
        defer { teardown() }

        let writer = UserDefaultsPingLabelStore(defaults: defaults)
        writer.save("Gallipoli")

        let reader = UserDefaultsPingLabelStore(defaults: defaults)
        #expect(reader.loadLabel() == "Gallipoli")
    }

    @Test
    func savingAnEmptyLabelReadsBackEmpty() {
        let (defaults, teardown) = Self.throwawayDefaults()
        defer { teardown() }

        let store = UserDefaultsPingLabelStore(defaults: defaults)
        store.save("")
        #expect(store.loadLabel() == "")
    }

    /// The store's only side effect is one key. No credential, no coordinate, nothing else
    /// ever lands in the suite's defaults. `dictionaryRepresentation()` merges in the search
    /// list's other domains (global domain, etc.) and is never empty even on a fresh suite,
    /// so the suite's OWN persistent domain -- not the merged view -- is what proves this.
    @Test
    func savingWritesExactlyOneKeyNamedPingLabel() {
        let suiteName = Self.throwawaySuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsPingLabelStore(defaults: defaults)
        store.save("Gallipoli")

        let dict = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(dict.count == 1)
        #expect(dict["ping.label"] as? String == "Gallipoli")
    }

    // MARK: - PingHistoryLog

    private static func makeEntry(
        id: UUID = UUID(),
        outcome: PingOutcome = .sent,
        reason: String? = nil,
        trigger: PingTrigger? = nil
    ) -> PingHistoryEntry {
        PingHistoryEntry(
            id: id,
            timestamp: Date(),
            latitude: 40.77465,
            longitude: 17.23107,
            label: "Manual ping",
            outcome: outcome,
            reason: reason,
            trigger: trigger
        )
    }

    @Test
    func recordingThreeEntriesLeavesThemNewestFirst() {
        var log = PingHistoryLog()
        let first = Self.makeEntry()
        let second = Self.makeEntry()
        let third = Self.makeEntry()

        log.record(first)
        log.record(second)
        log.record(third)

        #expect(log.entries.map(\.id) == [third.id, second.id, first.id])
    }

    /// Recording past capacity drops the oldest, not the newest: after 55 recordings only the
    /// most recent 50 remain, newest-first.
    @Test
    func recordingBeyondCapacityDropsTheOldest() {
        var log = PingHistoryLog()
        let entries = (1...55).map { _ in Self.makeEntry() }
        for entry in entries {
            log.record(entry)
        }

        #expect(log.entries.count == PingHistoryLog.capacity)
        #expect(log.entries.first?.id == entries[54].id)
        #expect(log.entries.last?.id == entries[5].id)
    }

    @Test
    func failedEntryKeepsItsReasonAndSentEntryHasNone() {
        let failed = Self.makeEntry(outcome: .failed, reason: "The webhook returned 500.")
        let sent = Self.makeEntry(outcome: .sent)

        #expect(failed.outcome == .failed)
        #expect(failed.reason == "The webhook returned 500.")
        #expect(sent.outcome == .sent)
        #expect(sent.reason == nil)
    }

    // MARK: - PingHistoryLog.apply (PingDeliveryUpdate)

    private static func makeUpdate(
        id: UUID,
        outcome: PingOutcome = .sent,
        reason: String? = nil,
        trigger: PingTrigger? = nil
    ) -> PingDeliveryUpdate {
        PingDeliveryUpdate(
            id: id,
            timestamp: Date(),
            latitude: 40.77465,
            longitude: 17.23107,
            label: "Manual ping",
            outcome: outcome,
            reason: reason,
            trigger: trigger
        )
    }

    /// The in-place flip: a row already in the log gets corrected at ITS OWN index rather than
    /// jumping to the top, which is what would make "flipped to Sent" indistinguishable from a
    /// second ping.
    @Test
    func applyingAnUpdateForAKnownIdReplacesTheRowInPlace() {
        var log = PingHistoryLog()
        let first = Self.makeEntry(outcome: .queued, reason: "Waiting to send.")
        let second = Self.makeEntry(outcome: .queued, reason: "Waiting to send.")
        let third = Self.makeEntry(outcome: .queued, reason: "Waiting to send.")
        log.record(first)
        log.record(second)
        log.record(third)
        // Newest-first: [third, second, first]. The middle entry is `second`, at index 1.

        log.apply(Self.makeUpdate(id: second.id, outcome: .sent, reason: nil))

        #expect(log.entries.count == 3)
        #expect(log.entries.map(\.id) == [third.id, second.id, first.id])
        #expect(log.entries[1].outcome == .sent)
        #expect(log.entries[1].reason == nil)
    }

    @Test
    func applyingAnUpdateForAnUnknownIdInsertsANewestFirstRow() {
        var log = PingHistoryLog()
        let update = Self.makeUpdate(id: UUID(), outcome: .sent, reason: nil)

        log.apply(update)

        #expect(log.entries.count == 1)
        let entry = log.entries[0]
        #expect(entry.id == update.id)
        #expect(entry.timestamp == update.timestamp)
        #expect(entry.latitude == update.latitude)
        #expect(entry.longitude == update.longitude)
        #expect(entry.label == update.label)
        #expect(entry.outcome == update.outcome)
        #expect(entry.reason == update.reason)
    }

    @Test
    func applyingUpdatesNeverExceedsCapacity() {
        var log = PingHistoryLog()
        for _ in 1...(PingHistoryLog.capacity + 5) {
            log.apply(Self.makeUpdate(id: UUID()))
        }

        #expect(log.entries.count == PingHistoryLog.capacity)
    }

    // MARK: - PingTrigger (REQ-07)

    /// The rule that keeps an arrival marking alive across a delayed drain: an arrival ping
    /// recorded offline carries `.arrival` immediately, and the delivery update that arrives a
    /// wake later carries no trigger of its own -- without this the drain would quietly erase
    /// REQ-07's marking.
    @Test
    func aDeliveryUpdateWithNoTriggerKeepsTheRowsExistingTrigger() {
        var log = PingHistoryLog()
        let entry = Self.makeEntry(outcome: .queued, trigger: .arrival)
        log.record(entry)

        log.apply(Self.makeUpdate(id: entry.id, outcome: .sent, trigger: nil))

        #expect(log.entries[0].outcome == .sent)
        #expect(log.entries[0].trigger == .arrival)
    }

    @Test
    func aDeliveryUpdateCanSetATriggerOnARowThatHadNone() {
        var log = PingHistoryLog()
        let entry = Self.makeEntry(outcome: .queued, trigger: nil)
        log.record(entry)

        log.apply(Self.makeUpdate(id: entry.id, outcome: .sent, trigger: .geofenceExit))

        #expect(log.entries[0].trigger == .geofenceExit)
    }

    /// Symbol AND word for every case, never one alone (DESIGN.md).
    @Test
    func everyTriggerHasAWordAndASymbol() {
        for trigger in PingTrigger.allCases {
            #expect(!trigger.word.isEmpty)
            #expect(trigger.word == trigger.word.trimmingCharacters(in: .whitespaces))
            #expect(!trigger.symbolName.isEmpty)
        }
    }
}
