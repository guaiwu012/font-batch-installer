import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FontOpenRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let automaticallyDetected: Bool
}

@MainActor
final class FontRequestCenter: ObservableObject {
    static let shared = FontRequestCenter()
    @Published var request: FontOpenRequest?

    func submit(urls: [URL], automaticallyDetected: Bool) {
        guard !urls.isEmpty else { return }
        request = FontOpenRequest(urls: urls, automaticallyDetected: automaticallyDetected)
    }
}

extension Notification.Name {
    static let chooseFontFiles = Notification.Name("chooseFontFiles")
    static let chooseFontFolder = Notification.Name("chooseFontFolder")
    static let downloadWatchPreferenceChanged = Notification.Name("downloadWatchPreferenceChanged")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var downloadWatcher: DownloadWatcher?
    private var statusItem: NSStatusItem?
    private var monitorMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["monitorDownloads": true])
        setupStatusItem()
        applyDownloadWatchPreference()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadWatchPreferenceDidChange),
            name: .downloadWatchPreferenceChanged,
            object: nil
        )
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.fayzhang.font-batch-installer.main-active"),
            object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindow()
        FontRequestCenter.shared.submit(urls: urls, automaticallyDetected: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        downloadWatcher?.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "字装一下")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开字装一下", action: #selector(openFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let monitorItem = NSMenuItem(title: "监控“下载”文件夹", action: #selector(toggleDownloadMonitoring), keyEquivalent: "")
        monitorItem.target = self
        menu.addItem(monitorItem)
        monitorMenuItem = monitorItem

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出字装一下", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        updateMonitorMenuState()
    }

    @objc private func openFromMenu() {
        showMainWindow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func toggleDownloadMonitoring() {
        let enabled = !UserDefaults.standard.bool(forKey: "monitorDownloads")
        UserDefaults.standard.set(enabled, forKey: "monitorDownloads")
        applyDownloadWatchPreference()
    }

    @objc private func downloadWatchPreferenceDidChange() {
        applyDownloadWatchPreference()
    }

    private func applyDownloadWatchPreference() {
        let enabled = UserDefaults.standard.bool(forKey: "monitorDownloads")
        if enabled {
            if downloadWatcher == nil {
                let watcher = DownloadWatcher { urls in
                    DispatchQueue.main.async {
                        self.showMainWindow()
                        FontRequestCenter.shared.submit(urls: urls, automaticallyDetected: true)
                    }
                }
                downloadWatcher = watcher
                watcher.start()
            }
        } else {
            downloadWatcher?.stop()
            downloadWatcher = nil
        }
        updateMonitorMenuState()
    }

    private func updateMonitorMenuState() {
        monitorMenuItem?.state = UserDefaults.standard.bool(forKey: "monitorDownloads") ? .on : .off
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct FontBatchInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("字装一下", id: "main") {
            ContentView()
                .frame(minWidth: 700, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("字体") {
                Button("选择字体或 ZIP…") {
                    NotificationCenter.default.post(name: .chooseFontFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("选择文件夹…") {
                    NotificationCenter.default.post(name: .chooseFontFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

