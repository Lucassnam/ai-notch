import XCTest
@testable import AINotch

final class UsageHeatmapTests: XCTestCase {
    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        return calendar
    }

    private func day(_ calendar: Calendar, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
    }

    func testGraphOffersBarsAndHeatmap() {
        XCTAssertEqual(UsageGraphStyle.allCases, [.bars, .heatmap])
    }

    func testWeekIsOneRowOfSevenDaysEndingToday() throws {
        let calendar = try calendar()
        let end = try day(calendar, 10, 16)
        let grid = UsageHeatmap.grid(
            from: [],
            metric: .money,
            range: .week,
            endingOn: end,
            calendar: calendar
        )
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.columns.count, 7)
        XCTAssertEqual(grid.cells.last?.day, end)
        XCTAssertTrue(grid.cells.allSatisfy { $0.level == 0 })
    }

    /// Weeks are columns starting on the calendar's first weekday; slots
    /// before the range and after today stay empty instead of reading as idle.
    func testThirtyDaysLaysOutWeeksAsColumns() throws {
        let calendar = try calendar()
        let end = try day(calendar, 10, 16) // a Friday
        let grid = UsageHeatmap.grid(
            from: [],
            metric: .money,
            range: .thirtyDays,
            endingOn: end,
            calendar: calendar
        )
        XCTAssertEqual(grid.rows, 7)
        XCTAssertEqual(grid.cells.count, 30)
        XCTAssertTrue(grid.columns.allSatisfy { $0.count == 7 })
        // Friday is row 5 of a Sunday-first week; Saturday after it is empty.
        XCTAssertEqual(grid.columns.last?[5]?.day, end)
        XCTAssertNil(grid.columns.last?[6] ?? nil)
    }

    func testDaysSumBothProvidersAndFollowTheMeasure() throws {
        let calendar = try calendar()
        let end = try day(calendar, 10, 16)
        let daily = [
            DailyUsage(day: end, provider: .claude, tokens: .init(input: 100), estimatedCost: 2),
            DailyUsage(day: end, provider: .codex, tokens: .init(input: 50), estimatedCost: 1)
        ]
        let money = UsageHeatmap.grid(from: daily, metric: .money, range: .week, endingOn: end, calendar: calendar)
        let tokens = UsageHeatmap.grid(from: daily, metric: .tokens, range: .week, endingOn: end, calendar: calendar)
        XCTAssertEqual(money.cells.last?.value ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(tokens.cells.last?.value ?? 0, 150, accuracy: 0.001)
    }

    /// One huge day must not flatten everything else to the faintest shade.
    func testLevelsAreQuartilesOfActiveDays() {
        let values: [Double] = [1, 2, 3, 4, 5, 6, 7, 500]
        let thresholds = UsageHeatmap.quartiles(values)
        XCTAssertEqual(UsageHeatmap.level(0, thresholds), 0)
        XCTAssertEqual(UsageHeatmap.level(1, thresholds), 1)
        XCTAssertEqual(UsageHeatmap.level(3, thresholds), 2)
        XCTAssertEqual(UsageHeatmap.level(5, thresholds), 3)
        XCTAssertEqual(UsageHeatmap.level(500, thresholds), 4)
        XCTAssertEqual(UsageHeatmap.level(7, thresholds), 4)
    }

    func testAllStartsAtTheEarliestRecordedDayAndCapsColumns() throws {
        let calendar = try calendar()
        let end = try day(calendar, 10, 16)
        let first = try day(calendar, 6, 11)
        let daily = [DailyUsage(day: first, provider: .claude, tokens: .init(), estimatedCost: 1)]
        let grid = UsageHeatmap.grid(from: daily, metric: .money, range: .all, endingOn: end, calendar: calendar)
        XCTAssertEqual(grid.cells.first?.day, first)
        XCTAssertEqual(grid.cells.first?.level, 4)

        let capped = UsageHeatmap.grid(
            from: daily, metric: .money, range: .all, endingOn: end, calendar: calendar, maxColumns: 4
        )
        XCTAssertEqual(capped.columns.count, 4)
        XCTAssertEqual(capped.cells.last?.day, end)
    }
}
