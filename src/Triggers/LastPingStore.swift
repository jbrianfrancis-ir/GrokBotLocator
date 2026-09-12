import Foundation

/// The second sanctioned coordinate store (D-16, 2026-09-11). D-12 (`PingQueueStore.swift`)
/// reserved that role for the offline queue file alone; D-16 widens it by exactly one more
/// narrow exception, no further, to close REQ-08's cold-relaunch arming gap: with only the
/// geofence trigger enabled, `TriggerCoordinator.reference` is `nil` in a fresh process, and the
/// only other durable record -- the region `CLMonitor` itself holds -- may not have survived
/// (RESEARCH.md Q2's "moderately confident, not Apple-prose-verified" persistence claim, now
/// addressed empirically by Q2's addendum but not ratified as load-bearing). This file is what
/// lets `TriggerCoordinator` recover a reference and re-arm the region without CLMonitor's help.
///
/// D-16's four binding conditions, each pinned by a test in `LastPingStoreTests.swift`:
/// 1. **Exactly ONE coordinate, overwritten in place, never appended.** `save` replaces the
///    whole file with a single `StoredCoordinate` object -- never an array, never a dictionary
///    keyed by anything -- which is what makes "a single overwritten point, not a location
///    history" true by construction rather than by convention.
/// 2. Excluded from backups (`isExcludedFromBackup`), same as the queue.
/// 3. Protection class `.completeUntilFirstUserAuthentication`. A geofence exit fires while the
///    phone is locked in a pocket, which is the entire point of the feature: under complete
///    protection that write would fail on exactly that wake, and the region would never
///    re-register. When D-16 chose this class it was **deliberately weaker** than the queue's
///    then-`.completeFileProtectionUnlessOpen`; phase 03 had shipped the inverse of this bug --
///    a locked device could not open the queue file and the drain reported the pings
///    undeliverable (`PingQueueError.unavailable`). D-21 (2026-09-12) moved the queue to this
///    SAME class for the same reason, so the two stores now match. The trade is stated rather
///    than hidden: this file survives a locked screen, so it is readable after first unlock
///    following boot, not after every lock.
/// 4. Deleted when every trigger is disabled (`TriggerCoordinator.applySettings`) -- if nothing
///    is watching, nothing needs the position, in memory or on disk.
///
/// Two different symbols spell the SAME protection class differently, on purpose, and this file
/// uses both: `Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication` (below, in
/// `writeOptions`) is what `save` passes to `Data.write(to:options:)`; `FileProtectionType
/// .completeUntilFirstUserAuthentication` is the runtime class `FileManager` reports back
/// (`LastPingStoreTests.theLastPingFileCarriesTheStatedProtectionClass`). They are not the same
/// type and are not unified here.
protocol LastPingStoring: Sendable {
    /// The stored coordinate, or `nil` if nothing has ever been saved (or it was cleared).
    /// Non-throwing: a read before first unlock, or any other failure, is indistinguishable from
    /// "nothing saved yet" to every caller on the arming path.
    func load() async -> TriggerCoordinate?
    /// Overwrites the stored coordinate in place. Non-throwing: a failed reference write must
    /// never fail a ping that already succeeded.
    func save(_ coordinate: TriggerCoordinate) async
    /// Removes the stored coordinate, if any (D-16 condition 4).
    func clear() async
}

/// `FilePingQueueStore`-shaped: an `actor` over one file under Application Support, modelled on
/// `PingQueueStore.swift:118-245`. The wire shape is this store's own -- a private
/// `StoredCoordinate`, not `TriggerCoordinate` itself, which stays free of `Codable` so
/// `DisplacementGate.swift` carries no notion that anything persists it.
actor FileLastPingStore: LastPingStoring {
    private struct StoredCoordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    private static let fileName = "LastPing.json"

    /// Pinned as a named seam, not an inline literal at the call site, so a test can assert
    /// against the SAME symbol `save` actually uses (`LastPingStoreTests` and this plan's verify
    /// both key off `Self.writeOptions`). `.completeFileProtectionUntilFirstUserAuthentication`
    /// is the `Data.WritingOptions` spelling of condition 3 above -- see this file's header for
    /// why this class, and why the queue (D-21) now shares it.
    static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication,
    ]

    private let directory: URL

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    /// The injectable directory is what makes every case here testable against a throwaway
    /// directory, never against the app's real Application Support.
    init(directory: URL) {
        self.directory = directory
    }

    /// The app's real store location, mirroring `FilePingQueueStore.applicationSupport()`.
    static func applicationSupport() throws -> FileLastPingStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileLastPingStore(directory: directory)
    }

    func load() async -> TriggerCoordinate? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredCoordinate.self, from: data) else {
            return nil
        }
        return TriggerCoordinate(latitude: stored.latitude, longitude: stored.longitude)
    }

    /// The ONE place this file is ever written. Both protections are reasserted on EVERY call,
    /// for the same reason `FilePingQueueStore.write(_:)` does: an atomic replace recreates the
    /// file, and a recreated file does not inherit the previous file's resource values.
    func save(_ coordinate: TriggerCoordinate) async {
        let stored = StoredCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL, options: Self.writeOptions)) != nil else { return }

        var excludedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedURL.setResourceValues(resourceValues)
    }

    func clear() async {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// In-memory conformer for tests -- `internal`, not `private`, so `TriggerCoordinatorTests.swift`
/// (Task 3) reuses the same fake rather than declaring a second one. Every mutation genuinely
/// suspends first: LEARNINGS records that a fake returning without suspending cannot test an
/// actor's reentrancy, which is exactly what this store's callers (`TriggerCoordinator`) rely on
/// being safe across concurrent wakes.
actor InMemoryLastPingStore: LastPingStoring {
    private var coordinate: TriggerCoordinate?

    func load() async -> TriggerCoordinate? {
        await Task.yield()
        return coordinate
    }

    func save(_ coordinate: TriggerCoordinate) async {
        await Task.yield()
        self.coordinate = coordinate
    }

    func clear() async {
        await Task.yield()
        coordinate = nil
    }
}
