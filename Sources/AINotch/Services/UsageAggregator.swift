import Foundation

struct UsageAggregator: Sendable {
    let calendar: Calendar
    let pricing: PricingCatalog

    init(calendar: Calendar = .current, pricing: PricingCatalog = .init()) {
        self.calendar = calendar
        self.pricing = pricing
    }

    func snapshot(from raw: RawTelemetry, now: Date = Date()) -> UsageSnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? startOfToday
        let eventsThroughNow = raw.events.filter { $0.timestamp <= now }

        let providers = ProviderID.allCases.map { provider in
            let events = eventsThroughNow.filter { $0.provider == provider }
            return ProviderSummary(
                provider: provider,
                lastFiveHours: slice(events.filter { $0.timestamp >= fiveHoursAgo }, recordedCosts: raw.recordedCosts),
                today: slice(events.filter { $0.timestamp >= startOfToday }, recordedCosts: raw.recordedCosts),
                week: slice(events.filter { $0.timestamp >= weekStart }, recordedCosts: raw.recordedCosts),
                month: slice(events.filter { $0.timestamp >= monthStart }, recordedCosts: raw.recordedCosts),
                allTime: slice(events, recordedCosts: raw.recordedCosts),
                currentLimit: preferredLimit(
                    raw.limits.filter { $0.provider == provider },
                    now: now
                ),
                sourceFileCount: raw.sourceFiles[provider, default: 0]
            )
        }

        let dailyGroups = Dictionary(grouping: eventsThroughNow) { event in
            DailyKey(provider: event.provider, day: calendar.startOfDay(for: event.timestamp))
        }
        let daily = dailyGroups.map { key, events in
            let usage = slice(events, recordedCosts: raw.recordedCosts)
            return DailyUsage(
                day: key.day,
                provider: key.provider,
                tokens: usage.tokens,
                estimatedCost: usage.estimatedCost
            )
        }.sorted { $0.day < $1.day }

        // Hoisted rather than inlined into the initialiser: with this many
        // arguments the type checker gives up on the expression as a whole.
        let costs = raw.recordedCosts
        let todayEvents = eventsThroughNow.filter { $0.timestamp >= startOfToday }
        let weekEvents = eventsThroughNow.filter { $0.timestamp >= weekStart }
        let thirtyDayEvents = eventsThroughNow.filter { $0.timestamp >= thirtyDayStart }

        return UsageSnapshot(
            generatedAt: now,
            providers: providers,
            daily: daily,
            lastThirtyDays: slice(thirtyDayEvents, recordedCosts: costs),
            todayModels: modelUsage(from: todayEvents, recordedCosts: costs),
            weekModels: modelUsage(from: weekEvents, recordedCosts: costs),
            thirtyDayModels: modelUsage(from: thirtyDayEvents, recordedCosts: costs),
            allTimeModels: modelUsage(from: eventsThroughNow, recordedCosts: costs),
            weekProjects: projectUsage(from: weekEvents, recordedCosts: costs),
            thirtyDayProjects: projectUsage(from: thirtyDayEvents, recordedCosts: costs),
            allTimeProjects: projectUsage(from: eventsThroughNow, recordedCosts: costs),
            eventCount: eventsThroughNow.count
        )
    }

    /// Only Claude events carry a project. Events without one — every Codex
    /// event, plus Claude history recorded before attribution existed — are
    /// omitted rather than bucketed into a fake "unknown" project, so the
    /// totals shown are always attributable.
    private func projectUsage(
        from events: [UsageEvent],
        recordedCosts: [String: Double]
    ) -> [ProjectUsage] {
        Dictionary(grouping: events.filter { $0.project != nil }) { $0.project ?? "" }
            .map { project, events in
                let usage = slice(events, recordedCosts: recordedCosts)
                return ProjectUsage(
                    project: project,
                    tokens: usage.tokens,
                    estimatedCost: usage.estimatedCost,
                    requestCount: usage.requestCount
                )
            }
            .sorted { $0.estimatedCost > $1.estimatedCost }
    }

    /// Claude writes `<synthetic>` for locally generated assistant turns that
    /// never hit a model. They carry no tokens and no cost, so listing them
    /// among real models is pure noise.
    private static func isRealModel(_ model: String) -> Bool {
        !model.hasPrefix("<")
    }

    private func modelUsage(
        from events: [UsageEvent],
        recordedCosts: [String: Double]
    ) -> [ModelUsage] {
        Dictionary(grouping: events.filter { Self.isRealModel($0.model) }) { event in
            ModelKey(provider: event.provider, model: event.model)
        }
        .map { key, events in
            let usage = slice(events, recordedCosts: recordedCosts)
            return ModelUsage(
                id: "\(key.provider.rawValue):\(key.model)",
                provider: key.provider,
                model: key.model,
                tokens: usage.tokens,
                estimatedCost: usage.estimatedCost
            )
        }
        .sorted { $0.tokens.total > $1.tokens.total }
    }

    private func slice(
        _ events: [UsageEvent],
        recordedCosts: [String: Double]
    ) -> UsageSlice {
        events.reduce(into: UsageSlice()) { result, event in
            result.tokens = result.tokens + event.tokens
            result.estimatedCost += recordedCosts[event.id] ?? pricing.estimatedCost(for: event)
            result.requestCount += 1
        }
    }

    private func preferredLimit(_ limits: [RateLimitWindow], now: Date) -> RateLimitWindow? {
        let fresh = limits.filter { now.timeIntervalSince($0.observedAt) < 14 * 24 * 60 * 60 }
        guard let latestObservation = fresh.map(\.observedAt).max() else { return nil }
        let currentRecordSet = fresh.filter {
            latestObservation.timeIntervalSince($0.observedAt) < 10 * 60
        }
        if let fiveHour = currentRecordSet
            .filter({ $0.windowMinutes == 300 })
            .max(by: { $0.observedAt < $1.observedAt }) {
            return fiveHour
        }
        return currentRecordSet.max { lhs, rhs in
            if lhs.observedAt == rhs.observedAt {
                return lhs.windowMinutes > rhs.windowMinutes
            }
            return lhs.observedAt < rhs.observedAt
        }
    }
}

private struct DailyKey: Hashable {
    let provider: ProviderID
    let day: Date
}

private struct ModelKey: Hashable {
    let provider: ProviderID
    let model: String
}
