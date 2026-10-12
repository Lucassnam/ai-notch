import XCTest
@testable import AINotch

final class ProjectAttributionTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/alice/.claude/projects", isDirectory: true)

    func testProjectNameIsTheLeafOfTheMangledDirectory() {
        let file = root
            .appendingPathComponent("-Users-alice-Desktop-Active-trajectory")
            .appendingPathComponent("session.jsonl")
        XCTAssertEqual(TelemetryScanner.projectName(for: file, below: root), "trajectory")
    }

    func testNestedSessionDirectoriesStillResolveToTheProject() {
        let file = root
            .appendingPathComponent("-Users-alice-Desktop-penlo")
            .appendingPathComponent("subdir")
            .appendingPathComponent("session.jsonl")
        XCTAssertEqual(TelemetryScanner.projectName(for: file, below: root), "penlo")
    }

    func testFileDirectlyInRootHasNoProject() {
        let file = root.appendingPathComponent("stray.jsonl")
        XCTAssertNil(TelemetryScanner.projectName(for: file, below: root))
    }

    /// The mangling maps `_` to `-` as well as `/`, so an account name like
    /// `ada_99` produced a project literally named "999".
    func testHomeDirectoryProjectIsNamedHomeNotATrailingDigitRun() {
        let root = URL(
            fileURLWithPath: "/Users/ada_99/.claude/projects",
            isDirectory: true
        )
        let file = root
            .appendingPathComponent("-Users-ada-99")
            .appendingPathComponent("session.jsonl")
        XCTAssertEqual(TelemetryScanner.projectName(for: file, below: root), "Home")
    }

    func testUnderscoredAccountNameDoesNotLeakIntoProjectName() {
        let root = URL(
            fileURLWithPath: "/Users/ada_99/.claude/projects",
            isDirectory: true
        )
        let file = root
            .appendingPathComponent("-Users-ada-99-Desktop-Active-sample")
            .appendingPathComponent("session.jsonl")
        XCTAssertEqual(TelemetryScanner.projectName(for: file, below: root), "sample")
    }

    func testFileOutsideRootHasNoProject() {
        let file = URL(fileURLWithPath: "/Users/alice/.codex/sessions/2026/05/13/rollout.jsonl")
        XCTAssertNil(TelemetryScanner.projectName(for: file, below: root))
    }

    /// Durable history written before attribution existed has no `project` key.
    /// Decoding must succeed with nil rather than throw, because the history
    /// store treats a decode failure as permanent corruption.
    func testLegacyEventWithoutProjectKeyStillDecodes() throws {
        let legacy = """
        {"id":"claude:1","provider":"claude","timestamp":0,\
        "model":"claude-opus-5","tokens":{"input":10,"output":5,\
        "cacheRead":0,"cacheWrite5m":0,"cacheWrite1h":0}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(UsageEvent.self, from: legacy)
        XCTAssertNil(event.project)
        XCTAssertEqual(event.tokens.input, 10)
    }

    /// Codex events carry no project, so they must not appear in project
    /// totals — otherwise the breakdown would silently under-report by
    /// bucketing them under an invented name.
    func testProjectTotalsExcludeEventsWithoutAProject() {
        let now = Date()
        let events = [
            UsageEvent(
                id: "claude:1", provider: .claude, timestamp: now,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 100, output: 100),
                project: "trajectory"
            ),
            UsageEvent(
                id: "codex:1", provider: .codex, timestamp: now,
                model: "gpt-5.6-sol",
                tokens: TokenBreakdown(input: 100, output: 100),
                project: nil
            )
        ]

        let snapshot = UsageAggregator().snapshot(
            from: RawTelemetry(events: events, limits: [], sourceFiles: [:]),
            now: now
        )

        XCTAssertEqual(snapshot.allTimeProjects.count, 1)
        XCTAssertEqual(snapshot.allTimeProjects.first?.project, "trajectory")
    }

    func testProjectTotalsAreSortedByCostDescending() {
        let now = Date()
        let events = [
            UsageEvent(
                id: "claude:small", provider: .claude, timestamp: now,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 10, output: 10),
                project: "small"
            ),
            UsageEvent(
                id: "claude:big", provider: .claude, timestamp: now,
                model: "claude-opus-5",
                tokens: TokenBreakdown(input: 10_000, output: 10_000),
                project: "big"
            )
        ]

        let snapshot = UsageAggregator().snapshot(
            from: RawTelemetry(events: events, limits: [], sourceFiles: [:]),
            now: now
        )

        XCTAssertEqual(snapshot.allTimeProjects.map(\.project), ["big", "small"])
    }
}
