import SwiftUI
import AppKit
import Quartz

/// 封装 QuickLook 预览面板（空格键预览）
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    var isVisible: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    /// 切换预览：已打开则刷新内容，未打开则显示
    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            guard !urls.isEmpty else {
                panel.orderOut(nil)
                return
            }
            self.urls = urls
            panel.reloadData()
        } else {
            guard !urls.isEmpty else { return }
            self.urls = urls
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < urls.count else { return nil }
        return urls[index] as NSURL
    }
}

/// 放入窗口 responder 链，让 QLPreviewPanel 能接管控制权
struct QuickLookAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        QuickLookAnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class QuickLookAnchorView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}
