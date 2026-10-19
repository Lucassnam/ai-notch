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

    /// Axis labels live in a fixed 44pt slot. Every compact
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

    // MARK: - Square values

    /// The square beside the notch is notch-height wide: about four glyphs
    /// at 13pt. Under $1,000 spend fits four; the dollar sign makes a scaled
    /// figure (`$1.2K`) five, which the slot's scale factor absorbs.
    func testSquareValuesStayWithinFourGlyphs() {
        for sample: Double in [0, 0.6, 4.24, 9.96, 24.62, 99.6, 132.87, 999.4] {
            XCTAssertLessThanOrEqual(AIFormat.squareCurrency(sample).count, 4, "\(sample)")
        }
        for sample: Double in [0.004, 999.6, 10_400, 999_499, 2_500_000] {
            XCTAssertLessThanOrEqual(AIFormat.squareCurrency(sample).count, 5, "\(sample)")
        }
        let tokens: [Int64] = [0, 999, 1_000, 9_960, 850_000, 999_499, 21_800_000,
                               147_800_000, 999_600_000, 3_100_000_000]
        for sample in tokens {
            XCTAssertLessThanOrEqual(AIFormat.squareTokens(sample).count, 4, "\(sample)")
        }
    }

    func testSquareCurrencyKeepsTwoSignificantFigures() {
        XCTAssertEqual(AIFormat.squareCurrency(0), "$0")
        XCTAssertEqual(AIFormat.squareCurrency(0.004), "<$0.1")
        XCTAssertEqual(AIFormat.squareCurrency(4.24), "$4.2")
        XCTAssertEqual(AIFormat.squareCurrency(9.96), "$10")
        XCTAssertEqual(AIFormat.squareCurrency(24.62), "$25")
        XCTAssertEqual(AIFormat.squareCurrency(132.87), "$133")
        XCTAssertEqual(AIFormat.squareCurrency(999.6), "$1.0K")
        XCTAssertEqual(AIFormat.squareCurrency(1_172.76), "$1.2K")
        XCTAssertEqual(AIFormat.squareCurrency(12_345), "$12K")
    }

    func testSquareTokensRoundOnTheRoundedValue() {
        XCTAssertEqual(AIFormat.squareTokens(999), "999")
        XCTAssertEqual(AIFormat.squareTokens(9_960), "10K")
        XCTAssertEqual(AIFormat.squareTokens(21_800_000), "22M")
        XCTAssertEqual(AIFormat.squareTokens(1_234_000_000), "1.2B")
        XCTAssertEqual(AIFormat.squareTokens(999_600), "1.0M")
    }
}
