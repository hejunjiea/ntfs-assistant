import SwiftUI

/// 操作日志面板
struct LogPanel: View {
    @ObservedObject var logs: LogStore
    var height: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").font(.caption)
                Text("操作日志").font(.caption).bold()
                Spacer()
                Button {
                    logs.clear()
                } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("清空日志")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.entries.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(color(for: entry))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .frame(height: height)
                .background(Color.black.opacity(0.05))
                .onChange(of: logs.entries) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue.count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private func color(for entry: String) -> Color {
        if entry.contains("❌") { return .red }
        if entry.contains("✅") { return .green }
        if entry.contains("⏹") { return .orange }
        return .primary
    }
}
