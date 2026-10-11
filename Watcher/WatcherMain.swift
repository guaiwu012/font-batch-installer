import Foundation
import AppKit

@main
struct FontBatchInstallerWatcher {
    static func main() {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.fayzhang.font-batch-installer.main-active"),
            object: nil,
            queue: .main
        ) { _ in
            exit(0)
        }

        let watcher = DownloadWatcher { urls in
            DispatchQueue.main.async {
                let helperBundle = Bundle.main.bundleURL
                let mainApp = helperBundle
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(
                    urls,
                    withApplicationAt: mainApp,
                    configuration: configuration
                ) { _, _ in exit(0) }
            }
        }
        watcher.start()
        _ = observer
        RunLoop.main.run()
    }
}

