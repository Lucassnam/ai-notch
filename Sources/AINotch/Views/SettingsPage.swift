import AppKit
import SwiftUI

struct SettingsPage: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                sourceCard(.claude, path: "~/.claude/projects")
                sourceCard(.codex, path: "~/.codex/sessions")
            }

            VStack(alignment: .leading, spacing: 7) {
                toggleRow(
                    title: "Launch at login",
                    detail: viewModel.loginItemMessage ?? "Start AI Notch when you log in",
                    isOn: viewModel.launchesAtLogin,
                    isWarning: viewModel.loginItemMessage != nil
                ) {
                    viewModel.toggleLaunchAtLogin()
                }

                Divider().overlay(NotchDesign.divider)

                toggleRow(
                    title: "Translucent panel",
                    detail: "Frost the background instead of solid black",
                    isOn: viewModel.isTranslucent,
                    isWarning: false
                ) {
                    viewModel.toggleTranslucency()
                }
            }
            .cardSurface(padding: 11)

            // Side by side so Quit stays on screen. Stacked, this page needed
            // ~395pt against 308pt available and pushed the button off the
            // bottom edge.
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchDesign.secondary)
                        Text("Private by design")
                            .font(NotchType.title)
                    }
                    Text("Only timestamps, model names, token counts, and rate-limit records are read — never prompts or responses. Dollar figures estimate API list prices and can differ from a subscription bill.")
                        .font(NotchType.label)
                        .foregroundStyle(NotchDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(viewModel.snapshot.eventCount.formatted()) usage records stored locally")
                        .font(NotchType.label)
                        .foregroundStyle(NotchDesign.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: 11)

                Button { viewModel.quit() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Quit")
                            .font(NotchType.body)
                    }
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 92)
                    .frame(maxHeight: .infinity)
                    .cardSurface(padding: 11)
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NotchMetrics.horizontalPadding)
        .padding(.bottom, 14)
    }

    private func toggleRow(
        title: String,
        detail: String,
        isOn: Bool,
        isWarning: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(NotchType.body)
                    Text(detail)
                        .font(NotchType.label)
                        .foregroundStyle(isWarning ? Color.orange.opacity(0.9) : NotchDesign.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Switch(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceCard(_ provider: ProviderID, path: String) -> some View {
        let summary = viewModel.snapshot.providers.first { $0.provider == provider }
        let fileCount = summary?.sourceFileCount ?? 0
        return Button {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(provider.tint)
                    Text(provider.displayName)
                        .font(NotchType.title)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(fileCount > 0 ? Color.green : NotchDesign.tertiary)
                        .frame(width: 6, height: 6)
                }
                Text("\(fileCount) local files")
                    .font(NotchType.value)
                    .monospacedDigit()
                Text(path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchDesign.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 11)
        }
        .buttonStyle(.plain)
        .help("Reveal \(path) in Finder")
    }
}

/// A small switch. AppKit's own `Toggle` renders at a fixed system size that
/// overwhelms a panel this short.
private struct Switch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.green.opacity(0.85) : Color.white.opacity(0.16))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.16), value: isOn)
    }
}
