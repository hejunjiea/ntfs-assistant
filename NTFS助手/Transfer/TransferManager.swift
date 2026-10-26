import Foundation
import Combine
import AppKit
import Darwin

/// 传输任务中心：串行队列、真实进度、取消、空间预检
final class TransferManager: ObservableObject {
    @Published private(set) var tasks: [TransferTask] = []
    @Published private(set) var isActive = false
    /// 存在同名文件时等待用户选择处理方式
    @Published var pendingConflict: ConflictPrompt?

    /// 冲突确认请求
    struct ConflictPrompt: Identifiable {
        let id = UUID()
        let urls: [URL]
        let destDir: String
        let conflictingNames: [String]
        /// 冲突项中属于文件夹的名称，覆盖会删除其全部内容
        let folderConflicts: [String]
    }

    /// 传输完成后用于刷新文件列表
    weak var browser: FileBrowserModel?

    private let logs: LogStore
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.disk.transfer", qos: .userInitiated)
    private let cancelLock = NSLock()
    private var cancelledIDs = Set<UUID>()
    private var isBusy = false
    private var hasNotifiedBatch = false

    private var completedCount: Int { tasks.filter { $0.state == .completed }.count }

    init(logStore: LogStore) {
        self.logs = logStore
    }

    /// 队列概览文案，例如 "2/5"
    var progressSummary: String {
        guard !tasks.isEmpty else { return "" }
        return "\(completedCount)/\(tasks.count)"
    }

    // MARK: - 入队

    func enqueue(urls: [URL], to destDir: String) {
        guard !destDir.isEmpty else { return }
        let valid = urls.filter { url in
            // 不能把文件夹复制进它自己内部
            destDir != url.path && !destDir.hasPrefix(url.path + "/")
        }
        if valid.count < urls.count {
            logs.add("❌ 已跳过 \(urls.count - valid.count) 项：目标目录位于源文件夹内部")
        }
        guard !valid.isEmpty else { return }

        // 目标存在同名项时先询问用户，而不是静默加序号或自动跳过
        var conflictingNames: [String] = []
        var folderConflicts: [String] = []
        for url in valid {
            let target = (destDir as NSString).appendingPathComponent(url.lastPathComponent)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: target, isDirectory: &isDirectory) else { continue }
            conflictingNames.append(url.lastPathComponent)
            if isDirectory.boolValue { folderConflicts.append(url.lastPathComponent) }
        }
        if !conflictingNames.isEmpty {
            pendingConflict = ConflictPrompt(urls: valid, destDir: destDir,
                                             conflictingNames: conflictingNames,
                                             folderConflicts: folderConflicts)
            return
        }
        addTasks(for: valid, destDir: destDir, conflictNames: []) { _ in .keepBoth }
    }

    /// 用户确认后入队。defaultPolicy 为统一策略，overrides 按文件名单独覆盖。
    /// 只有重名项会被「跳过」，非重名项始终传输。
    func resolveConflict(defaultPolicy: ConflictPolicy, overrides: [String: ConflictPolicy]) {
        guard let prompt = pendingConflict else { return }
        pendingConflict = nil
        addTasks(for: prompt.urls,
                 destDir: prompt.destDir,
                 conflictNames: Set(prompt.conflictingNames)) { name in
            overrides[name] ?? defaultPolicy
        }
    }

    func cancelConflict() {
        pendingConflict = nil
        logs.add("⏹ 已取消本次传输")
    }

    private func addTasks(for urls: [URL], destDir: String,
                          conflictNames: Set<String>,
                          policyFor: (String) -> ConflictPolicy) {
        let list = urls.filter { url in
            let name = url.lastPathComponent
            // 非重名项不受「跳过」影响
            guard conflictNames.contains(name) else { return true }
            return policyFor(name) != .skip
        }
        if list.count < urls.count {
            logs.add("⏭ 已跳过 \(urls.count - list.count) 项同名文件")
        }
        guard !list.isEmpty else { return }

        let newTasks = list.map {
            TransferTask(fileName: $0.lastPathComponent, sourceURL: $0,
                         destDir: destDir, conflictPolicy: policyFor($0.lastPathComponent))
        }
        tasks.append(contentsOf: newTasks)
        hasNotifiedBatch = false
        logs.add("📥 已加入队列 \(newTasks.count) 项，准备传输")
        processNext()
    }

    func cancel(_ id: UUID) {
        cancelLock.lock()
        cancelledIDs.insert(id)
        cancelLock.unlock()

        if let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].state == .pending {
            tasks[index].state = .cancelled
            tasks[index].message = "已取消"
            logs.add("⏹ 已取消: \(tasks[index].fileName)")
            processNext()
        }
    }

    func cancelAll() {
        for task in tasks where !task.isFinished {
            cancel(task.id)
        }
    }

    /// 清理已结束的任务记录
    func clearFinished() {
        tasks.removeAll { $0.isFinished }
    }

    // MARK: - 调度

    private func processNext() {
        guard !isBusy else { return }
        guard let index = tasks.firstIndex(where: { $0.state == .pending }) else {
            isActive = false
            notifyIfBatchFinished()
            if tasks.contains(where: { $0.state == .completed }) {
                browser?.reload()
            }
            return
        }
        isActive = true
        isBusy = true
        tasks[index].state = .running
        let task = tasks[index]
        queue.async { [weak self] in
            self?.perform(task)
        }
    }

    private func finishCurrent(taskID: UUID) {
        isBusy = false
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].speed = 0
            tasks[index].eta = nil
        }
        processNext()
    }

    /// 整批任务结束时推送一次系统通知
    private func notifyIfBatchFinished() {
        guard !hasNotifiedBatch, !tasks.isEmpty,
              tasks.allSatisfy({ $0.isFinished }) else { return }
        hasNotifiedBatch = true
        let completed = tasks.filter { $0.state == .completed }.count
        let failed = tasks.filter { $0.state == .failed }.count
        let body = failed > 0
            ? "完成 \(completed) 项，失败 \(failed) 项"
            : "全部 \(completed) 项传输完成"
        NotificationService.shared.notify(title: "传输结束", body: body)
    }

    private func updateTask(_ id: UUID, _ body: (inout TransferTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        body(&tasks[index])
    }

    // MARK: - 执行复制

    private func perform(_ task: TransferTask) {
        let taskID = task.id
        let total = totalBytes(at: task.sourceURL)

        // 空间预检：预留 5% 余量
        if let available = availableSpace(at: task.destDir), total > 0,
           Double(total) * 1.05 > Double(available) {
            DispatchQueue.main.async {
                self.updateTask(taskID) {
                    $0.state = .failed
                    $0.message = "空间不足"
                }
                self.logs.add("❌ 空间不足: \(task.fileName) 需要 \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))，可用 \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))")
                self.finishCurrent(taskID: taskID)
            }
            return
        }

        let destPath = resolveDestination(for: task)
        DispatchQueue.main.async {
            self.updateTask(taskID) {
                $0.bytesTotal = total
                $0.destPath = destPath
            }
            self.logs.add("🚀 开始传输: \(task.fileName)")
        }

        guard let copyState = copyfile_state_alloc() else {
            DispatchQueue.main.async {
                self.updateTask(taskID) { $0.state = .failed; $0.message = "初始化复制引擎失败" }
                self.logs.add("❌ 初始化复制引擎失败")
                self.finishCurrent(taskID: taskID)
            }
            return
        }
        defer { copyfile_state_free(copyState) }

        let context = CopyContext(taskID: taskID, total: total,
                                  isCancelled: { self.isCancelled(taskID) },
                                  onProgress: { done, progress, speed in
            DispatchQueue.main.async {
                self.updateTask(taskID) {
                    $0.bytesDone = done
                    $0.progress = progress
                    $0.speed = speed
                    if speed > 0, total > done {
                        $0.eta = Double(total - done) / speed
                    } else {
                        $0.eta = nil
                    }
                }
            }
        })
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        copyfile_state_set(copyState, UInt32(COPYFILE_STATE_STATUS_CTX), contextPointer)

        let callback: copyfile_callback_t = { what, _, state, _, _, ctx in
            guard what == COPYFILE_COPY_DATA, let state, let ctx else { return COPYFILE_CONTINUE }
            let context = Unmanaged<CopyContext>.fromOpaque(ctx).takeUnretainedValue()
            if context.isCancelled() { return COPYFILE_QUIT }
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            context.report(fileCopied: Int64(copied))
            return COPYFILE_CONTINUE
        }
        copyfile_state_set(copyState, UInt32(COPYFILE_STATE_STATUS_CB),
                           unsafeBitCast(callback, to: UnsafeMutableRawPointer.self))

        let success: Bool
        do {
            try copyItem(at: task.sourceURL, to: URL(fileURLWithPath: destPath),
                         state: copyState, context: context)
            success = true
        } catch {
            let message = error.localizedDescription
            try? fileManager.removeItem(atPath: destPath)
            DispatchQueue.main.async {
                if self.isCancelled(taskID) {
                    self.updateTask(taskID) { $0.state = .cancelled; $0.message = "已取消" }
                    self.logs.add("⏹ 已取消: \(task.fileName)")
                } else {
                    self.updateTask(taskID) { $0.state = .failed; $0.message = message }
                    self.logs.add("❌ 传输失败 \(task.fileName): \(message)")
                }
                self.finishCurrent(taskID: taskID)
            }
            return
        }

        if success {
            DispatchQueue.main.async {
                if self.isCancelled(taskID) {
                    try? self.fileManager.removeItem(atPath: destPath)
                    self.updateTask(taskID) { $0.state = .cancelled; $0.message = "已取消" }
                    self.logs.add("⏹ 已取消: \(task.fileName)")
                } else {
                    self.updateTask(taskID) {
                        $0.state = .completed
                        $0.progress = 1
                        $0.bytesDone = total
                    }
                    self.logs.add("✅ 传输完成: \(task.fileName)")
                }
                self.finishCurrent(taskID: taskID)
            }
        }
    }

    private final class CopyContext {
        let taskID: UUID
        let total: Int64
        let startedAt = Date()
        var finishedBytes: Int64 = 0
        var lastReport = Date.distantPast
        let isCancelled: () -> Bool
        let onProgress: (Int64, Double, Double) -> Void

        init(taskID: UUID, total: Int64, isCancelled: @escaping () -> Bool,
             onProgress: @escaping (Int64, Double, Double) -> Void) {
            self.taskID = taskID
            self.total = total
            self.isCancelled = isCancelled
            self.onProgress = onProgress
        }

        /// 每 0.1 秒上报一次，避免高频刷新 UI
        func report(fileCopied: Int64) {
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.1 else { return }
            lastReport = now
            let done = finishedBytes + fileCopied
            let progress = total > 0 ? min(Double(done) / Double(total), 1) : 0
            let elapsed = now.timeIntervalSince(startedAt)
            onProgress(done, progress, elapsed > 0 ? Double(done) / elapsed : 0)
        }
    }

    private func isCancelled(_ id: UUID) -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelledIDs.contains(id)
    }

    /// 递归复制：目录建好后逐项复制，符号链接原样保留，普通文件走 copyfile
    private func copyItem(at source: URL, to destination: URL,
                          state: copyfile_state_t, context: CopyContext) throws {
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        let type = attributes[.type] as? FileAttributeType

        if type == .typeDirectory {
            try fileManager.createDirectory(atPath: destination.path, withIntermediateDirectories: true)
            for child in try fileManager.contentsOfDirectory(atPath: source.path) {
                if context.isCancelled() { throw CancellationError() }
                try copyItem(at: source.appendingPathComponent(child),
                             to: destination.appendingPathComponent(child),
                             state: state, context: context)
            }
        } else if type == .typeSymbolicLink {
            let target = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        } else {
            let flags = copyfile_flags_t(COPYFILE_DATA | COPYFILE_XATTR)
            if copyfile(source.path, destination.path, state, flags) != 0 {
                let code = errno
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                              userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))])
            }
            context.finishedBytes += Int64((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    // MARK: - 辅助

    private func totalBytes(at url: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let child as URL in enumerator {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return total
        }
        return Int64(((try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0)
    }

    private func availableSpace(at path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

    /// 按冲突策略决定实际写入路径。
    /// 是否覆盖文件夹由用户在弹出的确认框中明确选择，此处直接执行。
    private func resolveDestination(for task: TransferTask) -> String {
        let target = (task.destDir as NSString).appendingPathComponent(task.fileName)
        guard fileManager.fileExists(atPath: target) else { return target }

        switch task.conflictPolicy {
        case .replace:
            try? fileManager.removeItem(atPath: target)
            return target
        case .keepBoth, .skip:
            return uniquePath(for: task.fileName, in: task.destDir)
        }
    }

    private func uniquePath(for fileName: String, in directory: String) -> String {
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
}
