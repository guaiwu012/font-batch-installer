import Foundation
import Darwin

final class DownloadWatcher {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.fayzhang.font-batch-installer.download-watcher", qos: .utility)
    private let handler: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var seenPaths = Set<String>()
    private var pendingScan: DispatchWorkItem?

    init(directory: URL? = nil, handler: @escaping ([URL]) -> Void) {
        self.directory = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        self.handler = handler
    }

    func start() {
        guard source == nil else { return }
        primeExistingFiles()
        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .extend, .attrib],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in self?.scheduleScan() }
        newSource.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source = newSource
        newSource.resume()
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
    }

    private func primeExistingFiles() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        seenPaths = Set(urls.map { $0.standardizedFileURL.path })
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanForNewFontPackages() }
        pendingScan = work
        queue.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func scanForNewFontPackages() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var detected: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            guard FontFileSupport.isFont(url) || FontFileSupport.isArchive(url) else {
                seenPaths.insert(path)
                continue
            }

            if FontFileSupport.isFont(url) {
                seenPaths.insert(path)
                detected.append(url)
                continue
            }

            do {
                let containsFonts = try FontArchiveUtility.containsSupportedFonts(url)
                seenPaths.insert(path)
                if containsFonts { detected.append(url) }
            } catch {
                // The browser may still be writing the archive. Leave it unseen so the next event retries it.
            }
        }

        if !detected.isEmpty { handler(detected) }
    }
}

