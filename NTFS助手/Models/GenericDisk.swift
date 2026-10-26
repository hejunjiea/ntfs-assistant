import Foundation

/// 外部磁盘卷信息
struct GenericDisk: Identifiable, Hashable {
    /// 磁盘节点 ID（如 disk4s1）
    let id: String
    /// 物理整盘 ID，用于整盘弹出
    let parentID: String
    let volumeName: String
    /// 展示用文件系统类型（NTFS / FAT32 / EXFAT…）
    let fsType: String
    /// 是否已由本程序接管为读写模式
    var isHandled: Bool = false
    var mountPath: String = ""
    var capacityText: String = "未知"
    /// 已用比例 0.0 – 1.0
    var usagePercent: Double = 0

    var isNTFS: Bool { fsType.uppercased().contains("NTFS") }
}
