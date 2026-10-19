import Charts
import SwiftUI

enum ExpandedTab: String, CaseIterable, Identifiable {
    case widgets
    case graph
    case quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "Widgets"
        case .graph: "Graph"
        case .quick: "Quick"
        }
    }

    var symbol: String {
        switch self {
        case .widgets: "square.grid.2x2"
        case .graph: "chart.xyaxis.line"
        case .quick: "slider.horizontal.3"
        }
    }
}

struct ExpandedTabBar: View {
    @Binding var selection: ExpandedTab

    var body: some View {
        RangeSelector(
            options: ExpandedTab.allCases,
            title: \.title,
            selection: $selection,
            height: NotchMetrics.tabBarHeight,
            font: NotchType.tab
        )
        .padding(.horizontal, NotchMetrics.outerPadding)
        .padding(.top, NotchMetrics.cardGap)
        .padding(.bottom, NotchMetrics.contentInset)
        // The bar keeps its place whatever the page above asks for. Without
        // this a page 3pt too tall pushed it down into the bottom margin.
        .layoutPriority(1)
    }
}

enum UsageGraphMetric: String, CaseIterable, Identifiable {
    case money
    case tokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .money: "Money"
        case .tokens: "Tokens"
        }
    }
}

/// Bars stack each provider; the heatmap trades that split for a whole
/// calendar at a glance, the way GitHub's contribution graph does.
enum UsageGraphStyle: String, CaseIterable, Identifiable {
    case bars
    case heatmap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: "Bars"
        case .heatmap: "Heatmap"
        }
    }

    var symbol: String {
        switch self {
        case .bars: "chart.bar.fill"
        case .heatmap: "square.grid.3x3.fill"
        }
    }
}

struct UsageHeatmapCell: Identifiable, Equatable {
    let day: Date
    let value: Double
    /// 0 for an idle day, then 1-4 by quartile of the active days shown.
    let level: Int

    var id: Date { day }
}

/// Columns of cells, oldest first. A column is one week, top to bottom in the
/// calendar's own weekday order, or a single day when `rows` is 1. `nil`
/// marks a slot outside the range (before the first day, after today).
struct UsageHeatmapGrid: Equatable {
    let rows: Int
    let columns: [[UsageHeatmapCell?]]

    var cells: [UsageHeatmapCell] { columns.flatMap { $0.compactMap { $0 } } }
}

enum UsageHeatmap {
    static let levels = 4

    static func grid(
        from dailyUsage: [DailyUsage],
        metric: UsageGraphMetric,
        range: HistoryRange,
        endingOn endDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        maxColumns: Int = 53
    ) -> UsageHeatmapGrid {
        let end = calendar.startOfDay(for: endDate)
        let totals = dailyUsage.reduce(into: [Date: Double]()) { result, item in
            let amount = metric == .money ? item.estimatedCost : Double(item.tokens.total)
            result[calendar.startOfDay(for: item.day), default: 0] += amount
        }

        let start: Date
        switch range {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        case .all:
            start = min(totals.keys.filter { $0 <= end }.min() ?? end, end)
        }

        let thresholds = quartiles(
            totals.filter { $0.key >= start && $0.key <= end && $0.value > 0 }.map(\.value)
        )
        func cell(_ day: Date) -> UsageHeatmapCell? {
            guard day >= start, day <= end else { return nil }
            let value = totals[day] ?? 0
            return UsageHeatmapCell(day: day, value: value, level: level(value, thresholds))
        }

        // Seven days read best as one strip of large cells.
        if range == .week {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            return UsageHeatmapGrid(rows: 1, columns: days.map { [cell($0)] })
        }

        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        var columns: [[UsageHeatmapCell?]] = []
        var weekStart = firstWeek
        while weekStart <= end {
            columns.append((0..<7).map { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart).flatMap(cell)
            })
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return UsageHeatmapGrid(rows: 7, columns: Array(columns.suffix(maxColumns)))
    }

    /// GitHub-style buckets: a day's level is the quartile it falls in among
    /// the active days shown, so one huge day cannot flatten the rest to the
    /// faintest shade the way a linear scale would.
    static func quartiles(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [] }
        return (1..<levels).map { quarter in
            sorted[min(sorted.count - 1, sorted.count * quarter / levels)]
        }
    }

    static func level(_ value: Double, _ thresholds: [Double]) -> Int {
        guard value > 0 else { return 0 }
        return 1 + thresholds.filter { value >= $0 }.count
    }
}

struct UsageGraphPoint: Identifiable, Equatable {
    let day: Date
    let provider: ProviderID
    let cost: Double
    let tokens: Int64

    var id: String { "\(provider.rawValue)-\(day.timeIntervalSince1970)" }

    func value(for metric: UsageGraphMetric) -> Double {
        switch metric {
        case .money: cost
        case .tokens: Double(tokens)
        }
    }
}

enum UsageGraphSeries {
    private struct BucketKey: Hashable {
        let date: Date
        let provider: ProviderID
    }

    private struct BucketTotal {
        var cost: Double = 0
        var tokens: Int64 = 0
    }

    static func sevenDaySpend(
        from dailyUsage: [DailyUsage],
        endingOn endDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UsageGraphPoint] {
        spend(
            from: dailyUsage,
            range: .week,
            endingOn: endDate,
            calendar: calendar
        )
    }

    static func spend(
        from dailyUsage: [DailyUsage],
        range: HistoryRange,
        endingOn endDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UsageGraphPoint] {
        switch range {
        case .week:
            dailySpend(
                from: dailyUsage,
                dayCount: 7,
                endingOn: endDate,
                calendar: calendar
            )
        case .thirtyDays:
            dailySpend(
                from: dailyUsage,
                dayCount: 30,
                endingOn: endDate,
                calendar: calendar
            )
        case .all:
            monthlySpend(from: dailyUsage, endingOn: endDate, calendar: calendar)
        }
    }

    private static func dailySpend(
        from dailyUsage: [DailyUsage],
        dayCount: Int,
        endingOn endDate: Date,
        calendar: Calendar
    ) -> [UsageGraphPoint] {
        let end = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) ?? end
        let totals = dailyUsage.reduce(into: [BucketKey: BucketTotal]()) { result, item in
            let day = calendar.startOfDay(for: item.day)
            guard day >= start, day <= end else { return }
            let key = BucketKey(date: day, provider: item.provider)
            result[key, default: BucketTotal()].cost += item.estimatedCost
            result[key, default: BucketTotal()].tokens += item.tokens.total
        }

        let days = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }

        return days.flatMap { day in
            ProviderID.allCases.map { provider in
                let total = totals[BucketKey(date: day, provider: provider)] ?? BucketTotal()
                return UsageGraphPoint(
                    day: day,
                    provider: provider,
                    cost: total.cost,
                    tokens: total.tokens
                )
            }
        }
    }

    private static func monthlySpend(
        from dailyUsage: [DailyUsage],
        endingOn endDate: Date,
        calendar: Calendar
    ) -> [UsageGraphPoint] {
        let end = calendar.dateInterval(of: .month, for: endDate)?.start
            ?? calendar.startOfDay(for: endDate)
        let sourceMonths = dailyUsage.compactMap { item -> Date? in
            guard let month = calendar.dateInterval(of: .month, for: item.day)?.start,
                  month <= end else { return nil }
            return month
        }
        let start = sourceMonths.min() ?? end
        let monthCount = max(
            0,
            calendar.dateComponents([.month], from: start, to: end).month ?? 0
        )
        let totals = dailyUsage.reduce(into: [BucketKey: BucketTotal]()) { result, item in
            guard let month = calendar.dateInterval(of: .month, for: item.day)?.start,
                  month >= start,
                  month <= end else { return }
            let key = BucketKey(date: month, provider: item.provider)
            result[key, default: BucketTotal()].cost += item.estimatedCost
            result[key, default: BucketTotal()].tokens += item.tokens.total
        }

        let months = (0...monthCount).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: start)
        }

        return months.flatMap { month in
            ProviderID.allCases.map { provider in
                let total = totals[BucketKey(date: month, provider: provider)] ?? BucketTotal()
                return UsageGraphPoint(
                    day: month,
                    provider: provider,
                    cost: total.cost,
                    tokens: total.tokens
                )
            }
        }
    }
}

struct UsageGraphPage: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var range = HistoryRange(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_RANGE"] ?? "week"
    ) ?? .week
    @State private var metric = UsageGraphMetric(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_METRIC"] ?? "money"
    ) ?? .money
    @State private var style = UsageGraphStyle(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_GRAPH"] ?? "bars"
    ) ?? .bars

    private var points: [UsageGraphPoint] {
        UsageGraphSeries.spend(from: viewModel.snapshot.daily, range: range)
    }

    private var total: Double {
        points.reduce(0) { $0 + $1.value(for: metric) }
    }

    private var formattedTotal: String {
        switch metric {
        case .money: AIFormat.currency(total)
        case .tokens: AIFormat.tokens(Int64(total.rounded()))
        }
    }

    /// The tallest stacked bucket — the value the reference line is drawn at.
    private var peak: Double {
        let stackedTotals = Dictionary(grouping: points, by: \.day).values.map { bucket in
            bucket.reduce(0) { $0 + $1.value(for: metric) }
        }
        let minimum = metric == .money ? 0.01 : 1
        return max(stackedTotals.max() ?? 0, minimum)
    }

    private var upperBound: Double { peak * 1.15 }

    private func formatted(_ value: Double, compact: Bool = true) -> String {
        switch metric {
        case .money: AIFormat.currency(value, compact: compact)
        case .tokens: AIFormat.tokens(Int64(value.rounded()))
        }
    }

    private static let coverageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd y")
        return formatter
    }()

    /// "All time" was a false label. AI Notch can only see transcripts Claude
    /// Code has not yet deleted, plus whatever it has recorded itself since it
    /// was installed — so the widest range is "everything held", and it says
    /// which date that starts from instead of implying a lifetime total.
    private var caption: String {
        switch range {
        case .week:
            return "Past 7 days"
        case .thirtyDays:
            return "Past 30 days"
        case .all:
            guard let earliest = viewModel.earliestRecordedDay else {
                return "Everything recorded"
            }
            return "Since \(Self.coverageFormatter.string(from: earliest))"
        }
    }

    /// Shown on the widest range, always.
    ///
    /// This range used to be captioned "All time", which invited comparison
    /// with the lifetime total Claude Code reports for the account — a number
    /// this app cannot reach. Two things separate them, and the note names
    /// both: coverage (only what is still on disk) and counting (one row per
    /// API request, where a transcript writes one row per content block).
    private var coverageNote: String? {
        guard range == .all, let coverage = viewModel.historyCoverage else { return nil }

        let start = Self.coverageFormatter.string(from: coverage.earliest)
        var note = "Everything still on disk since \(start), counted once per "
            + "API request. Not an account lifetime total."

        if coverage.isTruncated {
            note += " Claude Code deletes older transcripts, so earlier usage "
                + "was gone before AI Notch could record it."
        }
        return note
    }

    private var xUnit: Calendar.Component {
        range == .all ? .month : .day
    }

    /// One mark per bar where every bar gets a label, so the label can be
    /// centred under it.
    private var xAxisValues: AxisMarkValues {
        range == .all ? .stride(by: .month) : .stride(by: .day)
    }

    /// Thirty daily bars cannot each carry a date, so that range labels every
    /// seventh day, anchored at the start of the day. The last mark is kept
    /// four days clear of the right edge: automatic marks could land on the
    /// final days, where "Oct 11" was cut to "O…".
    private var thirtyDayMarks: [Date] {
        let days = Array(Set(points.map(\.day))).sorted()
        return stride(from: 1, to: max(1, days.count - 4), by: 7).map { days[$0] }
    }

    @AxisMarkBuilder
    private func xLabel(_ value: AxisValue, centered: Bool) -> some AxisMark {
        // Uncentred, a label hangs from the start of its day while the bar
        // spans the whole day: measured 13pt left of the bar's centre on the
        // seven-day view.
        AxisValueLabel(centered: centered) {
            if let date = value.as(Date.self) {
                switch range {
                case .week:
                    Text(date, format: .dateTime.weekday(.narrow))
                case .thirtyDays:
                    Text(date, format: .dateTime.month(.abbreviated).day())
                case .all:
                    Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(NotchDesign.tertiary)
        AxisTick().foregroundStyle(.clear)
        AxisGridLine().foregroundStyle(.clear)
    }

    private func total(for provider: ProviderID) -> String {
        formatted(
            points
                .filter { $0.provider == provider }
                .reduce(0) { $0 + $1.value(for: metric) },
            compact: false
        )
    }

    /// Each provider's total for the range, under the figure they add up to.
    private var legend: some View {
        HStack(spacing: MacSpacing.item) {
            ForEach(ProviderID.allCases) { provider in
                HStack(spacing: 5) {
                    Circle()
                        .fill(provider.tint)
                        .frame(width: 7, height: 7)
                    Text(provider.displayName)
                        .foregroundStyle(NotchDesign.secondary)
                    Text(total(for: provider))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                }
                .font(NotchType.label)
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            // On the legend's row, which had the room: a row of its own would
            // take its height from the chart.
            RangeSelector(
                options: UsageGraphStyle.allCases,
                title: \.title,
                selection: $style,
                height: 22,
                font: .system(size: 10, weight: .semibold),
                symbol: \.symbol
            )
            .frame(width: 64)
            .accessibilityLabel("Graph style")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchMetrics.cardGap) {
            HStack(alignment: .top, spacing: MacSpacing.item) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption)
                        .font(NotchType.body)
                        .foregroundStyle(NotchDesign.secondary)
                    Text(formattedTotal)
                        .font(NotchType.display)
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                // One width for both, so their edges line up. Sized to their
                // own labels they were two different widths, stacked.
                VStack(spacing: 6) {
                    RangeSelector(
                        options: HistoryRange.allCases,
                        title: \.title,
                        selection: $range
                    )
                    .accessibilityLabel("Graph range")

                    RangeSelector(
                        options: UsageGraphMetric.allCases,
                        title: \.title,
                        selection: $metric
                    )
                    .accessibilityLabel("Graph measure")
                }
                .frame(width: 148)
            }
            .padding(.horizontal, MacSpacing.compact)

            // A row of its own. Beside the selectors it had 220pt, and two
            // four-figure totals wrapped mid-number.
            legend
                .padding(.horizontal, MacSpacing.compact)

            Group {
                switch style {
                case .bars:
                    Chart {
                        ForEach(points) { point in
                            BarMark(
                                x: .value("Period", point.day, unit: xUnit),
                                y: .value(metric.title, point.value(for: metric))
                            )
                            .foregroundStyle(by: .value("Provider", point.provider.displayName))
                            // 2pt, not 4. Swift Charts rounds every corner of a mark,
                            // so a larger radius lifts stacked segments off the baseline
                            // and off each other.
                            .cornerRadius(2)
                        }
                    }
                    .chartForegroundStyleScale([
                        ProviderID.claude.displayName: ProviderID.claude.tint,
                        ProviderID.codex.displayName: ProviderID.codex.tint
                    ])
                    .chartLegend(.hidden)
                    .chartYScale(domain: 0...upperBound)
                    .chartYAxis {
                        // One reference line at the tallest bucket. The axis was fully
                        // hidden, which left every bar height unreadable.
                        AxisMarks(position: .trailing, values: [peak]) { _ in
                            AxisGridLine().foregroundStyle(NotchDesign.divider)
                            AxisValueLabel {
                                Text(formatted(peak))
                                    .font(NotchType.label)
                                    .foregroundStyle(NotchDesign.tertiary)
                            }
                        }
                    }
                    .chartXAxis {
                        if range == .thirtyDays {
                            AxisMarks(values: thirtyDayMarks) { value in xLabel(value, centered: false) }
                        } else {
                            AxisMarks(values: xAxisValues) { value in xLabel(value, centered: true) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(NotchDesign.cardPadding)
                    .metalCard()
                    .accessibilityLabel("\(caption) \(metric.title.lowercased()) graph")
                    .accessibilityValue(formattedTotal)
                    .animation(.easeInOut(duration: 0.18), value: range)
                    .animation(.easeInOut(duration: 0.18), value: metric)
                case .heatmap:
                    UsageHeatmapView(
                        grid: UsageHeatmap.grid(
                            from: viewModel.snapshot.daily,
                            metric: metric,
                            range: range
                        ),
                        format: { formatted($0, compact: false) }
                    )
                    .frame(maxHeight: .infinity)
                    .padding(NotchDesign.cardPadding)
                    .metalCard()
                    .accessibilityLabel("\(caption) \(metric.title.lowercased()) heatmap")
                    .accessibilityValue(formattedTotal)
                }
            }

            if let coverageNote {
                Text(coverageNote)
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MacSpacing.compact)
            }
        }
        .padding(.horizontal, NotchMetrics.outerPadding)
        .padding(.top, NotchMetrics.pageTopInset)
        .onAppear {
            if let rawRange = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_RANGE"],
               let requestedRange = HistoryRange(rawValue: rawRange) {
                range = requestedRange
            }
            if let rawMetric = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_METRIC"],
               let requestedMetric = UsageGraphMetric(rawValue: rawMetric) {
                metric = requestedMetric
            }
            if let rawStyle = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_GRAPH"],
               let requestedStyle = UsageGraphStyle(rawValue: rawStyle) {
                style = requestedStyle
            }
        }
    }
}

/// GitHub's contribution graph, in Claude orange: darker is less, brighter
/// is more, a ring marks today. Pointing at a day names it in the footer, since
/// the panel is never key and so never shows tooltips.
struct UsageHeatmapView: View {
    let grid: UsageHeatmapGrid
    let format: (Double) -> String
    @State private var hovered: UsageHeatmapCell?

    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 14
    private let labelHeight: CGFloat = 14
    private let maxCell: CGFloat = 40

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter
    }()

    static func color(level: Int) -> Color {
        guard level > 0 else { return NotchDesign.control }
        let opacity = [0.30, 0.52, 0.76, 1.0][min(level, UsageHeatmap.levels) - 1]
        return ProviderID.claude.tint.opacity(opacity)
    }

    private var isCalendar: Bool { grid.rows == 7 }

    private var today: Date { Calendar.autoupdatingCurrent.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: MacSpacing.related) {
            GeometryReader { proxy in
                let size = cellSize(in: proxy.size)
                let gridWidth = CGFloat(grid.columns.count) * (size + gap) - gap
                HStack(alignment: .top, spacing: 0) {
                    if isCalendar { weekdayLabels(size: size) }
                    VStack(alignment: .leading, spacing: 4) {
                        if isCalendar { monthLabels(size: size, width: gridWidth) }
                        HStack(spacing: gap) {
                            ForEach(grid.columns.indices, id: \.self) { index in
                                VStack(spacing: gap) {
                                    ForEach(0..<grid.rows, id: \.self) { row in
                                        square(grid.columns[index][row], size: size)
                                    }
                                }
                            }
                        }
                        if !isCalendar { dayLetters(size: size) }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            footer
        }
    }

    /// Square cells as large as both directions allow, so seven days fill the
    /// card and a whole season still fits on one row.
    private func cellSize(in available: CGSize) -> CGFloat {
        let columns = CGFloat(max(1, grid.columns.count))
        let rows = CGFloat(grid.rows)
        let width = available.width - (isCalendar ? labelWidth : 0)
        let height = available.height - labelHeight - 4
        let byWidth = (width - gap * (columns - 1)) / columns
        let byHeight = (height - gap * (rows - 1)) / rows
        return max(4, min(maxCell, byWidth, byHeight))
    }

    @ViewBuilder
    private func square(_ cell: UsageHeatmapCell?, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(4, size / 4), style: .continuous)
        if let cell {
            shape
                .fill(Self.color(level: cell.level))
                .overlay {
                    if cell.day == today {
                        shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    } else if cell == hovered {
                        shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = cell } else if hovered == cell { hovered = nil }
                }
                .accessibilityElement()
                .accessibilityLabel(Self.dayFormatter.string(from: cell.day))
                .accessibilityValue(format(cell.value))
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    /// Mon, Wed and Fri, as GitHub labels them; every row is too dense.
    private func weekdayLabels(size: CGFloat) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let symbols = calendar.veryShortWeekdaySymbols
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                let weekday = (calendar.firstWeekday - 1 + row) % 7
                Text([1, 3, 5].contains(weekday) ? symbols[weekday] : "")
                    .frame(width: labelWidth, height: size, alignment: .leading)
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(NotchDesign.tertiary)
        .padding(.top, labelHeight + 4)
    }

    /// A month's name over the first week that starts inside it.
    private func monthLabels(size: CGFloat, width: CGFloat) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        return ZStack(alignment: .topLeading) {
            ForEach(grid.columns.indices, id: \.self) { index in
                if let first = grid.columns[index].compactMap({ $0 }).first,
                   index == 0 || calendar.component(.day, from: first.day) <= 7 {
                    Text(first.day, format: .dateTime.month(.abbreviated))
                        .fixedSize()
                        .offset(x: CGFloat(index) * (size + gap))
                }
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(NotchDesign.tertiary)
        .frame(width: width, height: labelHeight, alignment: .topLeading)
        .clipped()
    }

    private func dayLetters(size: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(grid.columns.indices, id: \.self) { index in
                Group {
                    if let cell = grid.columns[index].first ?? nil {
                        Text(cell.day, format: .dateTime.weekday(.abbreviated))
                    } else {
                        Text("")
                    }
                }
                .frame(width: size, height: labelHeight)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(NotchDesign.tertiary)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Group {
                if let hovered {
                    Text("\(Self.dayFormatter.string(from: hovered.day))  ")
                        .foregroundStyle(NotchDesign.secondary)
                    + Text(format(hovered.value)).foregroundStyle(Color.white)
                } else {
                    let active = grid.cells.filter { $0.value > 0 }.count
                    Text(active == 1 ? "1 active day" : "\(active) active days")
                        .foregroundStyle(NotchDesign.tertiary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            Spacer(minLength: 0)
            Text("Less").foregroundStyle(NotchDesign.tertiary)
            ForEach(0...UsageHeatmap.levels, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.color(level: level))
                    .frame(width: 9, height: 9)
            }
            Text("More").foregroundStyle(NotchDesign.tertiary)
        }
        .font(.system(size: 10, weight: .medium))
        .frame(height: 12)
    }
}

struct QuickSettingsPage: View {
    @ObservedObject var viewModel: UsageViewModel
    let onCustomize: () -> Void

    private static let rowHeight: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: NotchMetrics.cardGap) {
            group {
                switchRow(
                    title: "Keep open",
                    symbol: "pin.fill",
                    isOn: viewModel.isPinned,
                    action: viewModel.togglePinned
                )
                rowDivider
                switchRow(
                    title: "Translucent background",
                    symbol: "circle.lefthalf.filled",
                    isOn: viewModel.isTranslucent,
                    action: viewModel.toggleTranslucency
                )
                rowDivider
                switchRow(
                    title: "Launch at login",
                    symbol: "power",
                    isOn: viewModel.launchesAtLogin,
                    action: viewModel.toggleLaunchAtLogin
                )
            }

            group {
                Button(action: onCustomize) {
                    HStack(spacing: 0) {
                        rowLabel(title: "Customize widgets…", symbol: "slider.horizontal.3")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchDesign.tertiary)
                    }
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Its own group, in red, the way a destructive action is set apart
            // in System Settings. It was a plain row under Customize, where it
            // read as one more navigation link.
            group {
                Button(action: viewModel.quit) {
                    Text("Quit AI Notch")
                        .font(NotchType.body)
                        .foregroundStyle(NotchDesign.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text(status)
                .font(NotchType.label)
                .foregroundStyle(isWarning ? Color.orange : NotchDesign.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NotchDesign.cardPadding)
        }
        .padding(.horizontal, NotchMetrics.outerPadding)
        .padding(.top, NotchMetrics.pageTopInset)
    }

    private var isWarning: Bool {
        viewModel.errorMessage != nil || viewModel.loginItemMessage != nil
    }

    /// What the figures were read from, and when. A failure replaces it, since
    /// a stale total with no explanation is worse than no total.
    private var status: String {
        if let error = viewModel.errorMessage { return "Could not read usage: \(error)" }
        if let message = viewModel.loginItemMessage { return message }
        guard viewModel.hasLoaded else { return "Reading local session files…" }

        let files = viewModel.snapshot.providers.map {
            "\($0.sourceFileCount.formatted()) \($0.provider.displayName)"
        }
        let time = viewModel.snapshot.generatedAt.formatted(date: .omitted, time: .shortened)
        return "Read \(files.joined(separator: " and ")) session files at \(time). "
            + "Costs are API list prices, not a subscription bill."
    }

    /// Starts under the row's text, not under its icon, as list separators do
    /// in System Settings.
    private var rowDivider: some View {
        Rectangle()
            .fill(NotchDesign.divider)
            .frame(height: 1)
            .padding(.leading, Self.iconTile + MacSpacing.control)
    }

    private static let iconTile: CGFloat = 24

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, NotchDesign.cardPadding)
            .metalCard()
    }

    private func rowLabel(title: String, symbol: String) -> some View {
        HStack(spacing: MacSpacing.control) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: Self.iconTile, height: Self.iconTile)
                .background(
                    NotchDesign.controlActive,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            Text(title)
                .font(NotchType.body)
                .foregroundStyle(Color.white)
            Spacer(minLength: MacSpacing.control)
        }
    }

    /// The whole row is the hit target, and the switch is drawn by the app.
    /// A system `Toggle` here rendered in AppKit's inactive grey, because the
    /// notch panel is never the key window: on and off looked the same.
    private func switchRow(
        title: String,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                rowLabel(title: title, symbol: symbol)
                NotchSwitch(isOn: isOn)
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A switch that reads the same whether or not its window is key.
struct NotchSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? NotchDesign.switchOn : NotchDesign.controlActive)
            .frame(width: 36, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.14), value: isOn)
    }
}
