import Charts
import SwiftUI

/// Replaces the separate Spend and Tokens pages. Both presented the same
/// aggregation cut two ways, and both were the most crowded screens in the app.
struct HistoryPage: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var range: HistoryRange = .week
    @State private var breakdown: Breakdown = Breakdown(
        rawValue: ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_BREAKDOWN"] ?? "models"
    ) ?? .models

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom) {
                PageHeadline(
                    caption: range.caption,
                    value: AIFormat.currency(usage.estimatedCost),
                    detail: "\(AIFormat.tokens(usage.tokens.total)) tokens · \(usage.requestCount.formatted()) requests"
                )
                Spacer(minLength: 12)
                RangeSelector(
                    options: HistoryRange.allCases,
                    title: \.title,
                    selection: $range
                )
            }

            // Side by side rather than stacked. A 648x356 panel has width to
            // spare and none to spare vertically; stacking the chart above the
            // table needed ~400pt and overflowed.
            HStack(alignment: .top, spacing: 9) {
                chart
                    .frame(maxWidth: .infinity)
                    .cardSurface(padding: 10)
                breakdownSection
                    .frame(width: 268)
            }
        }
        .padding(.horizontal, NotchMetrics.horizontalPadding)
        .padding(.bottom, 12)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(filteredDaily) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Cost", item.estimatedCost)
                )
                .foregroundStyle(by: .value("Provider", item.provider.displayName))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                ProviderID.claude.displayName: ProviderID.claude.tint,
                ProviderID.codex.displayName: ProviderID.codex.tint
            ])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                    AxisValueLabel(
                        format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.month().day()
                    )
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(NotchDesign.divider)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(AIFormat.currency(amount, compact: true))
                                .font(NotchType.label)
                                .foregroundStyle(NotchDesign.tertiary)
                        }
                    }
                }
            }
            // One legend. The old Spend page drew a chart legend and a second
            // manual dot-and-name row beneath it.
            .chartLegend(position: .top, alignment: .trailing, spacing: 4)
        }
    }

    private var breakdownSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                ForEach(Breakdown.allCases) { option in
                    let isSelected = breakdown == option
                    Button {
                        breakdown = option
                    } label: {
                        Text(option.title)
                            .font(NotchType.label)
                            .foregroundStyle(isSelected ? Color.white : NotchDesign.tertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            switch breakdown {
            case .models:
                rows(models.prefix(Self.rowLimit)) { model in
                    ModelRow(model: model)
                }
            case .projects:
                if projects.isEmpty {
                    EmptyRow(
                        message: "No project data yet — Claude transcripts are re-read on the next scan."
                    )
                } else {
                    rows(projects.prefix(Self.rowLimit)) { project in
                        ProjectRow(project: project)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 10)
    }

    /// What the side-by-side layout affords. Capping is deliberate: the old
    /// Tokens page asked for five in a taller stack and pushed the last one
    /// through the bottom of its card.
    private static let rowLimit = 5

    @ViewBuilder
    private func rows<T: Identifiable, Row: View>(
        _ items: ArraySlice<T>,
        @ViewBuilder row: @escaping (T) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().overlay(NotchDesign.divider)
                }
                row(item)
            }
        }
    }

    private var usage: UsageSlice {
        switch range {
        case .week: viewModel.combinedWeek
        case .thirtyDays: viewModel.combinedThirtyDays
        case .all: viewModel.combinedAllTime
        }
    }

    private var models: [ModelUsage] {
        switch range {
        case .week: viewModel.snapshot.weekModels
        case .thirtyDays: viewModel.snapshot.thirtyDayModels
        case .all: viewModel.snapshot.allTimeModels
        }
    }

    private var projects: [ProjectUsage] {
        switch range {
        case .week: viewModel.snapshot.weekProjects
        case .thirtyDays: viewModel.snapshot.thirtyDayProjects
        case .all: viewModel.snapshot.allTimeProjects
        }
    }

    private var filteredDaily: [DailyUsage] {
        guard let start = range.startDate else { return viewModel.snapshot.daily }
        return viewModel.snapshot.daily.filter { $0.day >= start }
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case week
    case thirtyDays
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7D"
        case .thirtyDays: "30D"
        case .all: "All"
        }
    }

    var caption: String {
        switch self {
        case .week: "Past 7 days"
        case .thirtyDays: "Past 30 days"
        case .all: "All local history"
        }
    }

    var startDate: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        switch self {
        case .week: return Calendar.current.date(byAdding: .day, value: -6, to: today)
        case .thirtyDays: return Calendar.current.date(byAdding: .day, value: -29, to: today)
        case .all: return nil
        }
    }
}

private enum Breakdown: String, CaseIterable, Identifiable {
    case models
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Top models"
        // Codex partitions sessions by date and records no project, so this
        // view is Claude-only by construction. Say so rather than imply
        // coverage the data cannot support.
        case .projects: "Top projects (Claude)"
        }
    }
}

/// The narrow column carries name, token count, and spend on one line. Tokens
/// sit under the name rather than in a third column, which would squeeze the
/// name past the point of being readable at this width.
private struct ModelRow: View {
    let model: ModelUsage

    var body: some View {
        BreakdownRow(
            provider: model.provider,
            name: AIFormat.modelName(model.model),
            detail: "\(AIFormat.tokens(model.tokens.total)) tokens",
            cost: model.estimatedCost
        )
    }
}

private struct ProjectRow: View {
    let project: ProjectUsage

    var body: some View {
        BreakdownRow(
            provider: .claude,
            name: project.project,
            detail: "\(AIFormat.tokens(project.tokens.total)) tokens",
            cost: project.estimatedCost
        )
    }
}

private struct BreakdownRow: View {
    let provider: ProviderID
    let name: String
    let detail: String
    let cost: Double

    var body: some View {
        HStack(spacing: 8) {
            ProviderDot(provider: provider)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(NotchType.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(AIFormat.currency(cost))
                .font(NotchType.body)
                .monospacedDigit()
        }
        .frame(height: 32)
    }
}

private struct ProviderDot: View {
    let provider: ProviderID

    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(provider.tint)
            .frame(width: 16, height: 16)
            .background(provider.tint.opacity(0.14), in: Circle())
    }
}

private struct EmptyRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(NotchType.label)
            .foregroundStyle(NotchDesign.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 26 * 2)
    }
}
