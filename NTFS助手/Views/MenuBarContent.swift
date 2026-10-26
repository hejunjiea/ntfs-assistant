import SwiftUI
import AppKit

/// 菜单栏快捷面板
struct MenuBarContent: View {
    @EnvironmentObject private var diskObserver: DiskObserver
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if diskObserver.disks.isEmpty {
            Text("未检测到外部磁盘")
        } else {
            ForEach(diskObserver.disks) { disk in
                Button {
                    if disk.isHandled {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: disk.mountPath)
                    } else {
                        diskObserver.mount(disk)
                    }
                } label: {
                    Text("\(disk.volumeName) · \(disk.isHandled ? "可读写" : "只读")")
                }
            }
        }

        Divider()

        Button("挂载全部") { diskObserver.mountAll() }
            .disabled(diskObserver.isBusy)
        Button("弹出全部") { diskObserver.ejectAll() }
            .disabled(diskObserver.isBusy)

        Divider()

        Button("打开主窗口") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
