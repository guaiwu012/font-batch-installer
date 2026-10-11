import Foundation

enum FontFileSupport {
    static let fontExtensions = Set(["otf", "ttf", "ttc", "otc", "dfont"])
    static let archiveExtensions = Set(["zip"])

    static func isFont(_ url: URL) -> Bool {
        fontExtensions.contains(url.pathExtension.lowercased())
    }

    static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }
}

enum FontArchiveUtility {
    static func containsSupportedFonts(_ archiveURL: URL) throws -> Bool {
        let fileManager = FileManager.default
        let inspectionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ZiZhuangYiXiaInspection", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: inspectionDirectory) }
        try extract(archiveURL, to: inspectionDirectory)

        guard let enumerator = fileManager.enumerator(
            at: inspectionDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }

        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            if FontFileSupport.isFont(item) { return true }
        }
        return false
    }

    static func extract(_ archiveURL: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.extractionFailed(message?.isEmpty == false ? message! : "无法解压这个 ZIP")
        }

        let rootPath = destination.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if let extractedItems = fileManager.enumerator(
            at: destination,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let item as URL in extractedItems {
                let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { continue }
                let resolved = item.standardizedFileURL.resolvingSymlinksInPath().path
                guard resolved == destination.path || resolved.hasPrefix(rootPath) else {
                    throw ArchiveError.unsafePath
                }
            }
        }
    }
}

enum ArchiveError: LocalizedError {
    case emptyArchive
    case unsafePath
    case unreadableArchive(String)
    case extractionFailed(String)
    case invalidFilenameEncoding

    var errorDescription: String? {
        switch self {
        case .emptyArchive: return "ZIP 文件是空的"
        case .unsafePath: return "ZIP 内含不安全的文件路径，已停止解压"
        case .unreadableArchive(let message): return message
        case .extractionFailed(let message): return message
        case .invalidFilenameEncoding: return "ZIP 内的文件名编码无法识别"
        }
    }
}

