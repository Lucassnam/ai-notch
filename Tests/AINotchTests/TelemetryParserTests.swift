import Foundation
import XCTest
@testable import AINotch

final class TelemetryParserTests: XCTestCase {
    func testClaudeDeduplicatesRepeatedRequestAndPreservesCacheKinds() throws {
        let line = #"{"type":"assistant","requestId":"req_same","uuid":"one","timestamp":"2026-08-11T20:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":50}}}}"#
        let duplicate = line.replacingOccurrences(of: #""uuid":"one""#, with: #""uuid":"two""#)
        let events = TelemetryParser.parseClaude(
            data: Data("\(line)\n\(duplicate)\n".utf8),
            fileID: "session.jsonl"
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tokens.input, 10)
        XCTAssertEqual(events[0].tokens.output, 20)
        XCTAssertEqual(events[0].tokens.cacheRead, 300)
        XCTAssertEqual(events[0].tokens.cacheWrite1h, 50)
        XCTAssertEqual(events[0].tokens.cacheWrite5m, 0)
    }

    func testClaudePreservesHistoricalModelIdentifier() throws {
        let line = #"{"type":"assistant","requestId":"req_old","timestamp":"2026-07-01T20:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":0}}}"#
        let events = TelemetryParser.parseClaude(
            data: Data("\(line)\n".utf8),
            fileID: "historical-session.jsonl"
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "claude-opus-4-8")
        XCTAssertEqual(events[0].tokens.total, 60)
    }

    func testCodexUsesCumulativeDeltasAndReadsProviderLimit() throws {
        let jsonl = #"""
        {"timestamp":"2026-08-11T20:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-terra"}}
        {"timestamp":"2026-08-11T20:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":10,"total_tokens":110}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":25,"window_minutes":300,"resets_at":1787089891},"secondary":null}}}
        {"timestamp":"2026-08-11T20:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":10,"total_tokens":110}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":25,"window_minutes":300,"resets_at":1787089891},"secondary":null}}}
        {"timestamp":"2026-08-11T20:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":70,"cache_write_input_tokens":5,"output_tokens":25,"total_tokens":205}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":30,"window_minutes":300,"resets_at":1787089891},"secondary":null}}}
        """#

        let parsed = TelemetryParser.parseCodex(data: Data(jsonl.utf8), fileID: "rollout.jsonl")

        XCTAssertEqual(parsed.events.count, 2)
        XCTAssertEqual(parsed.events[0].tokens.input, 60)
        XCTAssertEqual(parsed.events[0].tokens.cacheRead, 40)
        XCTAssertEqual(parsed.events[1].tokens.input, 50)
        XCTAssertEqual(parsed.events[1].tokens.cacheRead, 30)
        XCTAssertEqual(parsed.events[1].tokens.output, 15)
        XCTAssertEqual(parsed.limits.last?.windowMinutes, 300)
        XCTAssertEqual(parsed.limits.last?.remainingPercent, 70)
    }
}
