import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    static let helperIdentifier = "com.fayzhang.font-batch-installer.watcher"

    @Published private(set) var isEnabled = false
    @Published var alertMessage: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.loginItem(identifier: Self.helperIdentifier)
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
            if service.status == .requiresApproval {
                alertMessage = "请在“系统设置 → 通用 → 登录项”中允许“字装一下监控器”。"
            }
        } catch {
            refresh()
            alertMessage = error.localizedDescription
        }
    }

    func refresh() {
        let status = SMAppService.loginItem(identifier: Self.helperIdentifier).status
        isEnabled = status == .enabled || status == .requiresApproval
    }
}

