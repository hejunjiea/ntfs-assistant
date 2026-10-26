import Foundation
import Combine
import AppKit

/// 文件列表排序字段
enum FileSortKey: String, CaseIterable, Identifiable {
    case name = "名称"
    case size = "大小"
    case date = "修改日期"
    case kind = "类型"

    var id: String { rawValue }
}

/// 文件浏览器状态与文件操作
final class FileBrowserModel: ObservableObject {
    @Published private(set) var files: [FileItem] = []
    @Published var selection = Set<FileItem.ID>()
    @Published private(set) var currentPath = ""
    @Published private(set) var rootPath = ""

    @Published var searchText = "" { didSet { rebuild() } }
    @Published var sortKey: FileSortKey = .name { didSet { rebuild() } }
    @Published var sortAscending = true { didSet { rebuild() } }
    @Published var showHiddenFiles = false { didSet { reload() } }

    private var rawFiles: [FileItem] = []
    private var pathStack: [String] = []
    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "com.disk.browser", qos: .userInitiated)
    private let logs: LogStore
    /// 每次加载目录生成新令牌，异步结果回来时比对，丢弃过期数据
    private var loadToken = UUID()
    private var sizeCache: [String: CachedSize] = [:]

    private struct CachedSize {
        let size: Int64
        let mtime: Date
    }

    init(logStore: LogStore) {
        self.logs = logStore
    }

    var canGoBack: Bool { pathStack.count > 1 }

    var selectedItems: [FileItem] {
        files.filter { selection.contains($0.id) }
    }

    /// 面包屑：从卷根到当前目录的逐级路径
    var breadcrumbs: [(name: String, path: String)] {
        guard !rootPath.isEmpty, currentPath.hasPrefix(rootPath) else { return [] }
        var result: [(String, String)] = []
        result.append(((rootPath as NSString).lastPathComponent, rootPath))
        let relative = String(currentPath.dropFirst(rootPath.count))
        var accumulated = rootPath
        for component in relative.split(separator: "/").map(String.init) where !component.isEmpty {
            accumulated = (accumulated as NSString).appendingPathComponent(component)
            result.append((component, accumulated))
        }
        return result
    }

    // MARK: - 导航

    /// 切换到某个磁盘根目录（重置导航栈）
    func setRoot(_ path: String) {
        guard !path.isEmpty else { return }
        rootPath = path
        pathStack = [path]
        loadDirectory(path)
    }

    /// 进入目录；若目标已在导航栈中则回退到该层级
    func navigate(to path: String) {
        guard path != currentPath else { return }
        if let index = pathStack.firstIndex(of: path) {
            pathStack = Array(pathStack.prefix(index + 1))
        } else {
            pathStack.append(path)
        }
        loadDirectory(path)
    }

    func goBack() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        loadDirectory(pathStack[pathStack.count - 1])
    }

    func reload() {
        guard !currentPath.isEmpty else { return }
        loadDirectory(currentPath)
    }

    /// 清空浏览器状态（未选择磁盘时调用）
    func clear() {
        rootPath = ""
        currentPath = ""
        pathStack = []
        rawFiles = []
        files = []
        selection = []
        searchText = ""
    }

    /// 在访达中定位当前目录
    func revealCurrentDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentPath)
    }

    // MARK: - 目录加载

    private func loadDirectory(_ path: String) {
        guard fileManager.fileExists(atPath: path) else {
            files = []
            return
        }
        currentPath = path
        let token = UUID()
        loadToken = token
        let showHidden = showHiddenFiles

        scanQueue.async { [weak self] in
            guard let self else { return }
            // 使用 options 控制是否包含隐藏文件
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            guard let contents = try? self.fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
            ) else {
                DispatchQueue.main.async {
                    guard self.loadToken == token else { return }
                    self.files = []
                    self.rawFiles = []
                }
                return
            }

            let workspace = NSWorkspace.shared
            let items = contents.map { url -> FileItem in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileItem(name: url.lastPathComponent, path: url.path,
                                isDirectory: isDir, icon: workspace.icon(forFile: url.path))
            }

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.rawFiles = items
                self.selection = []
                self.rebuild()
                self.startSizeScan(token: token, items: items)
            }
        }
    }

    private func rebuild() {
        var result = rawFiles
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        result.sort { lhs, rhs in
            // 文件夹始终排在文件之前
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let cmp: ComparisonResult
            switch sortKey {
            case .name:
                cmp = lhs.name.localizedStandardCompare(rhs.name)
            case .size:
                let a = lhs.sizeBytes ?? 0
                let b = rhs.sizeBytes ?? 0
                cmp = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            case .date:
                let a = lhs.modificationDate ?? .distantPast
                let b = rhs.modificationDate ?? .distantPast
                cmp = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            case .kind:
                cmp = lhs.kindString.localizedStandardCompare(rhs.kindString)
            }
            if cmp == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
        files = result
    }

    // MARK: - 大小计算

    /// 逐个后台计算大小与修改时间，完成一个更新一个，避免大目录阻塞界面
    private func startSizeScan(token: UUID, items: [FileItem]) {
        for item in items {
            scanQueue.async { [weak self] in
                guard let self else { return }
                let (size, mtime) = self.sizeAndDate(of: item)
                DispatchQueue.main.async {
                    guard self.loadToken == token else { return }
                    if let index = self.rawFiles.firstIndex(where: { $0.path == item.path }) {
                        self.rawFiles[index].sizeBytes = size
                        self.rawFiles[index].modificationDate = mtime
                    }
                    if let index = self.files.firstIndex(where: { $0.path == item.path }) {
                        self.files[index].sizeBytes = size
                        self.files[index].modificationDate = mtime
                    }
                }
            }
        }
    }

    /// 文件夹大小带缓存：目录 mtime 未变化时直接复用上次结果
    private func sizeAndDate(of item: FileItem) -> (Int64, Date?) {
        let attributes = try? fileManager.attributesOfItem(atPath: item.path)
        let mtime = attributes?[.modificationDate] as? Date
        guard item.isDirectory else {
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return (size, mtime)
        }
        if let mtime, let cached = sizeCache[item.path], cached.mtime == mtime {
            return (cached.size, mtime)
        }
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: item.path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        if let mtime {
            sizeCache[item.path] = CachedSize(size: total, mtime: mtime)
        }
        return (total, mtime)
    }

    // MARK: - 文件操作

    func open(_ item: FileItem) {
        if item.isDirectory {
            navigate(to: item.path)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// 批量删除（永久删除，调用方需先确认）
    func delete(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let paths = items.map { $0.path }
        let names = items.map { $0.name }
        scanQueue.async { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            for (path, name) in zip(paths, names) {
                do {
                    try self.fileManager.removeItem(atPath: path)
                    self.clearCache(for: path)
                } catch {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                if failures.isEmpty {
                    self.logs.add("✅ 已删除 \(paths.count) 项")
                } else {
                    self.logs.add("❌ 删除失败 \(failures.count) 项 — \(failures.joined(separator: "; "))")
                }
                self.reload()
            }
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.name, !trimmed.contains("/") else { return }
        let parent = (item.path as NSString).deletingLastPathComponent
        let destination = (parent as NSString).appendingPathComponent(trimmed)

        scanQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.fileManager.moveItem(atPath: item.path, toPath: destination)
                DispatchQueue.main.async {
                    self.clearCache(for: item.path)
                    self.logs.add("✅ 重命名: \(item.name) → \(trimmed)")
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs.add("❌ 重命名失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !currentPath.isEmpty, !trimmed.contains("/") else { return }
        let destination = uniquePath(for: trimmed, in: currentPath)

        scanQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.fileManager.createDirectory(atPath: destination, withIntermediateDirectories: true)
                DispatchQueue.main.async {
                    self.logs.add("✅ 新建文件夹: \((destination as NSString).lastPathComponent)")
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs.add("❌ 新建文件夹失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 复制/移动目标路径，重名时自动追加序号："a.txt" → "a 2.txt"
    func uniquePath(for fileName: String, in directory: String) -> String {
        var candidate = (directory as NSString).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: candidate) else { return candidate }
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = (directory as NSString).appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate) { return candidate }
            index += 1
        }
    }

    private func clearCache(for path: String) {
        sizeCache.removeValue(forKey: path)
    }
}
