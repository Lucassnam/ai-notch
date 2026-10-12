import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var panelController: NotchPanelController?
    private var customizationPanelController: CustomizationPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        customizationPanelController = CustomizationPanelController(viewModel: viewModel)
        panelController = NotchPanelController(
            viewModel: viewModel,
            onCustomize: { [weak self] in self?.openCustomization() }
        )
        panelController?.show()
        installStatusItem()
        viewModel.start()

        if ProcessInfo.processInfo.environment["AINOTCH_PREVIEW_CUSTOMIZE"] == "1" {
            openCustomization()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "waveform.path.ecg.rectangle",
            accessibilityDescription: "AI Notch"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show AI Notch",
            action: #selector(showNotch),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Customize AI Notch…",
            action: #selector(customizeNotch),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: "Refresh Usage",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit AI Notch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showNotch() {
        viewModel.isExpanded = true
        viewModel.isPinned = true
        panelController?.show()
    }

    @objc private func refreshUsage() {
        Task { await viewModel.refresh() }
    }

    @objc private func customizeNotch() {
        openCustomization()
    }

    private func openCustomization() {
        // The widget editor is a real second window. Return the notch to its
        // everyday compact state so the two surfaces never masquerade as one.
        viewModel.isPinned = false
        viewModel.isExpanded = false
        panelController?.show()
        customizationPanelController?.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
