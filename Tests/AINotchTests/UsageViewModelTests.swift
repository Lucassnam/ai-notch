import Foundation
import XCTest
@testable import AINotch

@MainActor
final class UsageViewModelTests: XCTestCase {
    func testTranslucencyPreferencePersistsAcrossViewModels() {
        let suiteName = "AINotchTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let first = UsageViewModel(preferences: preferences)
        XCTAssertFalse(first.isTranslucent)
        first.toggleTranslucency()
        XCTAssertTrue(first.isTranslucent)

        let restored = UsageViewModel(preferences: preferences)
        XCTAssertTrue(restored.isTranslucent)
        restored.toggleTranslucency()

        let blackAgain = UsageViewModel(preferences: preferences)
        XCTAssertFalse(blackAgain.isTranslucent)
    }

    func testWidgetPreferencesPersistAcrossViewModels() {
        let suiteName = "AINotchTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let first = UsageViewModel(preferences: preferences)
        first.toggleWidget(.fiveHourSpend)
        first.moveWidget(.codexLimit, offset: -1)
        first.leadingCompactWidget = .monthSpend
        first.trailingCompactWidget = nil

        let restored = UsageViewModel(preferences: preferences)
        XCTAssertFalse(restored.visibleWidgets.contains(.fiveHourSpend))
        XCTAssertEqual(restored.widgetOrder, first.widgetOrder)
        XCTAssertEqual(restored.leadingCompactWidget, .monthSpend)
        XCTAssertNil(restored.trailingCompactWidget)
    }

    func testResetRestoresMinimalDefaultLayout() {
        let suiteName = "AINotchTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let viewModel = UsageViewModel(preferences: preferences)
        MetricWidget.allCases.forEach { widget in
            if viewModel.visibleWidgets.contains(widget) {
                viewModel.toggleWidget(widget)
            }
        }
        viewModel.leadingCompactWidget = nil
        viewModel.trailingCompactWidget = .monthSpend

        viewModel.resetWidgetPreferences()

        XCTAssertEqual(
            viewModel.visibleWidgets,
            [.todaySpend, .fiveHourSpend, .fiveHourTokens, .codexLimit]
        )
        XCTAssertEqual(viewModel.widgetOrder, MetricWidget.allCases)
        XCTAssertEqual(viewModel.leadingCompactWidget, .todaySpend)
        XCTAssertEqual(viewModel.trailingCompactWidget, .fiveHourTokens)
    }

}
