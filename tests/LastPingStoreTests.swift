import Foundation
import Testing
@testable import GrokBotLocator

/// Exercises `FileLastPingStore` through a real file on disk, pinning each of D-16's four
/// binding conditions with a test that reads the real file rather than trusting the type's own
/// claim about itself -- the same discipline `PingQueueStoreTests.swift` uses for D-12. Every
/// test builds its own throwaway directory under the system temp directory, exactly as
/// `PingQueueStoreTests.throwawayDirectory()` does, and removes it when done.
@Suite
struct LastPingStoreTests {

    private static func throwawayDirectory() -> (directory: URL, teardown: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("test." + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, { try? FileManager.default.removeItem(at: directory) })
    }

    private static func coordinate(_ n: Double) -> TriggerCoordinate {
        TriggerCoordinate(latitude: 40.0559 + n, longitude: 17.9925)
    }

    @Test
    func loadOnAFreshStoreIsNil() async {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FileLastPingStore(directory: directory)
        #expect(await store.load() == nil)
    }

    /// D-16 condition 1: exactly ONE coordinate, overwritten in place, never appended. Saving
    /// twice must leave `load()` reading the SECOND coordinate, and the raw bytes on disk must be
    /// a single JSON object -- never an array, which is what a location HISTORY would look like.
    @Test
    func savingTwiceOverwritesAndNeverAppends() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FileLastPingStore(directory: directory)
        let a = Self.coordinate(1)
        let b = Self.coordinate(2)
        await store.save(a)
        await store.save(b)

        #expect(await store.load() == b)

        let fileURL = directory.appendingPathComponent("LastPing.json")
        let bytes = try Data(contentsOf: fileURL)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.hasPrefix("{"), "a single overwritten point is a JSON object, never a list")
        #expect(!text.contains("["), "condition 1: never an array -- a list of points is a location history")
    }

    /// D-16 condition 2, the same read-back-off-the-real-file discipline
    /// `PingQueueStoreTests.theQueueFileIsExcludedFromBackup` uses for the queue.
    @Test
    func theLastPingFileIsExcludedFromBackup() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FileLastPingStore(directory: directory)
        await store.save(Self.coordinate(1))

        let fileURL = directory.appendingPathComponent("LastPing.json")
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(resourceValues.isExcludedFromBackup == true)
    }

    /// D-16 condition 3. The simulator does not always surface a written file's runtime
    /// protection class back through `attributesOfItem(atPath:)` -- measured here against a
    /// CONTROL (the same directory's own throwaway file, written with no protection option at
    /// all) before trusting a nil reading on `LastPing.json` as meaningful. If the control ALSO
    /// reports nil, the runtime attribute is not observable in this environment, and the test
    /// falls back to asserting the named seam `save` actually uses (`Self.writeOptions`) rather
    /// than asserting nothing -- the on-device reading is Task 4's human check instead.
    @Test
    func theLastPingFileCarriesTheStatedProtectionClass() async throws {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FileLastPingStore(directory: directory)
        await store.save(Self.coordinate(1))
        let fileURL = directory.appendingPathComponent("LastPing.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let protectionClass = attributes[.protectionKey] as? FileProtectionType

        let controlURL = directory.appendingPathComponent("control.txt")
        try Data("control".utf8).write(to: controlURL)
        let controlAttributes = try FileManager.default.attributesOfItem(atPath: controlURL.path)
        let controlReportsAClass = (controlAttributes[.protectionKey] as? FileProtectionType) != nil

        if protectionClass == nil, !controlReportsAClass {
            // The runtime attribute is unreadable on this simulator (the control, written with
            // no protection option at all, ALSO reports nil) -- assert the seam `save` actually
            // passes to `Data.write(to:options:)` instead of asserting nothing.
            #expect(
                FileLastPingStore.writeOptions.contains(
                    .completeFileProtectionUntilFirstUserAuthentication))
        } else {
            #expect(protectionClass == .completeUntilFirstUserAuthentication)
        }
    }

    /// D-16 condition 4's mechanism at the store level: `clear()` removes the file outright, not
    /// merely empties it.
    @Test
    func clearRemovesTheFile() async {
        let (directory, teardown) = Self.throwawayDirectory()
        defer { teardown() }

        let store = FileLastPingStore(directory: directory)
        await store.save(Self.coordinate(1))
        let fileURL = directory.appendingPathComponent("LastPing.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        await store.clear()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(await store.load() == nil)
    }
}
