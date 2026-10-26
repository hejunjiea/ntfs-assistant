import SwiftUI
import AppKit

/// 首次使用配置向导：检测环境、给出命令、引导新手完成安装
struct SetupGuideView: View {
    @EnvironmentObject private var checker: EnvironmentChecker
    var onSkip: () -> Void = {}
    /// 调试用：传入伪造报告，可预览“全部未安装”时的页面样子
    var previewReport: EnvironmentReport?

    @State private var copiedCommand: String?

    private var report: EnvironmentReport? { previewReport ?? checker.report }

    var body: some View {
        VStack(spacing: 0) {
            // 上半部分可滚动，底部操作栏固定，保证“重新检测”始终可见
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    readyNotice

                    step1Homebrew
                    step2MacFUSE
                    step3NTFS3G
                    step4Restart
                }
                .padding(24)
                .frame(maxWidth: 720)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.orange)
                Text("首次使用：配置运行环境")
                    .font(.title2)
                    .bold()
            }

            Text("NTFS助手需要两个免费组件才能读写 NTFS 磁盘。按下面 4 步操作，大约 10 分钟，只需配置一次。")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                statusPill("Homebrew", done: report?.homebrewPath != nil)
                statusPill("macFUSE", done: report?.macFUSEPresent == true)
                statusPill("ntfs-3g", done: report?.ntfs3gPath != nil)
            }
        }
    }

    @ViewBuilder
    private var readyNotice: some View {
        if report?.isReady == true {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                Text("环境已就绪，可以开始挂载磁盘了")
                    .font(.callout)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12))
            .cornerRadius(8)
        }
    }

    private func statusPill(_ title: String, done: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(done ? .green : .secondary)
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - 步骤

    private var step1Homebrew: some View {
        stepCard(
            index: 1,
            title: "安装 Homebrew",
            done: report?.homebrewPath != nil,
            lines: [
                "Homebrew 是 macOS 的软件包管理器，用来安装下面两个组件。",
                "如果显示「已完成」，说明已经装过，直接跳到第 2 步。"
            ],
            command: report?.installHomebrewCommand,
            note: "安装时会要求输入开机密码，输入过程中屏幕不显示字符，这是正常现象。安装完成后终端会提示还需要执行两条命令，照着复制粘贴即可。"
        )
    }

    private var step2MacFUSE: some View {
        stepCard(
            index: 2,
            title: "安装 macFUSE",
            done: report?.macFUSEPresent,
            lines: macFUSELines,
            command: report?.installMacFUSECommand,
            note: "装完必须重启电脑，驱动才会生效。"
        )
    }

    private var macFUSELines: [String] {
        var lines = [
            "macFUSE 让 macOS 能加载第三方文件系统驱动。",
            "安装过程中会弹出系统扩展授权窗口，请点击「允许」。"
        ]
        if report?.homebrewPath == nil {
            lines.append("请先完成第 1 步安装 Homebrew，否则下面的命令无法执行。")
        }
        return lines
    }

    private var step3NTFS3G: some View {
        stepCard(
            index: 3,
            title: "安装 ntfs-3g",
            done: report?.ntfs3gPath != nil,
            lines: ntfs3gLines,
            command: report?.installNTFS3GCommand,
            note: "如果终端提示需要重启，请重启后再回到本软件。"
        )
    }

    private var ntfs3gLines: [String] {
        var lines = [
            "ntfs-3g 是真正负责读写 NTFS 的驱动。",
            "建议等第 2 步重启完成后再执行这一步。"
        ]
        if report?.homebrewPath == nil {
            lines.append("请先完成第 1 步安装 Homebrew，否则下面的命令无法执行。")
        }
        return lines
    }

    private var step4Restart: some View {
        stepCard(
            index: 4,
            title: "重启并确认授权",
            done: nil,
            lines: [
                "重启电脑。",
                "打开「系统设置 → 通用 → 登录项与扩展」，确认 macFUSE 处于已允许状态。",
                "回到本软件，点击下方「重新检测」，三项都变绿即可开始使用。"
            ],
            command: nil,
            note: "Apple 芯片的 Mac 如果提示需要在恢复模式中降低安全性，按系统窗口里的指引操作即可，不影响其他功能。"
        )
    }

    @ViewBuilder
    private func stepCard(index: Int,
                          title: String,
                          done: Bool?,
                          lines: [String],
                          command: String?,
                          note: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(done == true ? Color.green : Color.accentColor)
                        .frame(width: 22, height: 22)
                    if done == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Text(title).font(.headline)
                Spacer()
                if done == true {
                    Text("已完成")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let command, done != true {
                commandBox(command)
            }

            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
    }

    private func commandBox(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
                copiedCommand = command
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedCommand == command { copiedCommand = nil }
                }
            } label: {
                Label(copiedCommand == command ? "已复制" : "复制",
                      systemImage: copiedCommand == command ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.black.opacity(0.07))
        .cornerRadius(7)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    checker.check()
                } label: {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(checker.isChecking)

                if checker.isChecking {
                    ProgressView().controlSize(.small)
                }

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                } label: {
                    Label("打开终端", systemImage: "terminal")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("稍后配置") { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }

            Text("提示：复制命令后切换到终端窗口，粘贴并回车即可执行。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
