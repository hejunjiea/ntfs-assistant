import SwiftUI

/// 左侧磁盘列表
struct DiskListView: View {
    @ObservedObject var diskObserver: DiskObserver
    @Binding var selectedDisk: GenericDisk?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    diskObserver.mountAll()
                } label: {
                    Label("一键挂载", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    diskObserver.ejectAll()
                } label: {
                    Label("全盘弹出", systemImage: "eject.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(10)
            .disabled(diskObserver.isBusy)

            Divider()

            List(diskObserver.disks, selection: $selectedDisk) { disk in
                diskRow(disk)
                    .padding(.vertical, 4)
                    .tag(disk)
                    .contextMenu {
                        if !disk.isHandled {
                            Button("接管为读写模式") { diskObserver.mount(disk) }
                        } else {
                            Button("卸载并恢复只读") { diskObserver.restoreReadOnly(disk) }
                        }
                        Divider()
                        Button("在访达中打开") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: disk.mountPath)
                        }
                    }
            }
        }
        .navigationTitle("NTFS助手")
    }

    @ViewBuilder
    private func diskRow(_ disk: GenericDisk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: disk.isNTFS ? "externaldrive.badge.icloud" : "externaldrive.fill")
                    .foregroundColor(disk.isHandled ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(disk.volumeName).font(.headline).lineLimit(1)
                    Text(disk.fsType)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                }
                Spacer()
                if disk.isHandled {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                } else if diskObserver.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            if disk.isHandled {
                ProgressView(value: disk.usagePercent)
                    .tint(disk.usagePercent > 0.9 ? .red : .blue)
                Text("\(disk.capacityText) · \(Int(disk.usagePercent * 100))% 已用")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                Text("只读挂载 · 等待接管")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
    }
}
