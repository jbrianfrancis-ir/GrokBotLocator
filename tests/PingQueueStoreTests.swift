import Foundation
import Testing
@testable import GrokBotLocator

/// Exercises `FilePingQueueStore` through a real file on disk -- durability across a fresh store
/// instance, the delivered-entry removal `replace` performs, the capacity refusal, and the
/// unreadable-file set-aside path -- never against the app's real Application Support queue.
/// Every test builds its own throwaway directory under the system temp directory and removes it
/// when done, exactly as `PingHistoryTests` builds a throwaway `UserDefaults` suite. Synthetic
/// coordinates only.
@Suite
struct PingQueueStoreTests {

    /// Builds a fresh directory under the system temp directory and returns it alongside a
    /// teardown closure -- callers `defer { teardown() }` so a failed assertion still cleans up.
    private static func throwawayDirectory() -> (directory: URL, teardown: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("test." + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, { try? FileManager.default.removeItem(at: directory) })
    }

    private static func makeQueuedPing(
        id: UUID = UUID(),
        firstAttemptAt: Date = Date(),
        attemptsMade: Int = 0,
        nextAttemptAt: Date = Date(),
        permanentFailure: String? = nil
    ) -> QueuedPing {
        QueuedPing(
            id: id,
            payload: PingPayload(
                latitude: 40.77465,
                longitude: 17.23107,
                accuracyMetres: 5.0,
                label: "Test ping",
                capturedAt: Date()
            ),
            firstAttemptAt: firstAttemptAt,
            attemptsMade: attemptsMade,
            nextAttemptAt: nextAttemptAt,
            permanentFailure: permanentFailure
        )
    }

    /// The force-quit-and-relaunch case: a SECOND, independently-constructed store over the
    /// SAME directory must read back what the first one wrote, `payload.capturedAt` included.
    @Test
    func aQueuedPingSurvivesAFreshStoreOverTheSameDirectory() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let ping = Self.makeQueuedPing()
        let writer = FilePingQueueStore(directory: directory)
        try await writer.append(ping)

        let reader = FilePingQueueStore(directory: directory)
        let loaded = try await reader.load()

        #expect(loaded == [ping])
    }

    @Test
    func theQueueFileIsExcludedFromBackup() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        try await store.append(Self.makeQueuedPing())

        let fileURL = directory.appendingPathComponent("PingQueue.json")
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(resourceValues.isExcludedFromBackup == true)
    }

    @Test
    func applyRemovesADeliveredEntryAndLeavesTheRestAlone() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let first = Self.makeQueuedPing()
        let second = Self.makeQueuedPing()
        let third = Self.makeQueuedPing()
        try await store.append(first)
        try await store.append(second)
        try await store.append(third)

        try await store.apply(removing: [second.id], updating: [])

        let loaded = try await store.load()
        #expect(loaded == [first, third])
        #expect(!loaded.contains { $0.id == second.id })
    }

    /// `apply` merges against what is on disk NOW, which is the whole point of it: an entry that
    /// appeared after the caller took its snapshot must survive the caller's write. This is the
    /// store-level half of `aPingQueuedDuringADrainIsNotErasedByTheRewrite`.
    @Test
    func applyPreservesAnEntryTheCallerNeverSaw() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let known = Self.makeQueuedPing()
        try await store.append(known)

        // Appears after a caller would have loaded [known] -- the drain's exact situation.
        let late = Self.makeQueuedPing()
        try await store.append(late)

        try await store.apply(removing: [known.id], updating: [])

        let loaded = try await store.load()
        #expect(loaded.map(\.id) == [late.id], "an entry the caller never saw must not be erased")
    }

    /// An id in `updating` replaces in place rather than appending, and an id in BOTH lists is
    /// removed -- removal wins, so a delivered entry can never be resurrected by a stale update.
    @Test
    func applyReplacesInPlaceAndLetsRemovalWin() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let entry = Self.makeQueuedPing(attemptsMade: 1)
        let other = Self.makeQueuedPing()
        try await store.append(entry)
        try await store.append(other)

        var bumped = entry
        bumped.attemptsMade = 4
        try await store.apply(removing: [], updating: [bumped])
        var loaded = try await store.load()
        #expect(loaded.count == 2, "an update must replace, never append")
        #expect(loaded.first { $0.id == entry.id }?.attemptsMade == 4)

        try await store.apply(removing: [other.id], updating: [other])
        loaded = try await store.load()
        #expect(!loaded.contains { $0.id == other.id }, "removal must win over a same-id update")
    }

    /// Filling the queue and appending once more costs the NEW ping, never an existing one --
    /// the oldest entry is still present afterwards.
    @Test
    func appendRefusesWhenTheQueueIsFull() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let pings = (0..<FilePingQueueStore.capacity).map { _ in Self.makeQueuedPing() }
        for ping in pings {
            try await store.append(ping)
        }

        await #expect(throws: PingQueueError.full) {
            try await store.append(Self.makeQueuedPing())
        }

        let loaded = try await store.load()
        #expect(loaded.count == FilePingQueueStore.capacity)
        #expect(loaded.first?.id == pings.first?.id)
    }

    /// The failure this separates from corruption, found by the security lens at PR review.
    ///
    /// A data-protected file cannot be opened while it is sealed — under D-21's
    /// `.completeFileProtectionUntilFirstUserAuthentication` that is a background wake between a
    /// restart and the first unlock; under the earlier `.completeFileProtectionUnlessOpen` it was
    /// EVERY locked wake, and `BGAppRefreshTask` fires exactly then. The read and the decode once
    /// shared one `catch`, so a locked-device read renamed the ENTIRE pending queue to
    /// `PingQueue-unreadable.json` and told the user the pings "cannot be delivered": SC-02's one
    /// promise broken by the durability mechanism, because the phone was in a pocket.
    ///
    /// `chmod 000` stands in for the sealed-file read here — the simulator does not enforce data
    /// protection, so an unreadable-by-permissions file is the honest local analogue of an
    /// unreadable-by-encryption one. What is pinned is the BRANCH: a read that fails must throw
    /// `.unavailable`, move nothing, and leave the queue exactly where it was.
    /// D-21 (2026-09-12): the queue must be writable and readable from a locked pocket, because
    /// that is where every automatic trigger fires. `.completeFileProtectionUnlessOpen` sealed the
    /// file on every lock, so a send that failed offline could not be queued and was dropped, and
    /// every background drain gave up. The class is now `.completeFileProtectionUntilFirstUser
    /// Authentication`, the same one `FileLastPingStore` uses (D-16), pinned here the same way
    /// `LastPingStoreTests.theLastPingFileCarriesTheStatedProtectionClass` pins that one: read the
    /// runtime attribute back when the simulator surfaces it (checked against a CONTROL file
    /// written with no protection option), otherwise assert the named seam `write` actually uses.
    /// Both branches also assert the OLD class is gone — a regression to it would ship green
    /// under a contains-only check.
    @Test
    func theQueueFileCarriesTheStatedProtectionClass() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        try await store.append(Self.makeQueuedPing())
        let fileURL = directory.appendingPathComponent("PingQueue.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let protectionClass = attributes[.protectionKey] as? FileProtectionType

        let controlURL = directory.appendingPathComponent("control.txt")
        try Data("control".utf8).write(to: controlURL)
        let controlAttributes = try FileManager.default.attributesOfItem(atPath: controlURL.path)
        let controlReportsAClass = (controlAttributes[.protectionKey] as? FileProtectionType) != nil

        #expect(
            FilePingQueueStore.writeOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication))
        #expect(!FilePingQueueStore.writeOptions.contains(.completeFileProtectionUnlessOpen))
        #expect(!FilePingQueueStore.writeOptions.contains(.completeFileProtection))

        if protectionClass != nil || controlReportsAClass {
            #expect(protectionClass == .completeUntilFirstUserAuthentication)
        }
    }

    @Test
    func aFileThatCannotBeReadIsNotTreatedAsCorruptAndIsLeftAlone() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let fileURL = directory.appendingPathComponent("PingQueue.json")
        let store = FilePingQueueStore(directory: directory)
        try await store.append(Self.makeQueuedPing())
        let bytesBefore = try Data(contentsOf: fileURL)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        await #expect(throws: PingQueueError.unavailable) {
            try await store.load()
        }

        // The queue is still there, byte for byte, and nothing was set aside.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        #expect(try Data(contentsOf: fileURL) == bytesBefore)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("PingQueue-unreadable.json").path))
        #expect(try await store.load().count == 1)
    }

    @Test
    func anUnreadableFileIsSetAsideAndReported() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let fileURL = directory.appendingPathComponent("PingQueue.json")
        let corruptBytes = Data("{ not json".utf8)
        try corruptBytes.write(to: fileURL)

        let store = FilePingQueueStore(directory: directory)
        await #expect(throws: PingQueueError.unreadable) {
            try await store.load()
        }

        let setAsideURL = directory.appendingPathComponent("PingQueue-unreadable.json")
        #expect(FileManager.default.fileExists(atPath: setAsideURL.path))
        let setAsideBytes = try Data(contentsOf: setAsideURL)
        #expect(setAsideBytes == corruptBytes)

        let ping = Self.makeQueuedPing()
        try await store.append(ping)
        let loaded = try await store.load()
        #expect(loaded == [ping])
    }

    /// The backstop truth's mechanism: a finished `permanentFailure` sentence survives the
    /// round trip through the file, not just through memory.
    @Test
    func aPermanentlyFailedEntryIsStillReadBack() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let ping = Self.makeQueuedPing(
            permanentFailure: "This ping could not be delivered after a week of retries."
        )
        try await store.append(ping)

        let loaded = try await store.load()
        #expect(loaded.first?.permanentFailure == "This ping could not be delivered after a week of retries.")
    }
}
