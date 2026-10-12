import AppKit
import Foundation
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    private static let translucentPreferenceKey = "notchTranslucent"
    private static let widgetOrderPreferenceKey = "metricWidgetOrder"
    private static let visibleWidgetsPreferenceKey = "visibleMetricWidgets"
    private static let leadingWidgetPreferenceKey = "leadingCompactWidget"
    private static let trailingWidgetPreferenceKey = "trailingCompactWidget"

    private static let defaultVisibleWidgets: Set<MetricWidget> = [
        .todaySpend,
        .fiveHourSpend,
        .fiveHourTokens,
        .codexLimit
    ]

    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isLoading = true
    /// False until the first scan has finished, successfully or not. Views use
    /// it to tell "nothing spent" apart from "nothing read yet".
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var isExpanded = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW"] == "1"
    @Published var isPinned = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW"] == "1"
    @Published var selectedPage: NotchPage = NotchPage(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_PAGE"] ?? "overview"
    ) ?? .overview
    @Published var isTranslucent: Bool {
        didSet {
            preferences.set(isTranslucent, forKey: Self.translucentPreferenceKey)
        }
    }
    @Published private(set) var widgetOrder: [MetricWidget] {
        didSet {
            preferences.set(widgetOrder.map(\.rawValue), forKey: Self.widgetOrderPreferenceKey)
        }
    }
    @Published private(set) var visibleWidgets: Set<MetricWidget> {
        didSet {
            preferences.set(
                widgetOrder.filter(visibleWidgets.contains).map(\.rawValue),
                forKey: Self.visibleWidgetsPreferenceKey
            )
        }
    }
    @Published var leadingCompactWidget: MetricWidget? {
        didSet {
            preferences.set(leadingCompactWidget?.rawValue ?? "", forKey: Self.leadingWidgetPreferenceKey)
        }
    }
    @Published var trailingCompactWidget: MetricWidget? {
        didSet {
            preferences.set(trailingCompactWidget?.rawValue ?? "", forKey: Self.trailingWidgetPreferenceKey)
        }
    }
    /// Mirrors `SMAppService` rather than a stored preference, so the toggle
    /// always reflects what the system actually granted.
    @Published private(set) var launchesAtLogin = LoginItem.isEnabled
    @Published private(set) var loginItemMessage: String?
    /// Height of the notch (or menu bar) on the active screen. Published by the
    /// panel controller, which owns the geometry.
    @Published var notchHeight: CGFloat = NotchMetrics.collapsedFallbackHeight
    /// Width of the physical notch on the active screen, zero where there is
    /// none. Both presentations span the notch, so every layout that puts
    /// content in the top strip has to route around this.
    @Published var notchWidth: CGFloat = 0
    /// How far the notch's centre sits from the panel's centre, in points.
    /// Normally zero, but the menu bar's usable areas are the only source of
    /// truth for where the notch actually is, and nothing guarantees they are
    /// symmetric. Published so the compact layout can route around the real
    /// notch instead of an assumed one.
    @Published var notchCenterOffset: CGFloat = 0

    private let scanner: TelemetryScanner
    private let aggregator: UsageAggregator
    private let preferences: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    init(
        scanner: TelemetryScanner = TelemetryScanner(),
        aggregator: UsageAggregator = UsageAggregator(),
        preferences: UserDefaults = .standard
    ) {
        self.scanner = scanner
        self.aggregator = aggregator
        self.preferences = preferences
        self.isTranslucent = preferences.bool(forKey: Self.translucentPreferenceKey)
        self.widgetOrder = Self.restoredWidgetOrder(from: preferences)
        self.visibleWidgets = Self.restoredVisibleWidgets(from: preferences)
        self.leadingCompactWidget = Self.restoredCompactWidget(
            key: Self.leadingWidgetPreferenceKey,
            default: .todaySpend,
            from: preferences
        )
        self.trailingCompactWidget = Self.restoredCompactWidget(
            key: Self.trailingWidgetPreferenceKey,
            default: .fiveHourTokens,
            from: preferences
        )
    }

    deinit {
        refreshTask?.cancel()
        collapseTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refresh() async {
        isLoading = snapshot.eventCount == 0
        do {
            let raw = try await scanner.scan()
            snapshot = aggregator.snapshot(from: raw)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func setHovering(_ isHovering: Bool) {
        collapseTask?.cancel()
        if isHovering {
            isExpanded = true
        } else if !isPinned {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.isExpanded = false
            }
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func togglePinned() {
        isPinned.toggle()
        if isPinned { isExpanded = true }
    }

    func closePopout() {
        isPinned = false
        isExpanded = false
    }

    func toggleWidget(_ widget: MetricWidget) {
        if visibleWidgets.contains(widget) {
            visibleWidgets.remove(widget)
        } else {
            visibleWidgets.insert(widget)
        }
    }

    func moveWidget(_ widget: MetricWidget, offset: Int) {
        guard let index = widgetOrder.firstIndex(of: widget) else { return }
        let destination = index + offset
        guard widgetOrder.indices.contains(destination) else { return }
        widgetOrder.swapAt(index, destination)
    }

    func resetWidgetPreferences() {
        widgetOrder = MetricWidget.allCases
        visibleWidgets = Self.defaultVisibleWidgets
        leadingCompactWidget = .todaySpend
        trailingCompactWidget = .fiveHourTokens
    }

    var orderedVisibleWidgets: [MetricWidget] {
        widgetOrder.filter(visibleWidgets.contains)
    }

    func toggleTranslucency() {
        isTranslucent.toggle()
    }

    func toggleLaunchAtLogin() {
        let desired = !launchesAtLogin
        loginItemMessage = LoginItem.setEnabled(desired)
        launchesAtLogin = LoginItem.isEnabled
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    var combinedFiveHour: UsageSlice {
        snapshot.providers.reduce(into: UsageSlice()) { result, provider in
            result.tokens = result.tokens + provider.lastFiveHours.tokens
            result.estimatedCost += provider.lastFiveHours.estimatedCost
            result.requestCount += provider.lastFiveHours.requestCount
        }
    }

    var combinedToday: UsageSlice {
        snapshot.providers.reduce(into: UsageSlice()) { result, provider in
            result.tokens = result.tokens + provider.today.tokens
            result.estimatedCost += provider.today.estimatedCost
            result.requestCount += provider.today.requestCount
        }
    }

    var combinedAllTime: UsageSlice {
        snapshot.providers.reduce(into: UsageSlice()) { result, provider in
            result.tokens = result.tokens + provider.allTime.tokens
            result.estimatedCost += provider.allTime.estimatedCost
            result.requestCount += provider.allTime.requestCount
        }
    }

    var combinedWeek: UsageSlice {
        snapshot.providers.reduce(into: UsageSlice()) { result, provider in
            result.tokens = result.tokens + provider.week.tokens
            result.estimatedCost += provider.week.estimatedCost
            result.requestCount += provider.week.requestCount
        }
    }

    /// The oldest day AI Notch actually holds data for.
    ///
    /// This is *not* the day the user started using Claude Code. Claude Code
    /// deletes transcripts once they pass `cleanupPeriodDays` (30 by default),
    /// and this app only sees what is still on disk plus whatever it has
    /// recorded since it was installed. Every "all time" label is derived from
    /// this date rather than claiming a total the data cannot support.
    var earliestRecordedDay: Date? {
        snapshot.daily.first?.day
    }

    /// How much of the recorded history survives Claude Code's cleanup.
    var historyCoverage: HistoryCoverage? {
        HistoryCoverage.evaluate(daily: snapshot.daily)
    }

    var combinedThirtyDays: UsageSlice {
        snapshot.lastThirtyDays
    }

    var combinedMonth: UsageSlice {
        snapshot.providers.reduce(into: UsageSlice()) { result, provider in
            result.tokens = result.tokens + provider.month.tokens
            result.estimatedCost += provider.month.estimatedCost
            result.requestCount += provider.month.requestCount
        }
    }

    private static func restoredWidgetOrder(from preferences: UserDefaults) -> [MetricWidget] {
        let stored = preferences.stringArray(forKey: widgetOrderPreferenceKey) ?? []
        var seen: Set<MetricWidget> = []
        var restored = stored.compactMap(MetricWidget.init(rawValue:)).filter { seen.insert($0).inserted }
        restored.append(contentsOf: MetricWidget.allCases.filter { seen.insert($0).inserted })
        return restored
    }

    private static func restoredVisibleWidgets(from preferences: UserDefaults) -> Set<MetricWidget> {
        guard preferences.object(forKey: visibleWidgetsPreferenceKey) != nil else {
            return defaultVisibleWidgets
        }
        return Set(
            (preferences.stringArray(forKey: visibleWidgetsPreferenceKey) ?? [])
                .compactMap(MetricWidget.init(rawValue:))
        )
    }

    private static func restoredCompactWidget(
        key: String,
        default defaultWidget: MetricWidget,
        from preferences: UserDefaults
    ) -> MetricWidget? {
        guard preferences.object(forKey: key) != nil else { return defaultWidget }
        guard let rawValue = preferences.string(forKey: key), !rawValue.isEmpty else { return nil }
        return MetricWidget(rawValue: rawValue)
    }
}
