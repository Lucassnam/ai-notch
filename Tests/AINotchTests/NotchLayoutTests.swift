import XCTest
@testable import AINotch

final class NotchLayoutTests: XCTestCase {
    func testExpandedNotchStaysWithinThreeToTwoAspectRatio() {
        let height = NotchMetrics.expandedHeight(notchHeight: 38)
        XCTAssertLessThanOrEqual(NotchMetrics.expandedWidth / height, 1.5)
    }

    func testCollapsedNotchReservesExactlyOneGutterPerSide() {
        let hardwareNotchWidth: CGFloat = 185
        let reserved = NotchMetrics.collapsedWidth(notchWidth: hardwareNotchWidth)
            - hardwareNotchWidth
        XCTAssertEqual(reserved, NotchMetrics.compactGutter * 2, accuracy: 0.001)
        // Wide enough for a value on each side, narrow enough not to bury the
        // menu bar the way the old flat 200pt reservation did.
        XCTAssertGreaterThanOrEqual(reserved, 2 * NotchMetrics.compactSlotWidth)
        XCTAssertLessThan(reserved, 200)
    }

    func testCompactTextMatchesMenuBarScaleOnBothSides() {
        XCTAssertEqual(NotchMetrics.leadingCompactFontSize, 13)
        XCTAssertEqual(NotchMetrics.trailingCompactFontSize, 13)
        // Both slots must share one size; differing weights read as differing
        // sizes either side of the notch.
        XCTAssertEqual(
            NotchMetrics.leadingCompactFontSize,
            NotchMetrics.trailingCompactFontSize
        )
    }

    /// The bug this guards: `TopConnectedNotchShape` leaves the outer
    /// `compactShoulderRadius` points unpainted, so a value centred on the
    /// frame gutter sits half a shoulder too far outward. At a 185pt notch that
    /// was a measured 6pt bias on each side.
    func testCompactSlotsAreCentredInThePaintedGutterNotTheFrame() {
        let notchWidth: CGFloat = 185
        let width = NotchMetrics.collapsedWidth(notchWidth: notchWidth)
        let slots = NotchMetrics.compactSlots(width: width, notchWidth: notchWidth)

        let paintedLeading = NotchMetrics.compactShoulderRadius
        let paintedTrailing = width - NotchMetrics.compactShoulderRadius
        let notchLeading = width / 2 - notchWidth / 2
        let notchTrailing = width / 2 + notchWidth / 2

        XCTAssertEqual(
            slots.leadingCenter,
            (paintedLeading + notchLeading) / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            slots.trailingCenter,
            (notchTrailing + paintedTrailing) / 2,
            accuracy: 0.001
        )
        // And explicitly *not* the frame centre, which is what shipped before.
        XCTAssertNotEqual(slots.leadingCenter, notchLeading / 2, accuracy: 0.001)
    }

    func testCompactSlotsAreMirrorImagesOfEachOther() {
        let notchWidth: CGFloat = 185
        let width = NotchMetrics.collapsedWidth(notchWidth: notchWidth)
        let slots = NotchMetrics.compactSlots(width: width, notchWidth: notchWidth)

        XCTAssertEqual(slots.leadingCenter, width - slots.trailingCenter, accuracy: 0.001)
        XCTAssertGreaterThan(slots.width, 0)
    }

    /// Both values must stay evenly placed when the notch is not centred on the
    /// display, because the menu bar's usable areas are the only measurement
    /// available and nothing guarantees they are symmetric.
    func testCompactSlotsFollowAnOffCentreNotch() {
        let notchWidth: CGFloat = 185
        let width = NotchMetrics.collapsedWidth(notchWidth: notchWidth)
        let offset: CGFloat = 12
        let slots = NotchMetrics.compactSlots(
            width: width,
            notchWidth: notchWidth,
            notchCenterOffset: offset
        )

        let notchLeading = width / 2 + offset - notchWidth / 2
        let notchTrailing = width / 2 + offset + notchWidth / 2
        let paintedLeading = NotchMetrics.compactShoulderRadius
        let paintedTrailing = width - NotchMetrics.compactShoulderRadius

        // With an off-centre notch the two gutters are different widths, so
        // "centred in its own gutter" and "equal clearance from the notch"
        // cannot both hold. Centred-in-gutter is the one the eye judges: each
        // value sits in the middle of the strip it actually occupies.
        XCTAssertEqual(
            slots.leadingCenter,
            (paintedLeading + notchLeading) / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            slots.trailingCenter,
            (notchTrailing + paintedTrailing) / 2,
            accuracy: 0.001
        )
        // Both values still get the same amount of room, so they never render
        // at two different effective sizes.
        XCTAssertGreaterThan(slots.width, 0)
    }

    func testCompactSlotsDegradeSafelyWithoutAHardwareNotch() {
        let width = NotchMetrics.collapsedWidth(notchWidth: 0)
        let slots = NotchMetrics.compactSlots(width: width, notchWidth: 0)

        XCTAssertEqual(width, NotchMetrics.collapsedFallbackWidth)
        XCTAssertEqual(slots.leadingCenter, width - slots.trailingCenter, accuracy: 0.001)
        XCTAssertGreaterThan(slots.width, 0)
    }

    func testExpandedSurfaceHasTheThreeRequestedTabs() {
        XCTAssertEqual(ExpandedTab.allCases, [.widgets, .graph, .quick])
        XCTAssertEqual(ExpandedTab.allCases.map(\.title), ["Widgets", "Graph", "Quick"])
    }

    func testSevenDayGraphFillsMissingDaysAndSeparatesProviders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))
        )
        let previousDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))
        let tooOld = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: end))
        let daily = [
            DailyUsage(
                day: previousDay,
                provider: .claude,
                tokens: .init(input: 100, output: 25),
                estimatedCost: 2.25
            ),
            DailyUsage(
                day: previousDay,
                provider: .codex,
                tokens: .init(input: 200, output: 50),
                estimatedCost: 1.75
            ),
            DailyUsage(day: tooOld, provider: .codex, tokens: .init(), estimatedCost: 99)
        ]

        let points = UsageGraphSeries.sevenDaySpend(
            from: daily,
            endingOn: end,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 14)
        let previousDayPoints = points.filter { calendar.isDate($0.day, inSameDayAs: previousDay) }
        XCTAssertEqual(previousDayPoints.map(\.provider), [.claude, .codex])
        XCTAssertEqual(previousDayPoints[0].cost, 2.25, accuracy: 0.001)
        XCTAssertEqual(previousDayPoints[0].tokens, 125)
        XCTAssertEqual(previousDayPoints[1].cost, 1.75, accuracy: 0.001)
        XCTAssertEqual(previousDayPoints[1].tokens, 250)
        XCTAssertEqual(points.suffix(2).map(\.cost), [0, 0])
    }

    func testCompactLimitDropsDirectionalWord() {
        let limit = RateLimitWindow(
            id: "limit",
            provider: .codex,
            windowMinutes: 300,
            usedPercent: 47,
            resetsAt: nil,
            observedAt: Date(),
            source: "test"
        )

        XCTAssertEqual(limit.compactRemainingLabel, "53%")
        XCTAssertEqual(limit.remainingLabel, "53% left")
    }

    func testThirtyDayGraphContainsThirtyDailyBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))
        )

        let points = UsageGraphSeries.spend(
            from: [],
            range: .thirtyDays,
            endingOn: end,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 60)
    }

    func testAllTimeGraphCombinesDailySpendIntoMonthlyBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let january = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 4))
        )
        let march = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 19))
        )
        let daily = [
            DailyUsage(day: january, provider: .claude, tokens: .init(), estimatedCost: 2),
            DailyUsage(day: january, provider: .codex, tokens: .init(), estimatedCost: 3),
            DailyUsage(day: march, provider: .codex, tokens: .init(), estimatedCost: 7)
        ]

        let points = UsageGraphSeries.spend(
            from: daily,
            range: .all,
            endingOn: march,
            calendar: calendar
        )

        XCTAssertEqual(points.map(\.provider), [.claude, .codex, .claude, .codex, .claude, .codex])
        XCTAssertEqual(points.map(\.cost), [2, 3, 0, 0, 0, 7])
    }

    func testGraphOffersMoneyAndTokenMeasures() {
        XCTAssertEqual(UsageGraphMetric.allCases, [.money, .tokens])
        XCTAssertEqual(UsageGraphMetric.allCases.map(\.title), ["Money", "Tokens"])

        let point = UsageGraphPoint(
            day: Date(timeIntervalSince1970: 0),
            provider: .claude,
            cost: 4.25,
            tokens: 1_250_000
        )
        XCTAssertEqual(point.value(for: .money), 4.25, accuracy: 0.001)
        XCTAssertEqual(point.value(for: .tokens), 1_250_000, accuracy: 0.001)
    }

    /// The built-in display's "More Space" mode reports a 220 x 38pt notch.
    /// Every earlier check ran on a faked 185 x 32, so this is the geometry
    /// the layout was never measured against.
    func testCompactSlotsClearTheNotchAtTheMoreSpaceGeometry() {
        let notchWidth: CGFloat = 220
        let width = NotchMetrics.collapsedWidth(notchWidth: notchWidth)
        let slots = NotchMetrics.compactSlots(width: width, notchWidth: notchWidth)
        let notchLeading = (width - notchWidth) / 2
        let notchTrailing = (width + notchWidth) / 2

        XCTAssertEqual(slots.width, NotchMetrics.compactSlotWidth, accuracy: 0.001)
        XCTAssertLessThanOrEqual(slots.leadingCenter + slots.width / 2, notchLeading)
        XCTAssertGreaterThanOrEqual(slots.trailingCenter - slots.width / 2, notchTrailing)
        XCTAssertGreaterThanOrEqual(
            slots.leadingCenter - slots.width / 2,
            NotchMetrics.compactShoulderRadius
        )
    }

    func testWidgetRowsDivideThePageExactly() {
        let available: CGFloat = 288
        let gap = NotchMetrics.cardGap

        // Up to four widgets: two rows. Five or six: three.
        for count in 1...4 {
            let row = NotchMetrics.widgetRowHeight(available: available, widgetCount: count)
            XCTAssertEqual(row * 2 + gap, available, accuracy: 0.001)
        }
        for count in 5...6 {
            let row = NotchMetrics.widgetRowHeight(available: available, widgetCount: count)
            XCTAssertEqual(row * 3 + gap * 2, available, accuracy: 0.001)
        }
        // A seventh widget scrolls rather than shrinking the cards again.
        XCTAssertEqual(
            NotchMetrics.widgetRowHeight(available: available, widgetCount: 7),
            NotchMetrics.widgetRowHeight(available: available, widgetCount: 6),
            accuracy: 0.001
        )
        XCTAssertEqual(NotchMetrics.widgetRowHeight(available: 0, widgetCount: 4), 0)
    }

    /// The body is narrower than the frame by one shoulder per side. Padding
    /// measured from the frame alone once left cards 6pt from the visible edge
    /// with 16pt beneath them.
    func testContentSitsTheSameDistanceFromEveryPaintedEdge() {
        let sideFromPaintedEdge = NotchMetrics.outerPadding - NotchMetrics.shoulderRadius
        XCTAssertEqual(sideFromPaintedEdge, NotchMetrics.contentInset, accuracy: 0.001)
        // Concentric corners: the panel's radius is the card's plus the inset.
        XCTAssertEqual(
            NotchMetrics.bottomCornerRadius,
            NotchDesign.cardRadius + NotchMetrics.contentInset,
            accuracy: 0.001
        )
    }

    /// Three rows of short cards need 84pt each: 12 + title 16 + 1 + figure 27
    /// + 2 + detail 14 + 12.
    func testThreeRowsOfShortCardsFitThePage() {
        let page = NotchMetrics.dashboardContentHeight
            - NotchMetrics.pageTopInset
            - NotchMetrics.cardGap
            - NotchMetrics.tabBarHeight
            - NotchMetrics.contentInset
        let row = NotchMetrics.widgetRowHeight(available: page, widgetCount: 6)
        XCTAssertGreaterThanOrEqual(row, 84)
    }
}
