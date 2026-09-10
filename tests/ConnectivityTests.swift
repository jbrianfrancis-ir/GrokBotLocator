import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `ConnectivityEdge`'s rising-edge rule for all four transitions plus the cold-start
/// case, with no `NWPathMonitor`, no network, and no waiting -- the whole point of splitting the
/// rule out of `NWPathMonitorConnectivity` (03-03 objective).
@Suite
struct ConnectivityEdgeTests {

    @Test
    func theFirstObservationNeverFiresAnEdge() {
        var startsOnline = ConnectivityEdge()
        #expect(startsOnline.observe(satisfied: true) == false)

        var startsOffline = ConnectivityEdge()
        #expect(startsOffline.observe(satisfied: false) == false)
    }

    @Test
    func onlyTheRisingEdgeFires() {
        var edge = ConnectivityEdge()
        let observations = [false, false, true, true, false, true]
        let fired = observations.map { edge.observe(satisfied: $0) }
        #expect(fired == [false, false, true, false, false, true])
    }

    @Test
    func aStableConnectionNeverRefires() {
        var edge = ConnectivityEdge()
        #expect(edge.observe(satisfied: true) == false)

        for _ in 0..<20 {
            #expect(edge.observe(satisfied: true) == false)
        }
    }

    @Test
    func goingOfflineFiresNothing() {
        var edge = ConnectivityEdge()
        let observations = [false, true, false]
        let fired = observations.map { edge.observe(satisfied: $0) }
        #expect(fired == [false, true, false])
    }

    /// Compile-and-construct check only, not a network assertion -- awaiting the stream would
    /// hang the suite on a simulator with no path change.
    @Test
    func theWrapperConformsToTheProtocol() {
        #expect(NWPathMonitorConnectivity() is any ConnectivityObserving)
    }
}
