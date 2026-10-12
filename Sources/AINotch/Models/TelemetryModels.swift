import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

struct TokenBreakdown: Codable, Hashable, Sendable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite5m: Int64 = 0
    var cacheWrite1h: Int64 = 0

    var cacheWrite: Int64 { cacheWrite5m + cacheWrite1h }
    var total: Int64 { input + output + cacheRead + cacheWrite }

    static func + (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h
        )
    }

    static func - (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: max(0, lhs.input - rhs.input),
            output: max(0, lhs.output - rhs.output),
            cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
            cacheWrite5m: max(0, lhs.cacheWrite5m - rhs.cacheWrite5m),
            cacheWrite1h: max(0, lhs.cacheWrite1h - rhs.cacheWrite1h)
        )
    }
}

struct UsageEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let provider: ProviderID
    let timestamp: Date
    let model: String
    let tokens: TokenBreakdown
    /// Claude keys its transcripts by project directory, so events carry the
    /// originating project. Codex partitions sessions by date and exposes no
    /// project identity, so its events are always nil. Optional is load-bearing:
    /// durable history written before this field existed must still decode.
    var project: String?
}

struct RateLimitWindow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let provider: ProviderID
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Date
    let source: String

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var compactRemainingLabel: String { "\(Int(remainingPercent.rounded()))%" }
    var remainingLabel: String { "\(compactRemainingLabel) left" }

    var shortLabel: String {
        if windowMinutes == 300 { return "5H" }
        if windowMinutes == 1_440 { return "24H" }
        if windowMinutes == 10_080 { return "7D" }
        if windowMinutes >= 1_440 { return "\(windowMinutes / 1_440)D" }
        return "\(windowMinutes / 60)H"
    }
}

struct RawTelemetry: Sendable {
    var events: [UsageEvent]
    var limits: [RateLimitWindow]
    var sourceFiles: [ProviderID: Int]
    var recordedCosts: [String: Double] = [:]
}

struct DurableUsageRecord: Codable, Hashable, Identifiable, Sendable {
    let event: UsageEvent
    let estimatedCost: Double
    let recordedAt: Date

    var id: String { event.id }
}

struct ModelUsage: Identifiable, Hashable, Sendable {
    let id: String
    let provider: ProviderID
    let model: String
    let tokens: TokenBreakdown
    let estimatedCost: Double
}

struct ProjectUsage: Identifiable, Hashable, Sendable {
    let project: String
    let tokens: TokenBreakdown
    let estimatedCost: Double
    let requestCount: Int

    var id: String { project }
}

struct DailyUsage: Identifiable, Hashable, Sendable {
    let day: Date
    let provider: ProviderID
    let tokens: TokenBreakdown
    let estimatedCost: Double

    var id: String { "\(provider.rawValue)-\(day.timeIntervalSince1970)" }
}

struct UsageSlice: Hashable, Sendable {
    var tokens: TokenBreakdown = .init()
    var estimatedCost: Double = 0
    var requestCount: Int = 0
}

struct ProviderSummary: Identifiable, Hashable, Sendable {
    let provider: ProviderID
    let lastFiveHours: UsageSlice
    let today: UsageSlice
    let week: UsageSlice
    let month: UsageSlice
    let allTime: UsageSlice
    let currentLimit: RateLimitWindow?
    let sourceFileCount: Int

    var id: ProviderID { provider }
}

struct UsageSnapshot: Sendable {
    let generatedAt: Date
    let providers: [ProviderSummary]
    let daily: [DailyUsage]
    let lastThirtyDays: UsageSlice
    let todayModels: [ModelUsage]
    let weekModels: [ModelUsage]
    let thirtyDayModels: [ModelUsage]
    let allTimeModels: [ModelUsage]
    let weekProjects: [ProjectUsage]
    let thirtyDayProjects: [ProjectUsage]
    let allTimeProjects: [ProjectUsage]
    let eventCount: Int

    static let empty = UsageSnapshot(
        generatedAt: .distantPast,
        providers: ProviderID.allCases.map {
            ProviderSummary(
                provider: $0,
                lastFiveHours: .init(),
                today: .init(),
                week: .init(),
                month: .init(),
                allTime: .init(),
                currentLimit: nil,
                sourceFileCount: 0
            )
        },
        daily: [],
        lastThirtyDays: .init(),
        todayModels: [],
        weekModels: [],
        thirtyDayModels: [],
        allTimeModels: [],
        weekProjects: [],
        thirtyDayProjects: [],
        allTimeProjects: [],
        eventCount: 0
    )
}

enum NotchPage: String, CaseIterable, Identifiable {
    case overview
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.medium"
        case .history: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}
