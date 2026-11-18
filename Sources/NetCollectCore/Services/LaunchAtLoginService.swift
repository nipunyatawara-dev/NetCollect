import ServiceManagement

@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled && service.status != .enabled {
            try service.register()
        } else if !enabled && (service.status == .enabled || service.status == .requiresApproval) {
            try service.unregister()
        }
    }
}
