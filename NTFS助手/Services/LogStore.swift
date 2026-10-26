import Foundation
import Combine

/// 全局操作日志存储
final class LogStore: ObservableObject {
    @Published var entries: [String] = ["系统就绪..."]
    /// 最近一条错误，用于顶部错误提示条
    @Published var lastError: String?

    private let maxEntries = 100
    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func add(_ message: String) {
        let entry = "[\(formatter.string(from: Date()))] \(message)"
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.append(entry) }
        }
    }

    func clear() {
        entries = ["日志已清空"]
    }

    private func append(_ entry: String) {
        entries.append(entry)
        // 错误同时弹出顶部提示条
        if entry.contains("❌") { lastError = entry }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
