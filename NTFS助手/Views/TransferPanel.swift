import SwiftUI

/// 传输队列面板：显示多项任务进度、速度、剩余时间，支持取消
struct TransferPanel: View {
    @ObservedObject var transfer: TransferManager
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(transfer.tasks) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color.blue.opacity(0.08))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: transfer.isActive ? "arrow.up.arrow.down.circle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(transfer.isActive ? .blue : .green)
            Text(transfer.isActive ? "正在传输" : "传输队列").font(.caption).bold()
            if !transfer.progressSummary.isEmpty {
                Text(transfer.progressSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if transfer.tasks.contains(where: { $0.state == .running }) {
                Button("全部取消") { transfer.cancelAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if transfer.tasks.contains(where: { $0.isFinished }) {
                Button("清理已完成") { transfer.clearFinished() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func taskRow(_ task: TransferTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: task))
                    .font(.system(size: 10))
                    .foregroundColor(tint(for: task))
                Text(task.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer()
                Text(statusText(for: task))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(tint(for: task))
                if !task.isFinished {
                    Button {
                        transfer.cancel(task.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消此任务")
                }
            }

            ProgressView(value: task.state == .completed ? 1 : max(task.progress, 0.001), total: 1)
                .progressViewStyle(.linear)
                .tint(tint(for: task))
                .controlSize(.small)

            HStack(spacing: 10) {
                Text(task.sizeText)
                if task.state == .running {
                    Text(task.speedText)
                    Text(task.etaText)
                }
                if let message = task.message {
                    Text(message).foregroundColor(.secondary)
                }
                Spacer()
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
        }
    }

    private func icon(for task: TransferTask) -> String {
        switch task.state {
        case .pending: return "clock"
        case .running: return "arrow.up.arrow.down"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private func tint(for task: TransferTask) -> Color {
        switch task.state {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private func statusText(for task: TransferTask) -> String {
        switch task.state {
        case .pending: return "等待中"
        case .running: return "\(Int(task.progress * 100))%"
        case .completed: return "完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
