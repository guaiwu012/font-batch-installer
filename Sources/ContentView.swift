import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = InstallerViewModel()
    @StateObject private var requestCenter = FontRequestCenter.shared
    @StateObject private var loginItemController = LoginItemController()
    @AppStorage("monitorDownloads") private var monitorDownloads = true
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                mainContent
                Divider()
                footer
            }
        }
        .onChange(of: monitorDownloads) { _, _ in
            NotificationCenter.default.post(name: .downloadWatchPreferenceChanged, object: nil)
        }
        .onReceive(requestCenter.$request.compactMap { $0 }) { request in
            model.prepare(urls: request.urls, automaticallyDetected: request.automaticallyDetected)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseFontFiles)) { _ in
            chooseFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseFontFolder)) { _ in
            chooseFolder()
        }
        .alert(
            "无法更改开机监控",
            isPresented: Binding(
                get: { loginItemController.alertMessage != nil },
                set: { if !$0 { loginItemController.alertMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { loginItemController.alertMessage = nil }
        } message: {
            Text(loginItemController.alertMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch model.phase {
        case .ready:
            ScrollView {
                VStack(spacing: 22) {
                    dropZone
                    actionButtons
                    helperCard
                }
                .padding(28)
            }
        case .scanning:
            progressContent(
                icon: "doc.zipper",
                title: "正在读取字体包…",
                detail: "解压 ZIP，并识别字体家族和字重"
            )
        case .reviewing:
            reviewContent
        case .installing:
            progressContent(
                icon: "arrow.down.doc.fill",
                title: "正在安装 \(model.selectedCount) 个字体文件…",
                detail: "旧版本会先备份，再安装到当前用户"
            )
        case .finished:
            ScrollView {
                VStack(spacing: 18) {
                    if let summary = model.summary {
                        summaryCard(summary)
                        resultList(summary)
                    }
                    Button("继续安装") { model.reset() }
                        .buttonStyle(.borderedProminent)
                        .tint(brandPurple)
                        .controlSize(.large)
                }
                .padding(28)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [brandPurple, Color(red: 0.04, green: 0.57, blue: 0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                Image(systemName: "character.textbox")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("字装一下")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("字体包丢进来，挑好字重一起装")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("当前用户", systemImage: "person.crop.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.secondary.opacity(0.1), in: Capsule())
                .accessibilityLabel("字体将安装到当前用户")

            Menu {
                Toggle("监控“下载”文件夹", isOn: $monitorDownloads)
                Toggle(
                    "开机后自动监控",
                    isOn: Binding(
                        get: { loginItemController.isEnabled },
                        set: { enabled in
                            if enabled { monitorDownloads = true }
                            loginItemController.setEnabled(enabled)
                        }
                    )
                )
                Divider()
                Text("只在确认 ZIP 中含字体后提醒")
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isDropTargeted ? brandPurple.opacity(0.18) : brandPurple.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "doc.zipper")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(brandPurple)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 5) {
                Text("把字体、ZIP 或文件夹拖到这里")
                    .font(.system(size: 18, weight: .semibold))
                Text("先预览字重，再确认批量安装")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 205)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isDropTargeted ? brandPurple.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? brandPurple : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 7])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: acceptDrop)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("字体和 ZIP 拖放区域")
        .accessibilityHint("将字体、ZIP 或包含字体的文件夹拖到这里")
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: chooseFiles) {
                Label("选择字体或 ZIP", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(brandPurple)
            .controlSize(.large)
            .accessibilityHint("一次选择一个或多个字体文件或 ZIP 压缩包")

            Button(action: chooseFolder) {
                Label("选择文件夹", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("递归查找文件夹里的字体和 ZIP")
        }
    }

    private var helperCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: monitorDownloads ? "bell.badge.fill" : "bell.slash")
                .foregroundStyle(monitorDownloads ? brandPurple : .secondary)
                .font(.system(size: 17, weight: .medium))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(monitorDownloads ? "下载监控已开启" : "下载监控已暂停")
                    .font(.system(size: 13, weight: .semibold))
                Text(monitorDownloads
                     ? "发现新字体或字体 ZIP 后会弹出字重清单；普通 ZIP 不打扰。"
                     : "可从右上角设置重新开启，字体只安装到你的账户。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func progressContent(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(brandPurple.opacity(0.1)).frame(width: 78, height: 78)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(brandPurple)
                    .accessibilityHidden(true)
            }
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: model.wasAutomaticallyDetected ? "bell.badge.fill" : "textformat.alt")
                    .font(.system(size: 24))
                    .foregroundStyle(brandPurple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.wasAutomaticallyDetected ? "发现字体包，要安装哪些字重？" : "选择要安装的字体与字重")
                        .font(.system(size: 17, weight: .semibold))
                    Text(reviewSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text("\(model.candidates.count) 个文件")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            .padding(22)

            HStack(spacing: 8) {
                Button("全选") { model.selectAll() }
                Button("只选常规字重") { model.selectRegularWeights() }
                Button("清空") { model.clearSelection() }
                Spacer()
                Text("已选择 \(model.selectedCount) 个")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            List(model.candidates) { candidate in
                Toggle(
                    isOn: Binding(
                        get: { model.selectedCandidateIDs.contains(candidate.id) },
                        set: { _ in model.toggleSelection(for: candidate) }
                    )
                ) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(candidate.familyName)
                                    .font(.system(size: 13, weight: .semibold))
                                if candidate.isCollection {
                                    Text("字体集合")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(brandPurple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(brandPurple.opacity(0.1), in: Capsule())
                                }
                            }
                            Text(candidate.styleSummary)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(candidate.filename)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel("\(candidate.familyName)，\(candidate.styleSummary)")
            }
            .listStyle(.inset)

            if !model.preparationErrors.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("另有 \(model.preparationErrors.count) 个文件无法读取")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }

            Divider()
            HStack {
                Button("取消") { model.cancelReview() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("集合字体包含多个字重，会作为一个文件整体安装")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("安装所选 \(model.selectedCount) 个") { model.installSelected() }
                    .buttonStyle(.borderedProminent)
                    .tint(brandPurple)
                    .controlSize(.large)
                    .disabled(model.selectedCount == 0)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
    }

    private func summaryCard(_ summary: FontInstallSummary) -> some View {
        let success = summary.failedCount == 0 && summary.discoveredCount > 0
        return HStack(spacing: 14) {
            Image(systemName: success ? "checkmark.circle.fill" : (summary.discoveredCount == 0 ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"))
                .font(.system(size: 28))
                .foregroundStyle(success ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(summaryTitle(summary)).font(.system(size: 15, weight: .semibold))
                Text(summaryDetail(summary)).font(.system(size: 13)).foregroundStyle(.secondary)
                if summary.discoveredCount == 0, let firstError = model.preparationErrors.first {
                    Text(firstError).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer()
        }
        .padding(16)
        .background((success ? Color.green : Color.orange).opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func resultList(_ summary: FontInstallSummary) -> some View {
        Group {
            if !summary.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(summary.items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon(item.status))
                                .foregroundStyle(statusColor(item.status))
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                        if index < summary.items.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "folder.badge.person.crop").accessibilityHidden(true)
            Text("安装位置：~/Library/Fonts")
            Spacer()
            Label(
                monitorDownloads ? "正在监控下载" : "下载监控已暂停",
                systemImage: monitorDownloads ? "eye" : "eye.slash"
            )
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }

    private var reviewSubtitle: String {
        let names = model.sourceNames.prefix(2).joined(separator: "、")
        if model.sourceNames.count > 2 { return "\(names) 等 \(model.sourceNames.count) 项" }
        return names
    }

    private var brandPurple: Color { Color(red: 0.49, green: 0.23, blue: 0.93) }

    private func chooseFiles() {
        guard !model.isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择字体或 ZIP"
        panel.prompt = "查看字体与字重"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["otf", "ttf", "ttc", "otc", "dfont", "zip"].compactMap {
            UTType(filenameExtension: $0)
        }
        if panel.runModal() == .OK { model.prepare(urls: panel.urls) }
    }

    private func chooseFolder() {
        guard !model.isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择包含字体或 ZIP 的文件夹"
        panel.prompt = "扫描文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.prepare(urls: panel.urls) }
    }

    private func acceptDrop(providers: [NSItemProvider]) -> Bool {
        guard !model.isBusy else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                defer { group.leave() }
                guard let url = object as? URL else { return }
                lock.lock(); urls.append(url); lock.unlock()
            }
        }

        group.notify(queue: .main) { model.prepare(urls: urls) }
        return true
    }

    private func summaryTitle(_ summary: FontInstallSummary) -> String {
        if summary.discoveredCount == 0 { return "没有找到可安装的字体" }
        if summary.failedCount > 0 { return "部分字体未能安装" }
        return "安装完成"
    }

    private func summaryDetail(_ summary: FontInstallSummary) -> String {
        if summary.discoveredCount == 0 { return "请检查 ZIP，或选择 OTF、TTF、TTC、OTC、DFONT 文件" }
        var parts = ["成功 \(summary.installedCount) 个"]
        if summary.skippedCount > 0 { parts.append("跳过 \(summary.skippedCount) 个") }
        if summary.failedCount > 0 { parts.append("失败 \(summary.failedCount) 个") }
        return parts.joined(separator: " · ")
    }

    private func statusIcon(_ status: FontInstallItem.Status) -> String {
        switch status {
        case .installed: return "checkmark.circle.fill"
        case .skipped: return "arrow.right.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: FontInstallItem.Status) -> Color {
        switch status {
        case .installed: return .green
        case .skipped: return .secondary
        case .failed: return .red
        }
    }
}

