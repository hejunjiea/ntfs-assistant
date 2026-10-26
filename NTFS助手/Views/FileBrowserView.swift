import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 文件浏览区：工具栏、面包屑、文件表格、快捷键
struct FileBrowserView: View {
    @ObservedObject var browser: FileBrowserModel
    @ObservedObject var transfer: TransferManager

    @State private var showRenameAlert = false
    @State private var showNewFolderAlert = false
    @State private var showDeleteAlert = false
    @State private var inputText = ""
    @State private var renameTarget: FileItem?
    @State private var pendingDelete: [FileItem] = []
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            fileTable
        }
        .background(QuickLookAnchor().frame(width: 0, height: 0))
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("输入新名称", text: $inputText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let target = renameTarget {
                    browser.rename(target, to: inputText)
                }
            }
        }
        .alert("新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名称", text: $inputText)
            Button("取消", role: .cancel) {}
            Button("创建") { browser.createFolder(named: inputText) }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { browser.delete(pendingDelete) }
        } message: {
            if pendingDelete.count == 1 {
                Text("「\(pendingDelete.first?.name ?? "")」将被永久删除，无法从废纸篓恢复。")
            } else {
                Text("\(pendingDelete.count) 项将被永久删除，无法从废纸篓恢复。")
            }
        }
        .sheet(item: $transfer.pendingConflict) { prompt in
            ConflictSheet(prompt: prompt,
                          onResolve: { policy in transfer.resolveConflict(policy) },
                          onCancel: { transfer.cancelConflict() })
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.borderless)
            .disabled(!browser.canGoBack)
            .help("返回上一级")

            breadcrumb
            Spacer()

            TextField("搜索", text: $browser.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)

            Menu {
                ForEach(FileSortKey.allCases) { key in
                    Button {
                        if browser.sortKey == key {
                            browser.sortAscending.toggle()
                        } else {
                            browser.sortKey = key
                            browser.sortAscending = true
                        }
                    } label: {
                        if browser.sortKey == key {
                            Label(key.rawValue, systemImage: browser.sortAscending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(key.rawValue)
                        }
                    }
                }
                Divider()
                Toggle("显示隐藏文件", isOn: $browser.showHiddenFiles)
                Button("刷新") { browser.reload() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("排序与显示选项")

            Button {
                inputText = ""
                showNewFolderAlert = true
            } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
            .controlSize(.small)

            Button("在访达中打开") { browser.revealCurrentDirectory() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var breadcrumb: some View {
        HStack(spacing: 3) {
            ForEach(browser.breadcrumbs, id: \.path) { crumb in
                Button {
                    browser.navigate(to: crumb.path)
                } label: {
                    Text(crumb.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(crumb.path == browser.currentPath ? .primary : .secondary)

                if crumb.path != browser.breadcrumbs.last?.path {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 文件表格

    private var fileTable: some View {
        Table(browser.files, selection: $browser.selection) {
            TableColumn("名称") { item in
                HStack(spacing: 8) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(item.name).lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { browser.open(item) }
                .contextMenu { rowMenu(for: item) }
                .onDrag { NSItemProvider(object: item.url as NSURL) }
            }

            TableColumn("大小") { item in
                Text(item.sizeString)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { browser.open(item) }
            }
            .width(min: 70, ideal: 90)

            TableColumn("修改日期") { item in
                Text(item.dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .width(min: 110, ideal: 140)

            TableColumn("类型") { item in
                Text(item.kindString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 80)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for item: FileItem) -> some View {
        let targets = actionTargets(for: item)

        Button(targets.count > 1 ? "删除 \(targets.count) 项" : "删除", role: .destructive) {
            requestDelete(targets)
        }

        if targets.count == 1 {
            Button("重命名") {
                renameTarget = item
                inputText = item.name
                showRenameAlert = true
            }
        }

        Divider()

        Button(targets.count > 1 ? "复制 \(targets.count) 项" : "复制") {
            copyToPasteboard(targets)
        }

        if targets.count == 1 {
            Button("在访达中显示") {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            }
        }
    }

    /// 右键项若在选中集内则批量操作，否则只操作该项
    private func actionTargets(for item: FileItem) -> [FileItem] {
        if browser.selection.contains(item.id), browser.selection.count > 1 {
            return browser.selectedItems
        }
        return [item]
    }

    // MARK: - 拖入

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let destDir = browser.currentPath
        guard !destDir.isEmpty else { return false }

        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async { collected.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            transfer.enqueue(urls: collected, to: destDir)
        }
        return !providers.isEmpty
    }

    // MARK: - 剪贴板与删除

    private func copyToPasteboard(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
    }

    private func pasteFromPasteboard() {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return }
        transfer.enqueue(urls: urls, to: browser.currentPath)
    }

    private func requestDelete(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        pendingDelete = items
        showDeleteAlert = true
    }

    // MARK: - 快捷键

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 焦点在文本输入控件时不拦截，保留原生编辑快捷键
            if isEditingText() { return event }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

            switch event.keyCode {
            case 49: // 空格 → QuickLook
                if flags.isEmpty {
                    let urls = browser.selectedItems.map { $0.url }
                    QuickLookController.shared.toggle(urls: urls)
                    return nil
                }
            case 51: // Delete
                if flags == .command {
                    requestDelete(browser.selectedItems)
                    return nil
                }
            case 8: // C
                if flags == .command {
                    copyToPasteboard(browser.selectedItems)
                    return nil
                }
            case 9: // V
                if flags == .command {
                    pasteFromPasteboard()
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func isEditingText() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if let field = responder as? NSTextField, field.isEditable { return true }
        return false
    }
}
