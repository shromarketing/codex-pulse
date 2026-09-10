import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginService {
    static func apply(enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}
