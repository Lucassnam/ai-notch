import Foundation

enum TelemetryParser {
    static func parseClaude(data: Data, fileID: String, project: String? = nil) -> [UsageEvent] {
        var deduplicated: [String: UsageEvent] = [:]

        for line in lines(in: data) {
            guard
                let object = jsonObject(from: line),
                string(object["type"]) == "assistant",
                let message = object["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any],
                let timestamp = date(object["timestamp"]),
                let model = string(message["model"])
            else { continue }

            let requestID = string(object["requestId"])
                ?? string(object["uuid"])
                ?? "\(timestamp.timeIntervalSince1970)-\(deduplicated.count)"

            let cacheCreation = usage["cache_creation"] as? [String: Any]
            let detailed5m = int64(cacheCreation?["ephemeral_5m_input_tokens"])
            let detailed1h = int64(cacheCreation?["ephemeral_1h_input_tokens"])
            let cacheCreationTotal = int64(usage["cache_creation_input_tokens"])
            let hasDetailedCache = detailed5m > 0 || detailed1h > 0

            let tokens = TokenBreakdown(
                input: int64(usage["input_tokens"]),
                output: int64(usage["output_tokens"]),
                cacheRead: int64(usage["cache_read_input_tokens"]),
                cacheWrite5m: hasDetailedCache ? detailed5m : cacheCreationTotal,
                cacheWrite1h: detailed1h
            )

            let event = UsageEvent(
                id: "claude:\(requestID)",
                provider: .claude,
                timestamp: timestamp,
                model: model,
                tokens: tokens,
                project: project
            )

            if let existing = deduplicated[event.id] {
                if event.tokens.total > existing.tokens.total {
                    deduplicated[event.id] = event
                }
            } else {
                deduplicated[event.id] = event
            }
        }

        return Array(deduplicated.values)
    }

    static func parseCodex(data: Data, fileID: String) -> (events: [UsageEvent], limits: [RateLimitWindow]) {
        var events: [UsageEvent] = []
        var limits: [RateLimitWindow] = []
        var currentModel = "gpt-5.6-sol"
        var previousTotal = TokenBreakdown()
        var lastTotalTokenCount: Int64 = -1

        for line in lines(in: data) {
            guard let object = jsonObject(from: line) else { continue }
            let type = string(object["type"])
            let payload = object["payload"] as? [String: Any]

            if type == "turn_context", let model = string(payload?["model"]) {
                currentModel = model
                continue
            }

            guard
                type == "event_msg",
                string(payload?["type"]) == "token_count",
                let timestamp = date(object["timestamp"])
            else { continue }

            if let rateLimits = payload?["rate_limits"] as? [String: Any] {
                limits.append(contentsOf: parseCodexLimits(rateLimits, observedAt: timestamp))
            }

            guard
                let info = payload?["info"] as? [String: Any],
                let totalUsage = info["total_token_usage"] as? [String: Any]
            else { continue }

            let currentTotal = codexTokens(totalUsage)
            let currentTotalTokenCount = int64(totalUsage["total_tokens"])
            guard currentTotalTokenCount != lastTotalTokenCount else { continue }

            let delta: TokenBreakdown
            if currentTotal.total >= previousTotal.total {
                delta = currentTotal - previousTotal
            } else {
                delta = currentTotal
            }

            if delta.total > 0 {
                events.append(
                    UsageEvent(
                        id: "codex:\(fileID):\(currentTotalTokenCount)",
                        provider: .codex,
                        timestamp: timestamp,
                        model: currentModel,
                        tokens: delta
                    )
                )
            }

            previousTotal = currentTotal
            lastTotalTokenCount = currentTotalTokenCount
        }

        return (events, limits)
    }

    private static func parseCodexLimits(
        _ rateLimits: [String: Any],
        observedAt: Date
    ) -> [RateLimitWindow] {
        let limitID = string(rateLimits["limit_id"]) ?? "codex"
        return ["primary", "secondary"].compactMap { slot in
            guard
                let window = rateLimits[slot] as? [String: Any],
                let minutes = int(window["window_minutes"]),
                minutes > 0
            else { return nil }

            let resetSeconds = int64(window["resets_at"])
            return RateLimitWindow(
                id: "codex:\(limitID):\(minutes)",
                provider: .codex,
                windowMinutes: minutes,
                usedPercent: double(window["used_percent"]),
                resetsAt: resetSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(resetSeconds)) : nil,
                observedAt: observedAt,
                source: "Codex provider record"
            )
        }
    }

    private static func codexTokens(_ usage: [String: Any]) -> TokenBreakdown {
        let fullInput = int64(usage["input_tokens"])
        let cachedInput = int64(usage["cached_input_tokens"])
        return TokenBreakdown(
            input: max(0, fullInput - cachedInput),
            output: int64(usage["output_tokens"]),
            cacheRead: cachedInput,
            cacheWrite5m: int64(usage["cache_write_input_tokens"]),
            cacheWrite1h: 0
        )
    }

    private static func lines(in data: Data) -> [Data] {
        var result: [Data] = []
        var lineStart = data.startIndex

        while lineStart < data.endIndex,
              let newline = data[lineStart...].firstIndex(of: 0x0A) {
            if newline > lineStart {
                result.append(data.subdata(in: lineStart..<newline))
            }
            lineStart = data.index(after: newline)
        }

        if lineStart < data.endIndex {
            result.append(data.subdata(in: lineStart..<data.endIndex))
        }
        return result
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return ISO8601DateFormatter.withFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
