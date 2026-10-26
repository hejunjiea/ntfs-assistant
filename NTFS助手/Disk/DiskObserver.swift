import Foundation
import Combine
import DiskArbitration
import Darwin
import AppKit

/// 负责磁盘枚举、挂载接管、弹出与只读恢复
final class DiskObserver: ObservableObject {
    @Published private(set) var disks: [GenericDisk] = []
    @Published var isBusy = false

    private let logs: LogStore
    private var session: DASession?
    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "com.disk.diskScan", qos: .userInitiated)

    init(logStore: LogStore) {
        self.logs = logStore
        startObserving()
        scan()
    }

    // MARK: - 监听与扫描

    /// 通过 DiskArbitration 监听磁盘挂载/变更信号
    private func startObserving() {
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, ctx in
            guard let ctx else { return }
            Unmanaged<DiskObserver>.fromOpaque(ctx).takeUnretainedValue().scan()
        }, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// 扫描 /dev 节点，结合 getfsstat 确认实际挂载状态
    func scan(completion: (() -> Void)? = nil) {
        scanQueue.async { [weak self] in
            guard let self, let session = self.session else { return }
            let result = self.collectDisks(session: session)
            DispatchQueue.main.async {
                self.disks = result
                completion?()
            }
        }
    }

    private func collectDisks(session: DASession) -> [GenericDisk] {
        var kernelMounts = [String: String]()
        let count = getfsstat(nil, 0, Int32(MNT_NOWAIT))
        if count > 0 {
            let bufferSize = Int(count) * MemoryLayout<statfs>.stride
            let buffer = UnsafeMutablePointer<statfs>.allocate(capacity: Int(count))
            defer { buffer.deallocate() }
            let actual = getfsstat(buffer, Int32(bufferSize), Int32(MNT_NOWAIT))
            for i in 0..<Int(actual) {
                let mnt = buffer[i]
                kernelMounts[cString(from: mnt.f_mntonname)] = cString(from: mnt.f_fstypename)
            }
        }

        guard let devEntries = try? fileManager.contentsOfDirectory(atPath: "/dev") else { return [] }
        let nodePattern = try? NSRegularExpression(pattern: "^disk\\d+s\\d+$")
        let nodes = devEntries.filter { name in
            guard let nodePattern else { return false }
            return nodePattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }

        let supportedFormats = ["ntfs", "msdos", "exfat", "ext", "ext4", "fat32", "hfs"]
        let blackList = ["efi", "apfs_container", "apple_partition_map", "recovery"]
        var result: [GenericDisk] = []

        for node in nodes {
            guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/\(node)"),
                  let description = DADiskCopyDescription(disk) as NSDictionary? else { continue }

            let kind = (description[kDADiskDescriptionVolumeKindKey as String] as? String ?? "Unknown").lowercased()
            guard !blackList.contains(where: { kind.contains($0) }) else { continue }

            let name = (description[kDADiskDescriptionVolumeNameKey as String] as? String) ?? "未命名卷(\(node))"
            guard !name.contains("VM") else { continue }
            guard supportedFormats.contains(where: { kind.contains($0) }) else { continue }

            let parentDisk = DADiskCopyWholeDisk(disk)
            let parentID = parentDisk.flatMap { d -> String? in
                guard let bsdName = DADiskGetBSDName(d) else { return nil }
                return String(cString: bsdName)
            } ?? node

            let mountPath = "/Volumes/\(name)"
            let actualType = kernelMounts[mountPath] ?? ""
            // NTFS 卷被内核以 ntfs 只读挂载；被 ntfs-3g 接管后类型会变成 ntfs-3g 等
            let isHandled = !actualType.isEmpty && actualType != "ntfs"

            let displayType = kind.contains("msdos") ? "FAT32" : kind.uppercased()
            var info = GenericDisk(id: node, parentID: parentID, volumeName: name,
                                   fsType: displayType, isHandled: isHandled, mountPath: mountPath)

            if isHandled {
                let url = URL(fileURLWithPath: mountPath)
                if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
                    let total = Double(values.volumeTotalCapacity ?? 0)
                    let available = Double(values.volumeAvailableCapacity ?? 0)
                    info.capacityText = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .decimal)
                    info.usagePercent = total > 0 ? (total - available) / total : 0
                }
            }
            result.append(info)
        }
        return result.sorted { $0.volumeName.localizedStandardCompare($1.volumeName) == .orderedAscending }
    }

    /// 将 C 字符元组转为 Swift 字符串
    private func cString<T>(from tuple: T) -> String {
        var temp = tuple
        return withUnsafePointer(to: &temp) { pointer in
            let chars = UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            return String(cString: chars, encoding: .utf8) ?? "未知"
        }
    }

    // MARK: - 挂载 / 卸载

    func mountAll() {
        let targets = disks.filter { !$0.isHandled }
        guard !targets.isEmpty else {
            logs.add("没有需要接管的磁盘")
            return
        }
        execute(targets.map { mountCommand(for: $0) }.joined(separator: " ; "),
                successMessage: "已接管 \(targets.count) 个磁盘为读写模式")
    }

    func mount(_ disk: GenericDisk) {
        execute(mountCommand(for: disk), successMessage: "「\(disk.volumeName)」已可读写")
    }

    /// 卸载读写挂载，并恢复系统默认的只读挂载
    func restoreReadOnly(_ disk: GenericDisk) {
        let cmd = "diskutil unmount force /dev/\(disk.id) ; diskutil mount /dev/\(disk.id)"
        execute(cmd)
    }

    /// 弹出整块物理磁盘
    func ejectAll() {
        let parents = Set(disks.map { $0.parentID })
        guard !parents.isEmpty else { return }
        let cmds = parents.map { "diskutil unmountDisk force /dev/\($0) ; diskutil eject /dev/\($0)" }
        execute(cmds.joined(separator: " ; "))
    }

    /// 挂载原理：结束系统自带的 fsck 检查 → 强制卸载只读挂载 → 用 ntfs-3g 读写挂载
    /// 安全注意：清理挂载点必须用 rmdir 而不是 rm -rf。
    /// 若磁盘正被占用导致卸载失败，rm -rf 会递归删除“仍挂载着”的磁盘里的全部文件（已验证），
    /// 而 rmdir 遇到挂载点只会报 Resource busy 并拒绝执行，不会损坏数据。
    private func mountCommand(for disk: GenericDisk) -> String {
        let node = "/dev/\(disk.id)"
        let mountPath = "/Volumes/\(disk.volumeName)"
        if disk.isNTFS {
            let driver = findDriver("ntfs-3g")
            return "pkill -9 fsck_ntfs ; diskutil unmount force \(node) ; "
                + "rmdir \(shellQuote(mountPath)) 2>/dev/null ; mkdir -p \(shellQuote(mountPath)) ; "
                + "\(shellQuote(driver)) \(node) \(shellQuote(mountPath)) "
                + "-o local,allow_other,auto_xattr,volname=\(shellQuote(disk.volumeName)),force"
        }
        return "diskutil unmount force \(node) ; diskutil mount \(node)"
    }

    /// 用单引号包裹并转义，防止卷标中的特殊字符被 Shell 解释
    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 兼容 Homebrew（Intel / Apple Silicon）与系统路径
    private func findDriver(_ name: String) -> String {
        let candidates = ["/usr/local/sbin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        return candidates.first { fileManager.fileExists(atPath: $0) } ?? name
    }

    /// 挂载失败时自检依赖，给出可操作的原因，而不是笼统的“操作失败”
    private func diagnoseFailure() {
        let drivers = ["/usr/local/sbin/ntfs-3g", "/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"]
        let hasDriver = drivers.contains { fileManager.fileExists(atPath: $0) }
        let hasFUSE = fileManager.fileExists(atPath: "/Library/Filesystems/macfuse.fs")

        var missing: [String] = []
        if !hasDriver { missing.append("ntfs-3g") }
        if !hasFUSE { missing.append("macFUSE") }

        if !missing.isEmpty {
            logs.add("❌ 挂载失败：未检测到 \(missing.joined(separator: " 和 "))。请按配置向导安装后重启再试")
        } else {
            logs.add("❌ 挂载失败：磁盘可能正被其他程序占用。请关闭访达窗口与 Spotlight 索引后重试；"
                     + "若仍失败，右键该磁盘选择「卸载并恢复只读」再重新接管")
        }
    }

    /// 通过 osascript 以管理员权限执行（会触发系统授权弹窗）
    private func execute(_ command: String, successMessage: String? = nil) {
        isBusy = true
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                if proc.terminationStatus == 0 {
                    self.logs.add("✅ 磁盘操作完成")
                    if let successMessage {
                        NotificationService.shared.notify(title: "NTFS助手", body: successMessage)
                    }
                } else {
                    self.diagnoseFailure()
                }
                self.scan { self.isBusy = false }
            }
        }
        do {
            try process.run()
        } catch {
            isBusy = false
            logs.add("❌ 无法启动授权进程: \(error.localizedDescription)")
        }
    }
}
