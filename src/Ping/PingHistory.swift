import Foundation

/// Phase 01 declared `PingOutcome` without `Equatable`; the history tests below compare
/// outcomes, so the conformance is added here rather than widening phase 01's file.
extension PingOutcome: Equatable {}

/// One row of REQ-04's ping history: every column the screen lists, plus the `reason` a
/// `.failed` row needs and a `.sent` row never carries. In memory only -- no `Codable` and no
/// persistence of any kind. ARCHITECTURE forbids storing or logging raw coordinates, so this
/// log is deliberately session-only: it never survives to be written anywhere that forbidden
/// rule would reach. Phase 03 adds the durable, on-disk queue for sends themselves; this type
/// is unrelated to that queue.
struct PingHistoryEntry: Sendable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let label: String
    let outcome: PingOutcome
    let reason: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        label: String,
        outcome: PingOutcome,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.outcome = outcome
        self.reason = reason
    }
}

/// The in-memory, newest-first, capped log the history screen renders. No formatting --
/// `PingOutcomeRow` already owns presentation -- and no durable storage of any kind.
struct PingHistoryLog: Sendable, Equatable {
    static let capacity = 50

    private(set) var entries: [PingHistoryEntry] = []

    /// Inserts at the front and drops anything past `capacity` off the end, so the log is
    /// always newest-first and never grows without bound.
    mutating func record(_ entry: PingHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }
}
