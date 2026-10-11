import Foundation

@main
struct FontInstallerTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FontInstallerTests-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }

        let input = root.appendingPathComponent("input")
        let nested = input.appendingPathComponent("nested")
        let destination = root.appendingPathComponent("fonts")
        let backup = root.appendingPathComponent("backups")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)

        let validFont = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
        guard manager.fileExists(atPath: validFont.path) else {
            throw TestFailure("系统测试字体不存在")
        }

        let first = input.appendingPathComponent("Helvetica.ttc")
        let second = nested.appendingPathComponent("Second.ttf")
        let ignored = input.appendingPathComponent("notes.txt")
        try manager.copyItem(at: validFont, to: first)
        try manager.copyItem(at: validFont, to: second)
        try Data("not a font".utf8).write(to: ignored)

        let installer = FontInstaller(
            fileManager: manager,
            destinationOverride: destination,
            backupOverride: backup
        )

        let discovered = installer.discoverFonts(in: [input, first])
        try expect(discovered.count == 2, "递归发现或去重失败")

        let firstRun = installer.install(from: [input])
        try expect(firstRun.installedCount == 2, "首次安装数量不正确")
        try expect(firstRun.failedCount == 0, "首次安装不应失败")

        let secondRun = installer.install(from: [input])
        try expect(secondRun.skippedCount == 2, "相同字体应被跳过")

        let invalidFont = nested.appendingPathComponent("Broken.otf")
        try Data("broken".utf8).write(to: invalidFont)
        let invalidRun = installer.install(from: [invalidFont])
        try expect(invalidRun.failedCount == 1, "损坏字体应报告失败")

        let collisionInputA = root.appendingPathComponent("collision-a")
        let collisionInputB = root.appendingPathComponent("collision-b")
        let collisionDestination = root.appendingPathComponent("collision-fonts")
        try manager.createDirectory(at: collisionInputA, withIntermediateDirectories: true)
        try manager.createDirectory(at: collisionInputB, withIntermediateDirectories: true)

        let alternateFont = URL(fileURLWithPath: "/System/Library/Fonts/Menlo.ttc")
        try expect(manager.fileExists(atPath: alternateFont.path), "备用系统测试字体不存在")
        try manager.copyItem(at: validFont, to: collisionInputA.appendingPathComponent("Regular.ttc"))
        try manager.copyItem(at: alternateFont, to: collisionInputB.appendingPathComponent("Regular.ttc"))

        let collisionInstaller = FontInstaller(
            fileManager: manager,
            destinationOverride: collisionDestination,
            backupOverride: backup
        )
        let collisionRun = collisionInstaller.install(from: [collisionInputA, collisionInputB])
        try expect(collisionRun.installedCount == 2, "同名但不同的字体应全部安装")
        let installedFiles = try manager.contentsOfDirectory(at: collisionDestination, includingPropertiesForKeys: nil)
        try expect(installedFiles.count == 2, "同名字体不应互相覆盖")

        let zipSource = root.appendingPathComponent("中文字体包")
        let zipFont = zipSource.appendingPathComponent("常规字体.ttc")
        let zipURL = root.appendingPathComponent("精选字体包.zip")
        try manager.createDirectory(at: zipSource, withIntermediateDirectories: true)
        try manager.copyItem(at: validFont, to: zipFont)
        try createZip(from: zipSource, at: zipURL)
        let zipContainsFonts = try FontArchiveUtility.containsSupportedFonts(zipURL)
        try expect(zipContainsFonts, "应识别含字体的 ZIP")

        let preparedZip = FontBatchPreparer(fileManager: manager).prepare(urls: [zipURL])
        defer { preparedZip.temporaryDirectories.forEach { try? manager.removeItem(at: $0) } }
        try expect(preparedZip.candidates.count == 1, "ZIP 内字体应被解压并识别")
        try expect(preparedZip.candidates.first?.familyName.isEmpty == false, "应读取字体家族名称")

        let plainZipSource = root.appendingPathComponent("plain-zip")
        let plainZipURL = root.appendingPathComponent("plain.zip")
        try manager.createDirectory(at: plainZipSource, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: plainZipSource.appendingPathComponent("readme.txt"))
        try createZip(from: plainZipSource, at: plainZipURL)
        let plainZipContainsFonts = try FontArchiveUtility.containsSupportedFonts(plainZipURL)
        try expect(!plainZipContainsFonts, "普通 ZIP 不应触发字体提醒")

        print("FontInstallerTests: all checks passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }

    static func createZip(from source: URL, at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "无法创建 ZIP 测试包")
    }
}

struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

