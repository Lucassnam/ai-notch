import Foundation
import XCTest
@testable import AINotch

final class UsageAggregatorTests: XCTestCase {
    func testAggregatorSeparatesFiveHourWeekAndMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-11T22:00:00Z")!
        let recent = now.addingTimeInterval(-60 * 60)
        let old = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let events = [
            UsageEvent(
                id: "recent",
                provider: .claude,
                timestamp: recent,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 1_000_000, output: 100_000)
            ),
            UsageEvent(
                id: "old",
                provider: .claude,
                timestamp: old,
                model: "claude-opus-4-8",
                tokens: TokenBreakdown(input: 1_000_000, output: 100_000)
            )
        ]
        let raw = RawTelemetry(events: events, limits: [], sourceFiles: [.claude: 2])
        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingCatalog(pricingDate: now)
        ).snapshot(from: raw, now: now)
        let claude = try XCTUnwrap(snapshot.providers.first { $0.provider == .claude })

        XCTAssertEqual(claude.lastFiveHours.requestCount, 1)
        XCTAssertEqual(claude.week.requestCount, 1)
        XCTAssertEqual(claude.month.requestCount, 2)
        XCTAssertEqual(claude.allTime.requestCount, 2)
        XCTAssertEqual(claude.allTime.tokens.total, 2_200_000)
        XCTAssertEqual(snapshot.lastThirtyDays.requestCount, 2)
        XCTAssertEqual(snapshot.lastThirtyDays.tokens.total, 2_200_000)
        XCTAssertEqual(claude.sourceFileCount, 2)
        XCTAssertEqual(claude.lastFiveHours.estimatedCost, 7.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.todayModels.first?.tokens.total, 1_100_000)
        XCTAssertEqual(snapshot.weekModels.first?.tokens.total, 1_100_000)
        XCTAssertEqual(snapshot.allTimeModels.count, 2)
        XCTAssertEqual(snapshot.thirtyDayModels.count, 2)
        XCTAssertEqual(
            snapshot.allTimeModels.first(where: { $0.model == "claude-opus-4-8" })?.tokens.total,
            1_100_000
        )
    }

    func testThirtyDayRangeIncludesTodayAndPreviousTwentyNineDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-11T22:00:00Z")!
        let startOfToday = calendar.startOfDay(for: now)
        let events = [
            UsageEvent(
                id: "day-29",
                provider: .claude,
                timestamp: calendar.date(byAdding: .day, value: -29, to: startOfToday)!,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 100)
            ),
            UsageEvent(
                id: "day-30",
                provider: .claude,
                timestamp: calendar.date(byAdding: .day, value: -30, to: startOfToday)!,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 1_000)
            )
        ]
        let snapshot = UsageAggregator(calendar: calendar).snapshot(
            from: RawTelemetry(events: events, limits: [], sourceFiles: [:]),
            now: now
        )

        XCTAssertEqual(snapshot.lastThirtyDays.requestCount, 1)
        XCTAssertEqual(snapshot.lastThirtyDays.tokens.total, 100)
        XCTAssertEqual(snapshot.thirtyDayModels.first?.tokens.total, 100)
    }

    func testPricingDiscountsCachedInput() {
        let price = PricingCatalog().price(provider: .codex, model: "gpt-5.6-sol")
        let cost = price.cost(
            for: TokenBreakdown(
                input: 1_000_000,
                output: 1_000_000,
                cacheRead: 1_000_000,
                cacheWrite5m: 1_000_000
            )
        )

        XCTAssertEqual(cost, 41.75, accuracy: 0.0001)
    }

    func testAggregatorUsesCostCapturedByDurableHistory() throws {
        let now = Date()
        let event = UsageEvent(
            id: "captured-price",
            provider: .claude,
            timestamp: now.addingTimeInterval(-60),
            model: "claude-opus-5",
            tokens: TokenBreakdown(input: 1_000_000)
        )
        let raw = RawTelemetry(
            events: [event],
            limits: [],
            sourceFiles: [.claude: 1],
            recordedCosts: [event.id: 123.45]
        )
        let snapshot = UsageAggregator().snapshot(from: raw, now: now)
        let claude = try XCTUnwrap(snapshot.providers.first { $0.provider == .claude })

        XCTAssertEqual(claude.today.estimatedCost, 123.45, accuracy: 0.0001)
        XCTAssertEqual(snapshot.todayModels.first?.estimatedCost, 123.45)
    }

    func testAggregatorDoesNotPreferAStaleFiveHourLimitOverCurrentWeeklyLimit() throws {
        let now = Date()
        let limits = [
            RateLimitWindow(
                id: "old-five-hour",
                provider: .codex,
                windowMinutes: 300,
                usedPercent: 80,
                resetsAt: nil,
                observedAt: now.addingTimeInterval(-24 * 60 * 60),
                source: "test"
            ),
            RateLimitWindow(
                id: "current-weekly",
                provider: .codex,
                windowMinutes: 10_080,
                usedPercent: 4,
                resetsAt: nil,
                observedAt: now,
                source: "test"
            )
        ]
        let raw = RawTelemetry(events: [], limits: limits, sourceFiles: [:])
        let snapshot = UsageAggregator().snapshot(from: raw, now: now)
        let codex = try XCTUnwrap(snapshot.providers.first { $0.provider == .codex })

        XCTAssertEqual(codex.currentLimit?.windowMinutes, 10_080)
        XCTAssertEqual(codex.currentLimit?.remainingPercent, 96)
    }

    func testLimitPastItsResetReadsAsFull() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let stale = RateLimitWindow(
            id: "five-hour",
            provider: .codex,
            windowMinutes: 300,
            usedPercent: 88,
            resetsAt: now.addingTimeInterval(-60),
            observedAt: now.addingTimeInterval(-4 * 60 * 60),
            source: "test"
        )
        let raw = RawTelemetry(events: [], limits: [stale], sourceFiles: [:])
        let snapshot = UsageAggregator().snapshot(from: raw, now: now)
        let codex = try XCTUnwrap(snapshot.providers.first { $0.provider == .codex })

        XCTAssertEqual(codex.currentLimit?.remainingPercent, 100)
        XCTAssertEqual(AIFormat.reset(stale.resetsAt, now: now), "Reset, unused since")
    }
}
