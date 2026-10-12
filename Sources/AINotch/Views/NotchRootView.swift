import SwiftUI

/// One spacing and sizing system for both states.
///
/// The opened panel runs on two numbers: `contentInset` (16) from every painted
/// edge, and `cardGap` (8) between neighbours. Corner radii are concentric with
/// them: the panel's bottom corners are the card radius plus the inset.
enum NotchMetrics {
    static let expandedWidth: CGFloat = 448
    /// Everything under the chrome strip. Sized so that three rows of short
    /// cards, or the Quick page's three groups and status line, exactly fit;
    /// at 368 each page carried 30-50pt it had nothing to put in.
    static let dashboardContentHeight: CGFloat = 336
    static let collapsedFallbackHeight: CGFloat = 32
    static let collapsedFallbackWidth: CGFloat = 320

    /// `TopConnectedNotchShape` curves the panel inward from the outer edge by
    /// this much, so the first `shoulderRadius` points of the frame are not
    /// painted. Anything centred on the frame is therefore biased outward by
    /// half of it — which is exactly the bug this constant exists to prevent.
    static let shoulderRadius: CGFloat = 12
    static let compactShoulderRadius: CGFloat = 11

    /// Distance from a *painted* edge to content, on the sides and the bottom.
    static let contentInset: CGFloat = MacSpacing.item
    /// The same inset measured from the frame, which is what `.padding` takes.
    ///
    /// The body is narrower than the frame by one shoulder per side. A flat
    /// 24pt frame padding against an 18pt shoulder left the cards 6pt from the
    /// panel's visible edge while the bottom margin was 16pt — the sides read
    /// as cramped because they were.
    static let outerPadding: CGFloat = shoulderRadius + contentInset
    /// The one gap between sibling surfaces inside the opened panel.
    static let cardGap: CGFloat = MacSpacing.related
    /// Space between the chrome strip and the first row of a page. The strip
    /// already holds 6pt under its buttons, so this lands near `contentInset`.
    static let pageTopInset: CGFloat = MacSpacing.related
    static let tabBarHeight: CGFloat = 36
    /// Concentric with the cards: their radius plus the inset between them
    /// and the panel edge.
    static let bottomCornerRadius: CGFloat = NotchDesign.cardRadius + contentInset
    /// Past this many widgets the grid scrolls instead of shrinking further.
    static let widgetsBeforeScrolling = 6
    /// Equal breathing room on both sides of a compact value. Equal is
    /// load-bearing: it makes "centred in the padded slot" and "centred in the
    /// visible gutter" the same point, so the two ways of reading the layout
    /// cannot disagree.
    static let compactSlotInset: CGFloat = 6
    /// Room for the widest value a slot routinely shows.
    ///
    /// Tuned down from 58 with the inset: at 89pt per side the values sat in
    /// a field of empty bar. This is the smallest slot that still renders
    /// `$74.87` and `999.9M` at full 13pt, which is the floor the type scale
    /// sets — going narrower buys width by dropping text under 11pt.
    static let compactSlotWidth: CGFloat = 44
    static let compactFontSize: CGFloat = 13
    static let leadingCompactFontSize: CGFloat = compactFontSize
    static let trailingCompactFontSize: CGFloat = compactFontSize
    /// Kept as an alias for the dormant legacy page views, which still compile
    /// even though the active interface is the widget dashboard.
    static let horizontalPadding: CGFloat = outerPadding
    static let notchClearance: CGFloat = MacSpacing.item

    /// The painted width beside the notch: the unpainted shoulder curve, then
    /// an inset, the value, and an equal inset before the notch begins.
    static let compactGutter: CGFloat =
        compactShoulderRadius + compactSlotInset * 2 + compactSlotWidth

    static func topStripHeight(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, 40)
    }

    static func expandedHeight(notchHeight: CGFloat) -> CGFloat {
        topStripHeight(notchHeight: notchHeight) + dashboardContentHeight
    }

    /// Height of one row of widget cards.
    ///
    /// The rows divide the page exactly: two tall rows for up to four widgets,
    /// three short ones beyond that. A fixed 118pt card left a 45pt dead band
    /// above the tab bar with four widgets and clipped a third row with six.
    static func widgetRowHeight(available: CGFloat, widgetCount: Int) -> CGFloat {
        let rows = CGFloat(min(3, max(2, (widgetCount + 1) / 2)))
        return max(0, (available - cardGap * (rows - 1)) / rows)
    }

    /// Exactly the notch plus one gutter per side. The previous `notchWidth + 200`
    /// reserved 100pt per side, which buried the Apple menu and the leftmost
    /// status items under an opaque block for no layout benefit.
    static func collapsedWidth(notchWidth: CGFloat) -> CGFloat {
        guard notchWidth > 0 else { return collapsedFallbackWidth }
        return notchWidth + compactGutter * 2
    }

    /// Where the two compact values sit, and how wide they may be.
    ///
    /// Both centres are taken from the *painted* gutter — from the end of the
    /// shoulder curve to the edge of the notch — not from the frame. The notch
    /// is located by its measured centre rather than assumed to sit on the
    /// panel's midpoint, so a notch that is not perfectly centred on the
    /// display still gets two evenly placed values.
    struct CompactSlots: Equatable {
        var leadingCenter: CGFloat
        var trailingCenter: CGFloat
        var width: CGFloat
    }

    static func compactSlots(
        width: CGFloat,
        notchWidth: CGFloat,
        notchCenterOffset: CGFloat = 0
    ) -> CompactSlots {
        let paintedLeading = compactShoulderRadius
        let paintedTrailing = width - compactShoulderRadius
        let midX = width / 2 + notchCenterOffset
        // With no hardware notch there is nothing to route around, so the two
        // values keep the same gutter width they would have beside one.
        let gap = notchWidth > 0
            ? notchWidth
            : max(0, width - compactGutter * 2)

        let notchLeading = min(max(paintedLeading, midX - gap / 2), paintedTrailing)
        let notchTrailing = max(min(paintedTrailing, midX + gap / 2), paintedLeading)

        let leadingSpan = max(0, notchLeading - paintedLeading)
        let trailingSpan = max(0, paintedTrailing - notchTrailing)
        let usable = max(0, min(leadingSpan, trailingSpan) - compactSlotInset * 2)

        return CompactSlots(
            leadingCenter: paintedLeading + leadingSpan / 2,
            trailingCenter: notchTrailing + trailingSpan / 2,
            width: usable
        )
    }

    /// The same painted-gutter maths for the opened panel, where the chrome
    /// buttons straddle the notch. Zero on displays without one.
    static func expandedGutterWidth(notchWidth: CGFloat) -> CGFloat {
        guard notchWidth > 0 else { return 0 }
        return max(0, (expandedWidth - notchWidth) / 2 - shoulderRadius)
    }

    static func shoulderWidth(notchWidth: CGFloat) -> CGFloat {
        let usable = expandedWidth - outerPadding * 2
        let reserved = max(0, notchWidth) + notchClearance * 2
        return max(0, (usable - reserved) / 2)
    }
}

struct NotchRootView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onCustomize: () -> Void

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    ExpandedNotchView(viewModel: viewModel, onCustomize: onCustomize)
                        .opacity(viewModel.isExpanded ? 1 : 0)
                        .scaleEffect(viewModel.isExpanded ? 1 : 0.98, anchor: .top)
                        .allowsHitTesting(viewModel.isExpanded)
                        .accessibilityHidden(!viewModel.isExpanded)

                    CollapsedNotchView(viewModel: viewModel)
                        .opacity(viewModel.isExpanded ? 0 : 1)
                        .allowsHitTesting(!viewModel.isExpanded)
                        .accessibilityHidden(viewModel.isExpanded)
                }
            }
            .overlay(alignment: .top) {
                if NotchDebug.showsHardwareNotch, viewModel.notchWidth > 0 {
                    HardwareNotchSilhouette(
                        width: viewModel.notchWidth,
                        height: viewModel.notchHeight
                    )
                    .offset(x: viewModel.notchCenterOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.22), value: viewModel.isExpanded)
            .onHover { viewModel.setHovering($0) }
            .preferredColorScheme(.dark)
    }
}

// MARK: - Capture aid

enum NotchDebug {
    /// A screenshot never contains the hardware notch: the display has no
    /// pixels there, so a capture shows the panel as one unbroken strip and a
    /// value hidden behind the notch looks perfectly placed. With this set the
    /// app paints the notch itself, at the position it measured, so a capture
    /// shows what the eye sees. On a real notch the paint is hidden behind it.
    static let showsHardwareNotch =
        ProcessInfo.processInfo.environment["AINOTCH_SHOW_NOTCH"] == "1"
}

private struct HardwareNotchSilhouette: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 10,
            style: .continuous
        )
        .fill(Color(red: 0.86, green: 0.12, blue: 0.42))
        .frame(width: width, height: height)
    }
}

// MARK: - Compact notch

private struct CollapsedNotchView: View {
    @ObservedObject var viewModel: UsageViewModel

    private var width: CGFloat {
        NotchMetrics.collapsedWidth(notchWidth: viewModel.notchWidth)
    }

    private var slots: NotchMetrics.CompactSlots {
        NotchMetrics.compactSlots(
            width: width,
            notchWidth: viewModel.notchWidth,
            notchCenterOffset: viewModel.notchCenterOffset
        )
    }

    var body: some View {
        let slots = slots
        // Absolute placement rather than HStack + Spacer. A spacer centres each
        // value in its *frame* gutter, which runs to the panel edge; the panel
        // is not painted for the first `compactShoulderRadius` points, so the
        // frame centre and the visible centre are 6pt apart at a 185pt notch.
        ZStack(alignment: .topLeading) {
            Color.clear

            CompactMetricSlot(widget: viewModel.leadingCompactWidget, viewModel: viewModel)
                .frame(width: slots.width)
                .position(x: slots.leadingCenter, y: viewModel.notchHeight / 2)

            CompactMetricSlot(widget: viewModel.trailingCompactWidget, viewModel: viewModel)
                .frame(width: slots.width)
                .position(x: slots.trailingCenter, y: viewModel.notchHeight / 2)
        }
        .frame(width: width, height: viewModel.notchHeight)
        .background { NotchBackground(isTranslucent: viewModel.isTranslucent) }
        .clipShape(
            TopConnectedNotchShape(
                topShoulderRadius: NotchMetrics.compactShoulderRadius,
                bottomCornerRadius: NotchMetrics.compactShoulderRadius
            )
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleExpanded() }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens AI Notch")
    }
}

private struct CompactMetricSlot: View {
    let widget: MetricWidget?
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        if let widget {
            let metric = viewModel.presentation(for: widget)
            // Until the first scan lands every total is zero, and "$0.00" is a
            // claim about spending rather than a sign that nothing has loaded.
            Text(viewModel.hasLoaded ? metric.compactValue : "–")
                .font(NotchType.compact)
                .foregroundStyle(
                    viewModel.hasLoaded ? metric.tint.opacity(0.96) : NotchDesign.tertiary
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                // One scale factor for both slots. Two independent ones let a
                // long currency value shrink on one side while the other stayed
                // full size, which is what read as "uneven".
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(widget.title), \(metric.value)")
        } else {
            Color.clear
        }
    }
}

// MARK: - Main pop-out

private struct ExpandedNotchView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onCustomize: () -> Void
    @State private var selectedTab = ExpandedTab(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_TAB"] ?? "widgets"
    ) ?? .widgets

    private var panelHeight: CGFloat {
        NotchMetrics.expandedHeight(notchHeight: viewModel.notchHeight)
    }

    var body: some View {
        GlassGroup(spacing: MacSpacing.item) {
            VStack(spacing: 0) {
                topStrip
                VStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case .widgets:
                            WidgetDashboard(viewModel: viewModel)
                        case .graph:
                            UsageGraphPage(viewModel: viewModel)
                        case .quick:
                            QuickSettingsPage(viewModel: viewModel, onCustomize: onCustomize)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ExpandedTabBar(selection: $selectedTab)
                }
                .frame(
                    width: NotchMetrics.expandedWidth,
                    height: NotchMetrics.dashboardContentHeight,
                    alignment: .top
                )
                .clipped()
                .onAppear {
                    guard let raw = ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_TAB"],
                          let requestedTab = ExpandedTab(rawValue: raw) else { return }
                    selectedTab = requestedTab
                }
            }
            .frame(width: NotchMetrics.expandedWidth, height: panelHeight, alignment: .top)
        }
        .frame(width: NotchMetrics.expandedWidth, height: panelHeight)
        .background {
            MetalPanelBackground(
                isTranslucent: viewModel.isTranslucent,
                blackStrip: NotchMetrics.topStripHeight(notchHeight: viewModel.notchHeight),
                height: panelHeight
            )
        }
        .clipShape(panelShape)
        .overlay {
            // The lower edge catches a little light; the top stays unlined so
            // the panel still reads as one piece with the notch.
            panelShape
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.15),
                            .init(color: Color.white.opacity(0.16), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .clipShape(panelShape)
                .allowsHitTesting(false)
        }
    }

    private var panelShape: TopConnectedNotchShape {
        TopConnectedNotchShape(
            topShoulderRadius: NotchMetrics.shoulderRadius,
            bottomCornerRadius: NotchMetrics.bottomCornerRadius
        )
    }

    /// One control per side, each on the content margin so it lines up with
    /// the cards beneath it. They were centred in the gutter beside the notch,
    /// which put them on no line the rest of the panel uses.
    private var topStrip: some View {
        HStack(spacing: 0) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(
                        viewModel.isLoading
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isLoading
                    )
            }
            .buttonStyle(ChromeButtonStyle())
            .help("Refresh now")

            Spacer(minLength: 0)

            Button { viewModel.togglePinned() } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(ChromeButtonStyle(active: viewModel.isPinned))
            .help(viewModel.isPinned ? "Unpin" : "Keep open")
        }
        .padding(.horizontal, NotchMetrics.outerPadding)
        .frame(height: NotchMetrics.topStripHeight(notchHeight: viewModel.notchHeight))
    }
}

private struct WidgetDashboard: View {
    @ObservedObject var viewModel: UsageViewModel

    private let columns = [
        GridItem(.flexible(), spacing: NotchMetrics.cardGap),
        GridItem(.flexible(), spacing: NotchMetrics.cardGap)
    ]

    var body: some View {
        let widgets = viewModel.orderedVisibleWidgets
        Group {
            if widgets.isEmpty {
                VStack(spacing: MacSpacing.related) {
                    Text("No widgets chosen")
                        .font(NotchType.title)
                        .foregroundStyle(Color.white)
                    Text("Pick some under Quick › Customize widgets.")
                        .font(NotchType.body)
                        .foregroundStyle(NotchDesign.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let rowHeight = NotchMetrics.widgetRowHeight(
                        available: proxy.size.height,
                        widgetCount: widgets.count
                    )
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: NotchMetrics.cardGap) {
                            ForEach(widgets) { widget in
                                MetricWidgetCard(
                                    widget: widget,
                                    viewModel: viewModel,
                                    height: rowHeight
                                )
                            }
                        }
                    }
                    .scrollDisabled(widgets.count <= NotchMetrics.widgetsBeforeScrolling)
                }
            }
        }
        .padding(.horizontal, NotchMetrics.outerPadding)
        .padding(.top, NotchMetrics.pageTopInset)
    }
}

private struct MetricWidgetCard: View {
    let widget: MetricWidget
    @ObservedObject var viewModel: UsageViewModel
    let height: CGFloat

    /// Three rows to a page leaves no room for the 30pt figure or the bar.
    private var isShort: Bool { height < 110 }

    var body: some View {
        let metric = viewModel.presentation(for: widget)
        // Title and figure sit together at the top, the breakdown at the
        // bottom. Splitting title and figure to opposite ends left a hole in
        // the middle of every card.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // The same dot the graph legend uses, so a provider reads as
                // one colour everywhere. Combined figures carry none.
                if let provider = widget.provider {
                    Circle()
                        .fill(provider.tint)
                        .frame(width: 7, height: 7)
                }
                Text(widget.title)
                    .font(NotchType.body)
                    .foregroundStyle(NotchDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            Text(metric.value)
                .font(isShort ? NotchType.displayShort : NotchType.display)
                .foregroundStyle(metric.cardTint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, isShort ? 1 : 2)
            Spacer(minLength: 0)
            if !isShort {
                ShareBar(shares: metric.shares)
                    .padding(.bottom, MacSpacing.related)
            }
            if let detail = metric.detail {
                Text(detail)
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, NotchDesign.cardPadding)
        .padding(.vertical, isShort ? MacSpacing.control : NotchDesign.cardPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .metalCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metric presentation

private struct MetricPresentation {
    let value: String
    let compactValue: String
    /// What the figure is made of: tokens under a spend, spend under a token
    /// count, the reset time under a limit. A card that is only a number makes
    /// the reader guess which of four near-identical numbers it is.
    let detail: String?
    /// Colour of the value beside the notch, where the tint is the only thing
    /// saying which provider a bare number belongs to.
    let tint: Color
    /// Colour of the figure on a card. White unless it is a warning or a
    /// placeholder: the card already names its provider with a dot.
    let cardTint: Color
    /// How the figure divides: between providers for a total, against the
    /// combined total for one provider, against the allowance for a limit.
    let shares: [ShareBar.Share]

    init(
        value: String,
        compactValue: String? = nil,
        detail: String? = nil,
        tint: Color,
        cardTint: Color = .white,
        shares: [ShareBar.Share] = []
    ) {
        self.value = value
        self.compactValue = compactValue ?? value
        self.detail = detail
        self.tint = tint
        self.cardTint = cardTint
        self.shares = shares
    }
}

private enum Measure {
    case cost
    case tokens

    func amount(_ slice: UsageSlice) -> Double {
        switch self {
        case .cost: slice.estimatedCost
        case .tokens: Double(slice.tokens.total)
        }
    }
}

private extension UsageViewModel {
    func presentation(for widget: MetricWidget) -> MetricPresentation {
        switch widget {
        case .todaySpend:
            return spend(combinedToday, window: \.today, detail: tokensDetail(combinedToday))
        case .fiveHourSpend:
            return spend(
                combinedFiveHour,
                window: \.lastFiveHours,
                detail: tokensDetail(combinedFiveHour)
            )
        case .fiveHourTokens:
            return tokens(combinedFiveHour, window: \.lastFiveHours)
        case .todayTokens:
            return MetricPresentation(
                value: AIFormat.tokens(combinedToday.tokens.total),
                detail: requestsDetail(combinedToday),
                tint: .white,
                shares: shares(of: \.today, by: .tokens)
            )
        case .weekSpend:
            return spend(
                combinedWeek,
                window: \.week,
                detail: "\(AIFormat.currency(combinedWeek.estimatedCost / 7)) a day"
            )
        case .monthSpend:
            return spend(combinedMonth, window: \.month, detail: tokensDetail(combinedMonth))
        case .claudeTodaySpend:
            return providerSpend(.claude)
        case .codexTodaySpend:
            return providerSpend(.codex)
        case .claudeFiveHourTokens:
            return providerTokens(.claude)
        case .codexFiveHourTokens:
            return providerTokens(.codex)
        case .claudeLimit:
            return providerLimit(.claude)
        case .codexLimit:
            return providerLimit(.codex)
        }
    }

    /// Each provider's share of a window's combined total. With `only`, the
    /// bar shows that one provider against everything, the rest left as track.
    private func shares(
        of window: KeyPath<ProviderSummary, UsageSlice>,
        by measure: Measure,
        only: ProviderID? = nil
    ) -> [ShareBar.Share] {
        let amounts = snapshot.providers.map {
            (provider: $0.provider, amount: measure.amount($0[keyPath: window]))
        }
        let total = amounts.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        return amounts.enumerated().compactMap { index, entry in
            guard only == nil || only == entry.provider else { return nil }
            return ShareBar.Share(
                id: index,
                color: entry.provider.tint,
                fraction: entry.amount / total
            )
        }
    }

    private func tokensDetail(_ slice: UsageSlice) -> String {
        "\(AIFormat.tokens(slice.tokens.total)) tokens"
    }

    private func requestsDetail(_ slice: UsageSlice) -> String {
        slice.requestCount == 1 ? "1 request" : "\(slice.requestCount.formatted()) requests"
    }

    private func spend(
        _ slice: UsageSlice,
        window: KeyPath<ProviderSummary, UsageSlice>,
        detail: String,
        only provider: ProviderID? = nil
    ) -> MetricPresentation {
        MetricPresentation(
            value: AIFormat.currency(slice.estimatedCost),
            compactValue: AIFormat.currency(slice.estimatedCost, compact: true),
            detail: detail,
            tint: provider?.tint ?? .white,
            shares: shares(of: window, by: .cost, only: provider)
        )
    }

    private func tokens(
        _ slice: UsageSlice,
        window: KeyPath<ProviderSummary, UsageSlice>,
        only provider: ProviderID? = nil
    ) -> MetricPresentation {
        MetricPresentation(
            value: AIFormat.tokens(slice.tokens.total),
            detail: "\(AIFormat.currency(slice.estimatedCost)) at API rates",
            tint: provider?.tint ?? .white,
            shares: shares(of: window, by: .tokens, only: provider)
        )
    }

    private func summary(for provider: ProviderID) -> ProviderSummary? {
        snapshot.providers.first { $0.provider == provider }
    }

    private func providerSpend(_ provider: ProviderID) -> MetricPresentation {
        let today = summary(for: provider)?.today ?? UsageSlice()
        return spend(today, window: \.today, detail: tokensDetail(today), only: provider)
    }

    private func providerTokens(_ provider: ProviderID) -> MetricPresentation {
        tokens(
            summary(for: provider)?.lastFiveHours ?? UsageSlice(),
            window: \.lastFiveHours,
            only: provider
        )
    }

    private func providerLimit(_ provider: ProviderID) -> MetricPresentation {
        guard let limit = summary(for: provider)?.currentLimit else {
            return MetricPresentation(
                value: "–",
                detail: "Not in the local logs",
                tint: NotchDesign.tertiary,
                cardTint: NotchDesign.tertiary
            )
        }
        let isLow = limit.remainingPercent <= 10
        return MetricPresentation(
            value: limit.remainingLabel,
            compactValue: limit.compactRemainingLabel,
            detail: AIFormat.reset(limit.resetsAt),
            tint: isLow ? .orange : provider.tint,
            cardTint: isLow ? .orange : .white,
            shares: [
                ShareBar.Share(
                    id: 0,
                    color: isLow ? .orange : provider.tint,
                    fraction: limit.remainingPercent / 100
                )
            ]
        )
    }
}

/// The opened panel's ground: black where it meets the notch, graphite with a
/// fine grain below. The collapsed bar keeps `NotchBackground`, because all of
/// it sits beside the notch and has to match it exactly.
private struct MetalPanelBackground: View {
    let isTranslucent: Bool
    /// Height that stays pure black so the panel and the notch read as one.
    let blackStrip: CGFloat
    let height: CGFloat

    private var stripEnd: CGFloat {
        height > 0 ? min(1, blackStrip / height) : 0
    }

    private var ramp: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: stripEnd),
                .init(color: .black, location: min(1, stripEnd + 0.22)),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            if isTranslucent {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.18)
            } else {
                Color.black
                NotchDesign.graphite.mask(ramp)
            }
            GrainOverlay().mask(ramp)
        }
    }
}

private struct NotchBackground: View {
    let isTranslucent: Bool

    var body: some View {
        if isTranslucent {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.18)
            }
        } else {
            Color.black
        }
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.white : NotchDesign.secondary)
            .frame(width: 28, height: 28)
            .background(
                active
                    ? NotchDesign.controlActive
                    : (configuration.isPressed ? NotchDesign.controlPressed : NotchDesign.control),
                in: Circle()
            )
    }
}
