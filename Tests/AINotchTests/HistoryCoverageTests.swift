import Foundation
import XCTest
@testable import AINotch

final class HistoryCoverageTests: XCTestCase {
    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private func now(_ calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
    }

    /// The shape of the machine this was found on: two stray sessions from
    /// months ago carrying ~1% of the tokens, then a wall of usage starting at
    /// the 30-day cleanup horizon. The naive "is the oldest record about 30
    /// days old?" test calls this untruncated, which is exactly backwards.
    func testStraySessionsBeforeACliffStillCountAsTruncated() throws {
        let calendar = try utcCalendar()
        let today = try now(calendar)
        let stray = try XCTUnwrap(calendar.date(byAdding: .day, value: -99, to: today))
        let recent = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: today))

        let coverage = try XCTUnwrap(
            HistoryCoverage.evaluate(
                daily: [
                    DailyUsage(day: stray, provider: .codex,
                               tokens: .init(input: 6_000_000), estimatedCost: 1),
                    DailyUsage(day: recent, provider: .claude,
                               tokens: .init(input: 700_000_000), estimatedCost: 100)
                ],
                now: today,
                calendar: calendar
            )
        )

        XCTAssertTrue(coverage.isTruncated)
        XCTAssertLessThan(coverage.shareBeforeCutoff, 0.05)
        XCTAssertEqual(coverage.earliest, stray)
    }

    /// A genuinely deep history must not claim it was truncated.
    func testEvenlySpreadHistoryIsNotReportedAsTruncated() throws {
        let calendar = try utcCalendar()
        let today = try now(calendar)
        let daily = try (0..<120).map { offset -> DailyUsage in
            DailyUsage(
                day: try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today)),
                provider: .claude,
                tokens: .init(input: 1_000_000),
                estimatedCost: 1
            )
        }

        let coverage = try XCTUnwrap(
            HistoryCoverage.evaluate(daily: daily, now: today, calendar: calendar)
        )
        XCTAssertFalse(coverage.isTruncated)
    }

    /// A new install has nothing before the horizon at all — also a truncated
    /// view, for a different reason.
    func testHistoryThatDoesNotReachTheHorizonIsTruncated() throws {
        let calendar = try utcCalendar()
        let today = try now(calendar)
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: today))

        let coverage = try XCTUnwrap(
            HistoryCoverage.evaluate(
                daily: [DailyUsage(day: day, provider: .claude,
                                   tokens: .init(input: 5), estimatedCost: 1)],
                now: today,
                calendar: calendar
            )
        )
        XCTAssertTrue(coverage.isTruncated)
    }

    func testCoverageIsUnavailableWithoutRecordsOrTokens() throws {
        let calendar = try utcCalendar()
        let today = try now(calendar)
        XCTAssertNil(HistoryCoverage.evaluate(daily: [], now: today, calendar: calendar))
        XCTAssertNil(
            HistoryCoverage.evaluate(
                daily: [DailyUsage(day: today, provider: .claude,
                                   tokens: .init(), estimatedCost: 0)],
                now: today,
                calendar: calendar
            )
        )
    }

    /// `earliest` must be the minimum, not merely the first element, so an
    /// unsorted feed cannot mislabel the coverage start date.
    func testEarliestIgnoresInputOrdering() throws {
        let calendar = try utcCalendar()
        let today = try now(calendar)
        let old = try XCTUnwrap(calendar.date(byAdding: .day, value: -60, to: today))

        let coverage = try XCTUnwrap(
            HistoryCoverage.evaluate(
                daily: [
                    DailyUsage(day: today, provider: .claude,
                               tokens: .init(input: 10), estimatedCost: 1),
                    DailyUsage(day: old, provider: .claude,
                               tokens: .init(input: 10), estimatedCost: 1)
                ],
                now: today,
                calendar: calendar
            )
        )
        XCTAssertEqual(coverage.earliest, old)
    }
}
