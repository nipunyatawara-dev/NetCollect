import Foundation
import ServiceManagement

/// Handles macOS Launch at Login configuration.
public final class LaunchAtLoginService: @unchecked Sendable {
    public static let shared = LaunchAtLoginService()

    private init() {}

    public var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                    }
                } catch {
                    print("Failed to update LaunchAtLogin: \(error)")
                }
            }
        }
    }
}
