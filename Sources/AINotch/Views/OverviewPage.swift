import Charts
import SwiftUI

struct OverviewPage: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                PageHeadline(
                    caption: "Last five hours",
                    value: AIFormat.currency(viewModel.combinedFiveHour.estimatedCost),
                    detail: "API spend · \(AIFormat.tokens(viewModel.combinedFiveHour.tokens.total)) tokens"
                )
                Spacer(minLength: 12)
                HStack(spacing: 22) {
                    MetricLabel(
                        title: "7 days",
                        value: AIFormat.currency(viewModel.combinedWeek.estimatedCost),
                        alignment: .trailing
                    )
                    MetricLabel(
                        title: "This month",
                        value: AIFormat.currency(viewModel.combinedMonth.estimatedCost),
                        alignment: .trailing
                    )
                }
            }

            HStack(spacing: 10) {
                ForEach(viewModel.snapshot.providers) { summary in
                    ProviderCard(summary: summary)
                }
            }

            SpendSparkCard(daily: recentDaily)
        }
        .padding(.horizontal, NotchMetrics.horizontalPadding)
        .padding(.bottom, 14)
    }

    private var recentDaily: [DailyUsage] {
        let start = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        )
        return viewModel.snapshot.daily.filter { $0.day >= start }
    }
}

/// Both providers use the same slot for the same meaning: the five-hour figure
/// is always the headline. Previously the ring position showed a quota for
/// Codex but today's spend for Claude, so identical placement meant two
/// different things depending on which card you read.
private struct ProviderCard: View {
    let summary: ProviderSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: summary.provider.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.provider.tint)
                Text(summary.provider.displayName)
                    .font(NotchType.title)
                Spacer(minLength: 0)
                if let limit = summary.currentLimit {
                    QuotaPill(limit: limit, tint: summary.provider.tint)
                }
            }

            HStack(spacing: 6) {
                Text(AIFormat.currency(summary.lastFiveHours.estimatedCost))
                    .font(NotchType.value)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("·")
                    .foregroundStyle(NotchDesign.tertiary)
                Text("\(AIFormat.tokens(summary.lastFiveHours.tokens.total)) tokens")
                    .font(NotchType.body)
                    .foregroundStyle(NotchDesign.secondary)
            }

            Text(caption)
                .font(NotchType.label)
                .foregroundStyle(NotchDesign.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 11)
    }

    /// States plainly when a provider reports no quota rather than implying one
    /// is missing or still loading.
    private var caption: String {
        guard let limit = summary.currentLimit else {
            return "No quota reported · \(AIFormat.currency(summary.today.estimatedCost)) today"
        }
        return "\(limit.shortLabel) quota · \(AIFormat.reset(limit.resetsAt).lowercased())"
    }
}

private struct QuotaPill: View {
    let limit: RateLimitWindow
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: limit.remainingPercent / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)

            Text("\(Int(limit.remainingPercent))% left")
                .font(NotchType.label)
                .monospacedDigit()
                .foregroundStyle(NotchDesign.secondary)
        }
    }
}

private struct SpendSparkCard: View {
    let daily: [DailyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spend by day")
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
                Spacer()
                Text("Last 7 days")
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
            }

            Chart(daily) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Cost", item.estimatedCost)
                )
                .foregroundStyle(item.provider.tint)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(NotchType.label)
                        .foregroundStyle(NotchDesign.tertiary)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 11)
    }
}
