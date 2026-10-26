import SwiftUI
import AppKit

/// 应用主界面：左侧磁盘列表，右侧错误提示 / 传输队列 / 日志 / 文件浏览
struct ContentView: View {
    @EnvironmentObject private var logs: LogStore
    @EnvironmentObject private var diskObserver: DiskObserver
    @EnvironmentObject private var browser: FileBrowserModel
    @EnvironmentObject private var transfer: TransferManager

    @EnvironmentObject private var environmentChecker: EnvironmentChecker
    @State private var selectedDisk: GenericDisk?
    @State private var dismissedEnvironmentWarning = false
    @State private var setupSkipped = false

    /// 环境未就绪时用配置向导替换主区域
    private var showSetupGuide: Bool {
        if isForceSetupGuideEnabled { return !setupSkipped }
        guard let report = environmentChecker.report else { return false }
        return !report.isReady && !setupSkipped
    }

    // MARK: - 临时调试开关
    // 强制显示配置向导，用于预览新手首次打开时的界面。
    // 推荐用法：执行项目根目录的 ./preview_setup.sh
    // 备选：先退出本 App，再在终端执行下面命令后重新打开
    //   defaults write ntfs.NTFS-- ForceSetupGuide -bool YES
    private var isForceSetupGuideEnabled: Bool {
        UserDefaults.standard.bool(forKey: "ForceSetupGuide")
            || ProcessInfo.processInfo.environment["NTFS_FORCE_SETUP"] == "1"
    }

    var body: some View {
        NavigationSplitView {
            DiskListView(diskObserver: diskObserver, selectedDisk: $selectedDisk)
        } detail: {
            VStack(spacing: 0) {
                // 配置向导显示时独占主区域，避免日志和传输面板分散新手注意力
                if !showSetupGuide {
                    environmentBanner
                    errorBanner

                    if !transfer.tasks.isEmpty {
                        TransferPanel(transfer: transfer)
                        Divider()
                    }

                    LogPanel(logs: logs)
                    Divider()
                }

                detailContent
            }
        }
        .onAppear {
            transfer.browser = browser
            NotificationService.shared.prepare()
            environmentChecker.check()
        }
        .onChange(of: selectedDisk) { _, newValue in
            guard let disk = newValue else { return }
            if disk.isHandled {
                browser.setRoot(disk.mountPath)
            } else {
                browser.clear()
            }
        }
        .onChange(of: diskObserver.disks) { _, newDisks in
            guard let current = selectedDisk,
                  let updated = newDisks.first(where: { $0.id == current.id }) else { return }
            if updated != current {
                selectedDisk = updated
            }
            // 磁盘刚被接管为读写模式时自动进入该卷
            if updated.isHandled, browser.rootPath != updated.mountPath {
                browser.setRoot(updated.mountPath)
            }
        }
    }

    /// 启动时检测依赖，缺失时提示安装，避免挂载失败后才发现
    @ViewBuilder
    private var environmentBanner: some View {
        if let report = environmentChecker.report,
           !report.issues.isEmpty,
           !dismissedEnvironmentWarning {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("运行环境不完整，NTFS 读写挂载会失败")
                        .font(.caption)
                        .bold()
                    ForEach(report.issues, id: \.self) { issue in
                        Text(issue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("复制安装命令") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("brew install --cask macfuse && brew install ntfs-3g-mac", forType: .string)
                }
                .controlSize(.small)

                Button {
                    dismissedEnvironmentWarning = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = logs.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button {
                    logs.lastError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.red.opacity(0.85))
            .transition(.move(edge: .top))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if showSetupGuide {
            SetupGuideView(onSkip: { setupSkipped = true },
                           previewReport: isForceSetupGuideEnabled ? EnvironmentReport() : nil)
        } else if let disk = selectedDisk {
            if disk.isHandled {
                FileBrowserView(browser: browser, transfer: transfer)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 52))
                        .foregroundColor(.secondary)
                    Text("\(disk.fsType) 磁盘当前为只读模式")
                        .font(.title3)
                    Text("接管后可获得完整读写权限，此操作需要管理员授权。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("接管为读写模式") {
                        diskObserver.mount(disk)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(diskObserver.isBusy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("请在左侧选择外部磁盘")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
