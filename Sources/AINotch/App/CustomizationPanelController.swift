import AppKit
import SwiftUI

/// Owns the independent widget editor. Keeping this separate from the notch
/// panel means editing never changes the notch's geometry or interaction mode.
@MainActor
final class CustomizationPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let viewModel: UsageViewModel

    private static let windowSize = NSSize(width: 520, height: 680)

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.title = "Customize AI Notch"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Hiding only minimise left a gap between the red and green buttons.
        // The window cannot usefully zoom either, so close stands alone.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentMinSize = Self.windowSize

        let hostingView = NSHostingView(
            rootView: CustomizationWindowView(
                viewModel: viewModel,
                onDone: { [weak self] in self?.panel.close() }
            )
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.windowSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    func show() {
        positionBelowNotch()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["AINOTCH_PRINT_WINDOW_ID"] == "1" {
            FileHandle.standardError.write(
                Data("CUSTOMIZATION_WINDOW_ID=\(panel.windowNumber)\n".utf8)
            )
        }
    }

    private func positionBelowNotch() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main
                ?? NSScreen.screens.first else { return }

        let notchHeight = NotchPanelController.notchHeight(for: screen)
        let top = screen.frame.maxY - notchHeight - 16
        panel.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: top - panel.frame.height
            )
        )
    }
}
