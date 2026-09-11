import BackgroundTasks
import Foundation
import Testing
@testable import GrokBotLocator

/// Proves the empty-identifier truth `QueueDrainTask`'s doc comment describes: an empty
/// identifier produces NO refresh request, so nothing is ever submitted under a guessed
/// string. Without this test that claim rests on reading the source; `#require` below makes it
/// checkable.
@Suite
struct QueueDrainTaskTests {
    @Test
    func anEmptyIdentifierProducesNoRefreshRequest() {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        #expect(QueueDrainTask.request(identifier: "", from: fixedNow) == nil)
    }

    @Test
    func aRealIdentifierProducesARequestFifteenMinutesOut() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let request = try #require(
            QueueDrainTask.request(identifier: "com.example.GrokBotLocator.queue-drain", from: fixedNow))
        #expect(request.identifier == "com.example.GrokBotLocator.queue-drain")
        #expect(request.earliestBeginDate == fixedNow.addingTimeInterval(15 * 60))
    }
}
