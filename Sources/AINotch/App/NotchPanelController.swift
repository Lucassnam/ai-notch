import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPanelController: NSObject {
    private let panel: NotchPanel
    private let viewModel: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []

    /// The chrome straddles the notch, so the panel is as tall as that strip
    /// needs to be plus its fixed rows below.
    private var expandedSize: NSSize {
        NSSize(
            width: NotchMetrics.expandedWidth,
            height: NotchMetrics.expandedHeight(notchHeight: resolvedNotchHeight)
        )
    }

    /// The collapsed panel must be exactly as tall as the notch, otherwise it
    /// hangs below the menu bar. A hardcoded 38pt against a 32pt notch is what
    /// produced the overhang.
    ///
    /// `safeAreaInsets.top` is the notch height on built-in displays and zero
    /// everywhere else, so external monitors fall back to the menu-bar height.
    static func notchHeight(for screen: NSScreen) -> CGFloat {
        if let raw = ProcessInfo.processInfo.environment["AINOTCH_FAKE_NOTCH_HEIGHT"], let v = Double(raw) { return CGFloat(v) }
        let notch = screen.safeAreaInsets.top
        if notch > 0 { return notch }
        let menuBar = screen.frame.height - screen.visibleFrame.height
        return menuBar > 0 ? min(menuBar, NotchMetrics.collapsedFallbackHeight)
                           : NotchMetrics.collapsedFallbackHeight
    }

    /// A notch app belongs on the screen that has a notch. `NSScreen.main`
    /// follows keyboard focus, which can park the panel on an external display
    /// where there is no notch to sit in.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Width of the notch itself, taken from the gap between the two usable
    /// areas of the menu bar. Both are nil on displays without a notch, where
    /// the bar is uninterrupted and nothing needs to route around anything.
    ///
    /// Height alone was never enough: the panel is centred on the screen and so
    /// is the notch, so anything centred in the top strip lands behind it.
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if let raw = ProcessInfo.processInfo.environment["AINOTCH_FAKE_NOTCH_WIDTH"], let v = Double(raw) { return CGFloat(v) }
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }

    private var resolvedNotchHeight: CGFloat {
        targetScreen.map(Self.notchHeight(for:)) ?? NotchMetrics.collapsedFallbackHeight
    }

    private var collapsedSize: NSSize {
        NSSize(
            width: NotchMetrics.collapsedWidth(notchWidth: resolvedNotchWidth),
            height: resolvedNotchHeight
        )
    }

    private var resolvedNotchWidth: CGFloat {
        targetScreen.map(Self.notchWidth(for:)) ?? 0
    }

    /// Offset of the notch's true centre from the screen's centre. The panel is
    /// placed on the screen's midpoint, so this is also the offset from the
    /// panel's midpoint. Zero on displays with no notch, and zero on a notch
    /// that is genuinely centred — but it is measured rather than assumed.
    static func notchCenterOffset(for screen: NSScreen) -> CGFloat {
        if let raw = ProcessInfo.processInfo.environment["AINOTCH_FAKE_NOTCH_OFFSET"],
           let value = Double(raw) {
            return CGFloat(value)
        }
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 0 }
        return (left.maxX + right.minX) / 2 - screen.frame.midX
    }


    /// Pushes the screen's notch geometry to the view model, which is what every
    /// layout measures against. Runs before anything reads a panel size.
    private func applyScreenGeometry() {
        guard let screen = targetScreen else { return }
        viewModel.notchHeight = Self.notchHeight(for: screen)
        viewModel.notchWidth = Self.notchWidth(for: screen)
        viewModel.notchCenterOffset = Self.notchCenterOffset(for: screen)
    }

    init(viewModel: UsageViewModel, onCustomize: @escaping () -> Void) {
        self.viewModel = viewModel
        panel = NotchPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: NotchMetrics.collapsedWidth(notchWidth: 0),
                    height: NotchMetrics.collapsedFallbackHeight
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Boring Notch uses the adjacent status-bar layer. Staying a couple of
        // levels above it lets AI Notch act as a companion overlay when both
        // apps are installed, without using a system-wide screen-saver level.
        panel.level = .statusBar + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        // A capture run opens the panel under whatever the pointer is doing.
        // Two runs came back with a different tab selected and the pin off,
        // because the panel had been clicked while it was being photographed.
        panel.ignoresMouseEvents =
            ProcessInfo.processInfo.environment["AINOTCH_CAPTURE"] == "1"
        let hostingView = NSHostingView(
            rootView: NotchRootView(viewModel: viewModel, onCustomize: onCustomize)
        )
        // The root view deliberately switches between two fixed sizes. Letting
        // NSHostingView publish those intrinsic-size changes back to AppKit while
        // the panel is animating its frame can start a nested constraint pass and
        // crash the app. The panel controller is the single owner of window size.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: collapsedSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.resize(expanded: expanded, animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.resize(expanded: self.viewModel.isExpanded, animated: false)
            }
            .store(in: &cancellables)
    }

    func show() {
        resize(expanded: viewModel.isExpanded, animated: false)
        panel.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["AINOTCH_PRINT_WINDOW_ID"] == "1" {
            FileHandle.standardError.write(Data("WINDOW_ID=\(panel.windowNumber)\n".utf8))
        }
    }

    private func resize(expanded: Bool, animated: Bool) {
        guard let screen = targetScreen else { return }
        // The views size themselves from the view model, so the window and its
        // contents agree on both notch dimensions.
        applyScreenGeometry()
        let size = expanded ? expandedSize : collapsedSize

        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        panel.hasShadow = false
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.36 : 0.44
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22,
                    0.76,
                    0.24,
                    1
                )
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
