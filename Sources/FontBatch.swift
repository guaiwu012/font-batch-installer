import Foundation
import CoreText

struct FontCandidate: Identifiable, Hashable {
    let id: String
    let url: URL
    let familyName: String
    let styleNames: [String]
    let isCollection: Bool
    let isRegularWeight: Bool

    var filename: String { url.lastPathComponent }
    var styleSummary: String {
        styleNames.isEmpty ? "默认字重" : styleNames.joined(separator: "、")
    }
}

struct PreparedFontBatch {
    let candidates: [FontCandidate]
    let temporaryDirectories: [URL]
    let sourceNames: [String]
    let errors: [String]
}

final class FontBatchPreparer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepare(urls: [URL]) -> PreparedFontBatch {
        var sourceNames: [String] = []
        var temporaryDirectories: [URL] = []
        var errors: [String] = []
        var fontURLs: [URL] = []
        var seen = Set<String>()

        for input in urls {
            sourceNames.append(input.lastPathComponent)
            let inputs = discoverInputs(at: input)
            for candidate in inputs {
                if FontFileSupport.isFont(candidate) {
                    appendUnique(candidate, to: &fontURLs, seen: &seen)
                } else if FontFileSupport.isArchive(candidate) {
                    do {
                        let extractionDirectory = fileManager.temporaryDirectory
                            .appendingPathComponent("ZiZhuangYiXia", isDirectory: true)
                            .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        try FontArchiveUtility.extract(candidate, to: extractionDirectory)
                        temporaryDirectories.append(extractionDirectory)
                        for extractedFont in FontInstaller(fileManager: fileManager).discoverFonts(in: [extractionDirectory]) {
                            appendUnique(extractedFont, to: &fontURLs, seen: &seen)
                        }
                    } catch {
                        errors.append("\(candidate.lastPathComponent)：\(error.localizedDescription)")
                    }
                }
            }
        }

        let candidates = fontURLs.compactMap(makeCandidate).sorted {
            if $0.familyName != $1.familyName {
                return $0.familyName.localizedStandardCompare($1.familyName) == .orderedAscending
            }
            return $0.styleSummary.localizedStandardCompare($1.styleSummary) == .orderedAscending
        }

        return PreparedFontBatch(
            candidates: candidates,
            temporaryDirectories: temporaryDirectories,
            sourceNames: Array(Set(sourceNames)).sorted(),
            errors: errors
        )
    }

    private func discoverInputs(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            return FontFileSupport.isFont(url) || FontFileSupport.isArchive(url) ? [url] : []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            if FontFileSupport.isFont(item) || FontFileSupport.isArchive(item) {
                results.append(item)
            }
        }
        return results
    }

    private func appendUnique(_ url: URL, to urls: inout [URL], seen: inout Set<String>) {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard seen.insert(path).inserted else { return }
        urls.append(url)
    }

    private func makeCandidate(_ url: URL) -> FontCandidate? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              !descriptors.isEmpty else { return nil }

        let families = Set(descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
        })
        let styles = Set(descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontStyleNameAttribute) as? String
        }).filter { !$0.isEmpty }
        let displayName = descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontDisplayNameAttribute) as? String
        }.first
        let family = families.sorted().first ?? displayName ?? url.deletingPathExtension().lastPathComponent
        let styleNames = styles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let searchableStyles = styleNames.joined(separator: " ").lowercased()
        let regularTerms = ["regular", "normal", "roman", "book", "常规", "正常", "标准"]

        return FontCandidate(
            id: url.standardizedFileURL.path,
            url: url,
            familyName: family,
            styleNames: styleNames,
            isCollection: ["ttc", "otc"].contains(url.pathExtension.lowercased()) || descriptors.count > 1,
            isRegularWeight: styleNames.isEmpty || regularTerms.contains { searchableStyles.contains($0) }
        )
    }
}

