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
    func replaceRemovesADeliveredEntry() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FilePingQueueStore(directory: directory)
        let first = Self.makeQueuedPing()
        let second = Self.makeQueuedPing()
        let third = Self.makeQueuedPing()
        try await store.append(first)
        try await store.append(second)
        try await store.append(third)

        try await store.replace(with: [first, third])

        let loaded = try await store.load()
        #expect(loaded == [first, third])
        #expect(!loaded.contains { $0.id == second.id })
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
