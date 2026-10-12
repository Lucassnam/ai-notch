import XCTest
@testable import AINotch

final class FormattersTests: XCTestCase {
    /// The previous implementation replaced every hyphen with a space, so the
    /// version separator and the word separator became indistinguishable.
    func testVersionSegmentsRejoinWithADot() {
        XCTAssertEqual(AIFormat.modelName("claude-opus-4-8"), "Opus 4.8")
    }

    func testTrailingReleaseDatestampIsDropped() {
        XCTAssertEqual(AIFormat.modelName("claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testSingleVersionSegmentIsPreserved() {
        XCTAssertEqual(AIFormat.modelName("claude-opus-5"), "Opus 5")
        XCTAssertEqual(AIFormat.modelName("claude-sonnet-5"), "Sonnet 5")
    }

    func testNamedSuffixesSurvive() {
        XCTAssertEqual(AIFormat.modelName("gpt-5.6-sol"), "GPT 5.6 Sol")
        XCTAssertEqual(AIFormat.modelName("gpt-5.5"), "GPT 5.5")
    }

    func testBareAliasIsCapitalised() {
        XCTAssertEqual(AIFormat.modelName("opus"), "Opus")
    }

    // MARK: - Compact currency

    /// The two values beside the notch live in a fixed 44pt slot. Every compact
    /// result must stay within six characters so the text never has to shrink
    /// below the 11pt floor the type scale sets.
    func testCompactCurrencyNeverExceedsSixCharacters() {
        let samples: [Double] = [0, 0.004, 0.99, 9.99, 74.87, 99.99, 100, 181.04,
                                 999.99, 1_000, 1_234.56, 9_999, 12_345.6, 99_999,
                                 999_499, 999_999, 1_234_567, 99_000_000]
        for sample in samples {
            let formatted = AIFormat.currency(sample, compact: true)
            XCTAssertLessThanOrEqual(
                formatted.count, 6,
                "\(sample) formatted as \(formatted)"
            )
        }
    }

    func testCompactCurrencyDropsCentsOnlyFromOneHundred() {
        XCTAssertEqual(AIFormat.currency(74.87, compact: true), "$74.87")
        XCTAssertEqual(AIFormat.currency(99.99, compact: true), "$99.99")
        XCTAssertEqual(AIFormat.currency(181.04, compact: true), "$181")
        XCTAssertEqual(AIFormat.currency(999.49, compact: true), "$999")
        XCTAssertEqual(AIFormat.currency(1_234.56, compact: true), "$1.2K")
        XCTAssertEqual(AIFormat.currency(12_345.6, compact: true), "$12K")
        XCTAssertEqual(AIFormat.currency(99_999, compact: true), "$100K")
        XCTAssertEqual(AIFormat.currency(1_234_567, compact: true), "$1.2M")
    }

    /// The full form is what the widget cards and pages show, and it must keep
    /// its cents at every magnitude.
    func testFullCurrencyKeepsCentsAtEveryMagnitude() {
        XCTAssertEqual(AIFormat.currency(74.87), "$74.87")
        XCTAssertEqual(AIFormat.currency(181.04), "$181.04")
        XCTAssertEqual(AIFormat.currency(1_234.56), "$1,234.56")
        XCTAssertEqual(AIFormat.currency(999.99), "$999.99")
        XCTAssertEqual(AIFormat.currency(1_234_567.8), "$1,234,567.80")
        XCTAssertEqual(AIFormat.currency(0.004), "<$0.01")
        XCTAssertEqual(AIFormat.currency(0), "$0.00")
    }
}
