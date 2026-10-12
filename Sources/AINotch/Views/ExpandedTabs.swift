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
        }
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
