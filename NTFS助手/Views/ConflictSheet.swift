import SwiftUI

/// 同名冲突确认面板：统一策略 + 单项微调，全部确认后才能开始
struct ConflictSheet: View {
    let prompt: TransferManager.ConflictPrompt
    let onConfirm: (ConflictPolicy, [String: ConflictPolicy]) -> Void
    let onCancel: () -> Void

    @State private var agreed = false
    @State private var defaultPolicy: ConflictPolicy = .keepBoth
    /// 仅记录与统一策略不同的项
    @State private var overrides: [String: ConflictPolicy] = [:]

    private let allPolicies: [ConflictPolicy] = [.replace, .keepBoth, .skip]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            defaultPicker
            conflictList
            folderWarning
            agreement
            Divider()
            actions
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("目标位置已存在同名项")
                .font(.title3)
                .bold()
        }
    }

    private var defaultPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("统一处理方式")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $defaultPolicy) {
                ForEach(allPolicies, id: \.self) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("下列 \(prompt.conflictingNames.count) 项默认使用此方式，可在右侧单独调整。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var conflictList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(prompt.conflictingNames, id: \.self) { name in
                    row(for: name)
                    if name != prompt.conflictingNames.last {
                        Divider()
                    }
                }
            }
        }
        .frame(height: min(CGFloat(prompt.conflictingNames.count) * 30 + 8, 190))
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func row(for name: String) -> some View {
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

            Menu {
                Button("跟随统一设置") { overrides.removeValue(forKey: name) }
                Divider()
                ForEach(allPolicies, id: \.self) { policy in
                    Button(policy.title) { overrides[name] = policy }
                }
            } label: {
                Text(overrides[name]?.title ?? "跟随统一")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 76)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var folderWarning: some View {
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
    }

    private var agreement: some View {
        Toggle(isOn: $agreed) {
            Text("我已确认以上 \(prompt.conflictingNames.count) 项的处理方式，本次共传输 \(prompt.urls.count) 项")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("取消") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("开始传输") { onConfirm(defaultPolicy, overrides) }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
        }
    }
}
