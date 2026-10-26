import SwiftUI

/// 同名冲突确认面板：列出全部冲突项，需勾选「全部同意」后才能选择处理方式
struct ConflictSheet: View {
    let prompt: TransferManager.ConflictPrompt
    let onResolve: (ConflictPolicy) -> Void
    let onCancel: () -> Void

    @State private var agreed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("目标位置已存在同名项")
                    .font(.title3)
                    .bold()
            }

            Text("以下 \(prompt.conflictingNames.count) 项与目标目录中的内容重名：")
                .font(.callout)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prompt.conflictingNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: prompt.folderConflicts.contains(name) ? "folder.fill" : "doc.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            if prompt.folderConflicts.contains(name) {
                                Text("文件夹")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(3)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(10)
            }
            .frame(height: min(CGFloat(prompt.conflictingNames.count) * 22 + 20, 160))
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)

            if !prompt.folderConflicts.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text("其中 \(prompt.folderConflicts.count) 项是文件夹，选择「覆盖」会删除该文件夹内的全部内容。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $agreed) {
                Text("我已确认以上 \(prompt.conflictingNames.count) 项的处理方式，并统一应用到本次全部 \(prompt.urls.count) 项传输")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            Divider()

            HStack(spacing: 8) {
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("跳过重名") { onResolve(.skip) }
                    .disabled(!agreed)
                Button("保留两者") { onResolve(.keepBoth) }
                    .disabled(!agreed)
                Button("覆盖") { onResolve(.replace) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!agreed)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
