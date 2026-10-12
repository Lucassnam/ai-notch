import Foundation
import XCTest
@testable import AINotch

final class UsageHistoryStoreTests: XCTestCase {
    func testHistorySurvivesMissingSourceAndKeepsOriginalPrice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AINotchHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("usage-history.json")
        let event = UsageEvent(
            id: "historical-sonnet",
            provider: .claude,
            timestamp: Date(timeIntervalSince1970: 1_786_000_000),
            model: "claude-sonnet-5",
            tokens: TokenBreakdown(input: 1_000_000)
        )
        let launchPricingDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 11)
        )!
        var firstRun = UsageHistoryStore(
            historyURL: historyURL,
            pricing: PricingCatalog(pricingDate: launchPricingDate)
        )
        let first = try firstRun.merge(liveEvents: [event])

        XCTAssertEqual(try XCTUnwrap(first.recordedCosts[event.id]), 2, accuracy: 0.0001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))

        let laterPricingDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 10, day: 1)
        )!
        var laterRun = UsageHistoryStore(
            historyURL: historyURL,
            pricing: PricingCatalog(pricingDate: laterPricingDate)
        )
        let restored = try laterRun.merge(liveEvents: [])

        XCTAssertEqual(restored.events, [event])
        XCTAssertEqual(try XCTUnwrap(restored.recordedCosts[event.id]), 2, accuracy: 0.0001)
    }

    func testScannerReturnsDurableEventsAfterSourceFileIsDeleted() async throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("AINotchScannerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/test", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appendingPathComponent("session.jsonl")
        let line = #"{"type":"assistant","requestId":"durable-request","timestamp":"2026-08-11T20:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":0}}}"#
        try Data("\(line)\n".utf8).write(to: source)
        let support = home.appendingPathComponent("support", isDirectory: true)
        let cacheURL = support.appendingPathComponent("cache.json")
        let historyURL = support.appendingPathComponent("history.json")

        let firstScanner = TelemetryScanner(
            homeDirectory: home,
            cacheURL: cacheURL,
            historyURL: historyURL
        )
        let first = try await firstScanner.scan()
        XCTAssertEqual(first.events.count, 1)
        XCTAssertNotNil(first.recordedCosts["claude:durable-request"])

        try fileManager.removeItem(at: source)
        let restartedScanner = TelemetryScanner(
            homeDirectory: home,
            cacheURL: cacheURL,
            historyURL: historyURL
        )
        let restored = try await restartedScanner.scan()

        XCTAssertEqual(restored.events.count, 1)
        XCTAssertEqual(restored.events.first?.id, "claude:durable-request")
        XCTAssertEqual(restored.sourceFiles[.claude], 0)
    }

    func testGrowingEventPreservesPreviouslyCapturedPrice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AINotchGrowingHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("usage-history.json")
        let event = UsageEvent(
            id: "growing-event",
            provider: .claude,
            timestamp: Date(),
            model: "claude-sonnet-5",
            tokens: TokenBreakdown(input: 1_000_000)
        )
        let launchPricingDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 11)
        )!
        var firstRun = UsageHistoryStore(
            historyURL: historyURL,
            pricing: PricingCatalog(pricingDate: launchPricingDate)
        )
        _ = try firstRun.merge(liveEvents: [event])

        let grownEvent = UsageEvent(
            id: event.id,
            provider: event.provider,
            timestamp: event.timestamp,
            model: event.model,
            tokens: TokenBreakdown(input: 2_000_000)
        )
        let laterPricingDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 10, day: 1)
        )!
        var laterRun = UsageHistoryStore(
            historyURL: historyURL,
            pricing: PricingCatalog(pricingDate: laterPricingDate)
        )
        let result = try laterRun.merge(liveEvents: [grownEvent])

        // The first million stays at $2; only the added million uses the later $3 price.
        XCTAssertEqual(try XCTUnwrap(result.recordedCosts[event.id]), 5, accuracy: 0.0001)
    }
}
