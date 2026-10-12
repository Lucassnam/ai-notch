import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
///
/// Registration fails when the app runs from a quarantined or transient
/// location — a debug build under `.build/`, or an unmoved download. The error
/// is surfaced rather than swallowed so the toggle cannot claim a state the
/// system did not grant.
enum LoginItem {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// - Returns: nil on success, otherwise a message suitable for display.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard #available(macOS 13.0, *) else {
            return "Requires macOS 13 or later."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            if SMAppService.mainApp.status == .requiresApproval {
                return "Approve AI Notch in System Settings › General › Login Items."
            }
            return "Could not update login item. Move AI Notch to /Applications and try again."
        }
    }
}
