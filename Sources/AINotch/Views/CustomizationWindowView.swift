import SwiftUI

private enum CustomizerLayout {
    static let outer: CGFloat = MacSpacing.window
    static let sectionGap: CGFloat = 28
    static let rowHeight: CGFloat = 40
    /// Group-box contents sat on the box edge while their headers were inset.
    static let groupInset: CGFloat = MacSpacing.related
}

/// A native macOS secondary window. System group boxes, pop-up buttons,
/// checkboxes, switches, and push buttons provide the platform's own spacing,
/// focus, keyboard, and accessibility behavior.
struct CustomizationWindowView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpacing.section) {
            Text("Customize AI Notch")
                .font(.system(size: 22, weight: .semibold))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: CustomizerLayout.sectionGap) {
                    compactSection
                    widgetSection
                    appSection
                }
                .padding(.vertical, MacSpacing.compact)
            }

            Divider()

            HStack(spacing: MacSpacing.control) {
                Button("Reset Layout") { viewModel.resetWidgetPreferences() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(CustomizerLayout.outer)
        .frame(minWidth: 520, minHeight: 680, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var compactSection: some View {
        GroupBox {
            HStack(alignment: .top, spacing: MacSpacing.item) {
                WidgetPicker(title: "Left side", selection: $viewModel.leadingCompactWidget)
                WidgetPicker(title: "Right side", selection: $viewModel.trailingCompactWidget)
            }
            .padding(.top, MacSpacing.related)
            .padding(.horizontal, CustomizerLayout.groupInset)
        } label: {
            Text("Compact notch")
                .font(.headline)
        }
    }

    private var widgetSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.widgetOrder.enumerated()), id: \.element.id) { index, widget in
                    if index > 0 {
                        Divider()
                    }
                    WidgetPreferenceRow(
                        widget: widget,
                        isVisible: viewModel.visibleWidgets.contains(widget),
                        canMoveUp: index > 0,
                        canMoveDown: index < viewModel.widgetOrder.count - 1,
                        viewModel: viewModel
                    )
                }
            }
            .padding(.top, MacSpacing.related)
            .padding(.horizontal, CustomizerLayout.groupInset)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Pop-out widgets")
                    .font(.headline)
                Spacer()
                Text("Show and reorder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                NativePreferenceToggle(
                    title: "Translucent background",
                    isOn: viewModel.isTranslucent,
                    action: viewModel.toggleTranslucency
                )
                Divider()
                NativePreferenceToggle(
                    title: "Launch at login",
                    isOn: viewModel.launchesAtLogin,
                    action: viewModel.toggleLaunchAtLogin
                )
                Divider()
                HStack {
                    Text("Quit AI Notch")
                        .font(.body)
                    Spacer()
                    Button("Quit", role: .destructive, action: viewModel.quit)
                        .buttonStyle(.bordered)
                }
                .frame(minHeight: CustomizerLayout.rowHeight)
            }
            .padding(.top, MacSpacing.related)
            .padding(.horizontal, CustomizerLayout.groupInset)
        } label: {
            Text("App")
                .font(.headline)
        }
    }
}

private struct WidgetPicker: View {
    let title: String
    @Binding var selection: MetricWidget?

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpacing.related) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                Text("Nothing").tag(MetricWidget?.none)
                ForEach(MetricWidget.allCases) { widget in
                    Text(widget.title).tag(MetricWidget?.some(widget))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetPreferenceRow: View {
    let widget: MetricWidget
    let isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: MacSpacing.control) {
            Toggle(
                isOn: Binding(
                    get: { isVisible },
                    set: { desired in
                        if desired != isVisible { viewModel.toggleWidget(widget) }
                    }
                )
            ) {
                Text(widget.title)
                    .font(.body)
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: MacSpacing.control)

            HStack(spacing: MacSpacing.compact) {
                moveButton(symbol: "chevron.up", label: "Move up", enabled: canMoveUp, offset: -1)
                moveButton(symbol: "chevron.down", label: "Move down", enabled: canMoveDown, offset: 1)
            }
        }
        .frame(minHeight: CustomizerLayout.rowHeight)
        .contentShape(Rectangle())
    }

    private func moveButton(
        symbol: String,
        label: String,
        enabled: Bool,
        offset: Int
    ) -> some View {
        Button { viewModel.moveWidget(widget, offset: offset) } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NativePreferenceToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { desired in
                    if desired != isOn { action() }
                }
            )
        ) {
            Text(title)
                .font(.body)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .frame(minHeight: CustomizerLayout.rowHeight)
    }
}
