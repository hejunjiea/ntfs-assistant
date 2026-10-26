import Foundation

/// 传输任务状态机
enum TransferState: Equatable {
    case pending      // 排队中
    case running      // 传输中
    case completed    // 已完成
    case failed       // 失败
    case cancelled    // 已取消
}

/// 单个文件/文件夹的传输任务
struct TransferTask: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let sourceURL: URL
    /// 目标目录
    let destDir: String
    /// 实际写入路径（重名时会追加序号）
    var destPath: String = ""

    var state: TransferState = .pending
    var bytesTotal: Int64 = 0
    var bytesDone: Int64 = 0
    /// 0.0 – 1.0
    var progress: Double = 0
    /// 字节/秒
    var speed: Double = 0
    /// 预计剩余秒数，nil 表示尚不可估算
    var eta: TimeInterval?
    var message: String?

    var isFinished: Bool {
        state == .completed || state == .failed || state == .cancelled
    }

    var speedText: String {
        guard state == .running, speed > 0 else { return "—" }
        return String(format: "%.1f MB/s", speed / 1024 / 1024)
    }

    var etaText: String {
        guard state == .running, let eta, eta.isFinite, eta > 0 else { return "—" }
        if eta < 60 { return String(format: "剩余 %.0f 秒", eta) }
        if eta < 3600 { return String(format: "剩余 %.0f 分", eta / 60) }
        return String(format: "剩余 %.1f 小时", eta / 3600)
    }

    var sizeText: String {
        guard bytesTotal > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytesTotal, countStyle: .file)
    }
}
