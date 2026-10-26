import Foundation
import AppKit

/// 文件浏览器中的单个条目（文件或文件夹）
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    /// nil 表示大小仍在后台计算中
    var sizeBytes: Int64?
    var modificationDate: Date?
    let icon: NSImage

    var url: URL { URL(fileURLWithPath: path) }

    var sizeString: String {
        guard let sizeBytes else { return "计算中…" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var dateString: String {
        guard let modificationDate else { return "—" }
        return modificationDate.formatted(date: .numeric, time: .shortened)
    }

    var kindString: String {
        if isDirectory { return "文件夹" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "文件" : ext.uppercased()
    }
}
