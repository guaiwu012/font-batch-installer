import Foundation
import CoreText

struct FontInstallItem: Identifiable {
    enum Status {
        case installed
        case skipped
        case failed
    }

    let id = UUID()
    let filename: String
    let status: Status
    let detail: String
}

struct FontInstallSummary {
    let discoveredCount: Int
    let items: [FontInstallItem]

    var installedCount: Int { items.filter { $0.status == .installed }.count }
    var skippedCount: Int { items.filter { $0.status == .skipped }.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
}

final class FontInstaller {
    static let supportedExtensions = FontFileSupport.fontExtensions

    private let fileManager: FileManager
    private let destinationOverride: URL?
    private let backupOverride: URL?

    init(
        fileManager: FileManager = .default,
        destinationOverride: URL? = nil,
        backupOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.destinationOverride = destinationOverride
        self.backupOverride = backupOverride
    }

    func discoverFonts(in inputURLs: [URL]) -> [URL] {
        var discovered: [URL] = []
        var seenPaths = Set<String>()

        for inputURL in inputURLs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey]
                guard let enumerator = fileManager.enumerator(
                    at: inputURL,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let candidate as URL in enumerator {
                    let values = try? candidate.resourceValues(forKeys: Set(keys))
                    guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
                    guard isSupportedFont(candidate) else { continue }
                    if seenPaths.insert(candidate.standardizedFileURL.path).inserted {
                        discovered.append(candidate)
                    }
                }
            } else if isSupportedFont(inputURL) {
                if seenPaths.insert(inputURL.standardizedFileURL.path).inserted {
                    discovered.append(inputURL)
                }
            }
        }

        return discovered.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    func install(from inputURLs: [URL]) -> FontInstallSummary {
        let fontURLs = discoverFonts(in: inputURLs)
        guard !fontURLs.isEmpty else {
            return FontInstallSummary(discoveredCount: 0, items: [])
        }

        do {
            let destination = try fontsDirectory()
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

            var items: [FontInstallItem] = []
            for sourceURL in fontURLs {
                items.append(installOne(sourceURL, into: destination))
            }
            return FontInstallSummary(discoveredCount: fontURLs.count, items: items)
        } catch {
            let item = FontInstallItem(
                filename: "字体目录",
                status: .failed,
                detail: readableError(error)
            )
            return FontInstallSummary(discoveredCount: fontURLs.count, items: [item])
        }
    }

    private func installOne(_ sourceURL: URL, into destinationDirectory: URL) -> FontInstallItem {
        let filename = sourceURL.lastPathComponent

        guard isValidFont(sourceURL) else {
            return FontInstallItem(filename: filename, status: .failed, detail: "文件不是可识别的 macOS 字体")
        }

        do {
            let destinationURL = try resolvedDestination(for: sourceURL, in: destinationDirectory)
            if fileManager.fileExists(atPath: destinationURL.path) {
                if try filesAreIdentical(sourceURL, destinationURL) {
                    return FontInstallItem(filename: filename, status: .skipped, detail: "已安装相同版本")
                }
                try backupExistingFont(at: destinationURL)
                try fileManager.removeItem(at: destinationURL)
            }

            let stagingURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString)-\(filename)")
            defer { try? fileManager.removeItem(at: stagingURL) }
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try fileManager.moveItem(at: stagingURL, to: destinationURL)

            return FontInstallItem(filename: filename, status: .installed, detail: "已安装到当前用户")
        } catch {
            return FontInstallItem(filename: filename, status: .failed, detail: readableError(error))
        }
    }

    private func resolvedDestination(for sourceURL: URL, in directory: URL) throws -> URL {
        let primary = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        guard fileManager.fileExists(atPath: primary.path) else { return primary }
        if try filesAreIdentical(sourceURL, primary) { return primary }

        let sourceNames = fontIdentityNames(sourceURL)
        let installedNames = fontIdentityNames(primary)
        if !sourceNames.isEmpty, sourceNames == installedNames {
            return primary
        }

        let fileExtension = sourceURL.pathExtension
        let originalBase = sourceURL.deletingPathExtension().lastPathComponent
        let identity = safeFilenameComponent(sourceNames.sorted().first ?? "font")
        let base = "\(originalBase)-\(identity)"

        for sequence in 1...999 {
            let suffix = sequence == 1 ? "" : "-\(sequence)"
            let candidateName = fileExtension.isEmpty
                ? "\(base)\(suffix)"
                : "\(base)\(suffix).\(fileExtension)"
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            if try filesAreIdentical(sourceURL, candidate) { return candidate }
        }

        throw InstallerError.tooManyNameCollisions(sourceURL.lastPathComponent)
    }

    private func fontsDirectory() throws -> URL {
        if let destinationOverride { return destinationOverride }
        guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw InstallerError.userLibraryUnavailable
        }
        return library.appendingPathComponent("Fonts", isDirectory: true)
    }

    private func backupExistingFont(at url: URL) throws {
        let backupRoot: URL
        if let backupOverride {
            backupRoot = backupOverride
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw InstallerError.userLibraryUnavailable
            }
            backupRoot = applicationSupport
                .appendingPathComponent("字装一下", isDirectory: true)
                .appendingPathComponent("字体备份", isDirectory: true)
        }

        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: Date())
        let token = UUID().uuidString.prefix(8)
        let backupURL = backupRoot.appendingPathComponent("\(timestamp)-\(token)-\(url.lastPathComponent)")
        try fileManager.copyItem(at: url, to: backupURL)
    }

    private func isSupportedFont(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isValidFont(_ url: URL) -> Bool {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return false
        }
        return !descriptors.isEmpty
    }

    private func fontIdentityNames(_ url: URL) -> Set<String> {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        return Set(descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
        })
    }

    private func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String((cleaned.isEmpty ? "font" : cleaned).prefix(64))
    }

    private func filesAreIdentical(_ first: URL, _ second: URL) throws -> Bool {
        let firstValues = try first.resourceValues(forKeys: [.fileSizeKey])
        let secondValues = try second.resourceValues(forKeys: [.fileSizeKey])
        guard firstValues.fileSize == secondValues.fileSize else { return false }
        return try Data(contentsOf: first, options: .mappedIfSafe) == Data(contentsOf: second, options: .mappedIfSafe)
    }

    private func readableError(_ error: Error) -> String {
        let nsError = error as NSError
        if !nsError.localizedFailureReason.map({ $0.isEmpty }).nilOrTrue {
            return nsError.localizedFailureReason ?? nsError.localizedDescription
        }
        return nsError.localizedDescription
    }
}

private enum InstallerError: LocalizedError {
    case userLibraryUnavailable
    case tooManyNameCollisions(String)

    var errorDescription: String? {
        switch self {
        case .userLibraryUnavailable:
            return "无法访问当前用户的字体目录"
        case .tooManyNameCollisions(let filename):
            return "无法为 \(filename) 生成不重复的文件名"
        }
    }
}

private extension Optional where Wrapped == Bool {
    var nilOrTrue: Bool { self ?? true }
}

