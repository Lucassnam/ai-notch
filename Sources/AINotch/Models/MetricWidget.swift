import Foundation

/// Every metric the notch can present. The order is also the reset order in
/// the customization panel; the user's own order is persisted separately.
enum MetricWidget: String, CaseIterable, Codable, Identifiable, Sendable {
    case todaySpend
    case fiveHourSpend
    case fiveHourTokens
    case todayTokens
    case weekSpend
    case monthSpend
    case claudeTodaySpend
    case codexTodaySpend
    case claudeFiveHourTokens
    case codexFiveHourTokens
    case claudeLimit
    case codexLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todaySpend: "Today"
        case .fiveHourSpend: "Last 5 hours"
        case .fiveHourTokens: "5-hour tokens"
        case .todayTokens: "Today’s tokens"
        case .weekSpend: "Past 7 days"
        case .monthSpend: "This month"
        case .claudeTodaySpend: "Claude today"
        case .codexTodaySpend: "Codex today"
        case .claudeFiveHourTokens: "Claude 5-hour tokens"
        case .codexFiveHourTokens: "Codex 5-hour tokens"
        case .claudeLimit: "Claude limit"
        case .codexLimit: "Codex limit"
        }
    }

    var symbol: String {
        switch self {
        case .todaySpend: "calendar"
        case .fiveHourSpend: "clock"
        case .fiveHourTokens: "number"
        case .todayTokens: "calendar"
        case .weekSpend: "calendar.badge.clock"
        case .monthSpend: "calendar"
        case .claudeTodaySpend, .claudeFiveHourTokens, .claudeLimit: "sun.max.fill"
        case .codexTodaySpend, .codexFiveHourTokens, .codexLimit: "terminal.fill"
        }
    }

    var provider: ProviderID? {
        switch self {
        case .claudeTodaySpend, .claudeFiveHourTokens, .claudeLimit: .claude
        case .codexTodaySpend, .codexFiveHourTokens, .codexLimit: .codex
        default: nil
        }
    }
}
