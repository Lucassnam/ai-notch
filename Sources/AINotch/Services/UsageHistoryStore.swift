import Foundation

struct UsageHistoryStore {
    struct Envelope: Codable, Sendable {
        let version: Int
        var records: [String: DurableUsageRecord]
    }

    struct Snapshot: Sendable {
        let events: [UsageEvent]
        let recordedCosts: [String: Double]
    }

    private let fileManager: FileManager
    private let historyURL: URL
    private let pricing: PricingCatalog
    private var envelope = Envelope(version: 1, records: [:])
    private var hasLoaded = false

    init(
        historyURL: URL,
        pricing: PricingCatalog = .init(),
        fileManager: FileManager = .default
    ) {
        self.historyURL = historyURL
        self.pricing = pricing
        self.fileManager = fileManager
    }

    mutating func merge(liveEvents: [UsageEvent], recordedAt: Date = Date()) throws -> Snapshot {
        try loadIfNeeded()
        var changed = false

        for event in liveEvents {
            let estimatedCost: Double
            if let existing = envelope.records[event.id] {
                // Claude can emit the same request repeatedly while it is still
                // growing. Replace it only with an equally complete or larger
                // record; otherwise a truncated source file could shrink history.
                guard event != existing.event, event.tokens.total >= existing.event.tokens.total else {
                    continue
                }
                let addedTokens = event.tokens - existing.event.tokens
                estimatedCost = existing.estimatedCost
                    + pricing.price(provider: event.provider, model: event.model).cost(for: addedTokens)
            } else {
                estimatedCost = pricing.estimatedCost(for: event)
            }

            envelope.records[event.id] = DurableUsageRecord(
                event: event,
                estimatedCost: estimatedCost,
                recordedAt: recordedAt
            )
            changed = true
        }

        if changed {
            try persist()
        }

        let records = Array(envelope.records.values)
        return Snapshot(
            events: records.map(\.event),
            recordedCosts: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.estimatedCost) })
        )
    }

    private mutating func loadIfNeeded() throws {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard fileManager.fileExists(atPath: historyURL.path) else { return }

        let data = try Data(contentsOf: historyURL)
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        guard decoded.version == envelope.version else {
            throw CocoaError(.fileReadCorruptFile)
        }
        envelope = decoded
    }

    private func persist() throws {
        let directory = historyURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: historyURL, options: .atomic)
    }
}
