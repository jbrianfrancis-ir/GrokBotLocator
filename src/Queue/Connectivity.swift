import Foundation
import Network

/// The rule for exactly one thing: did the network just become reachable. A pure value type on
/// purpose -- REQ-05 names "connectivity returning while it is alive" as a drain opportunity, and
/// the only way to prove all four transitions (offline->online, online->online, online->offline,
/// offline->offline) without a simulator or a real `NWPathMonitor` is to keep the decision out of
/// any type that touches `Network`.
///
/// `lastSatisfied` starts `nil` rather than `false` so the very first observation is
/// distinguishable from "we were offline and now we're online": the first reading is just the
/// state the app launched in, already handled by the launcher's own drain, and firing an edge for
/// it here would double-drain every cold start (ARCHITECTURE's launch-time drain is a separate,
/// already-covered path).
struct ConnectivityEdge: Sendable, Equatable {
    private var lastSatisfied: Bool?

    /// Returns true only on a rising edge -- the previous observation was `false` and this one is
    /// `true`. `nil -> true` (first observation, any value) returns false; `true -> true`,
    /// `false -> false`, and `true -> false` all return false. Every branch updates
    /// `lastSatisfied` regardless of the return value, so the next call always compares against
    /// what was just observed.
    mutating func observe(satisfied: Bool) -> Bool {
        let firedEdge = lastSatisfied == false && satisfied
        lastSatisfied = satisfied
        return firedEdge
    }
}

/// A stream of rising edges -- exactly one `Void` yield per offline->online transition, never one
/// for the first observation or for going offline. A protocol, not a concrete type, so the drain
/// coordinator (03-10) depends on this shape and is tested against a fake stream a test drives by
/// hand, never against a real `NWPathMonitor`.
protocol ConnectivityObserving: Sendable {
    func onlineEdges() -> AsyncStream<Void>
}

/// The only type in the app that imports `Network`. Feeds every path update through a
/// `ConnectivityEdge` and yields on the stream exactly when that rule fires -- no logic of its
/// own, no `Task.sleep`, no timer, no retry: this file reports transitions and nothing else.
///
/// `pathUpdateHandler` runs on `monitorQueue`, while `onTermination` runs on whatever queue
/// cancels the stream -- not necessarily the same one. That is two concurrent writers to the
/// same `ConnectivityEdge`, so it is lock-guarded here rather than left `nonisolated(unsafe)`.
/// LEARNINGS.md: a fake with the same two-writer shape but no lock hung phase 02's suite
/// intermittently -- the fix there was a lock, not fewer writers, and the same fix applies here.
final class NWPathMonitorConnectivity: ConnectivityObserving, @unchecked Sendable {
    private let monitorQueue = DispatchQueue(label: "connectivity")

    /// A `let`-captured box around the mutable `ConnectivityEdge`, rather than a `var` captured
    /// directly by `pathUpdateHandler`: Swift 6 strict concurrency refuses to let an escaping
    /// closure mutate a captured local `var` (it cannot see that the lock serializes every
    /// access), so the var and its lock both live inside this `@unchecked Sendable` box instead.
    private final class LockedEdge: @unchecked Sendable {
        private let lock = NSLock()
        private var edge = ConnectivityEdge()

        func observe(satisfied: Bool) -> Bool {
            lock.withLock { edge.observe(satisfied: satisfied) }
        }
    }

    func onlineEdges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let lockedEdge = LockedEdge()

            monitor.pathUpdateHandler = { path in
                let satisfied = path.status == .satisfied
                if lockedEdge.observe(satisfied: satisfied) {
                    continuation.yield()
                }
            }

            continuation.onTermination = { _ in
                monitor.cancel()
            }

            monitor.start(queue: monitorQueue)
        }
    }
}
