import SwiftUI
import ServiceManagement

/// 设置页：环境自检结果与开机自启
struct SettingsView: View {
    @EnvironmentObject private var checker: EnvironmentChecker
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("运行环境") {
                if let report = checker.report {
                    LabeledContent("Homebrew") {
                        Text(report.homebrewPath ?? "未安装")
                            .foregroundColor(report.homebrewPath == nil ? .red : .secondary)
                    }
                    LabeledContent("ntfs-3g") {
                        Text(report.ntfs3gVersion ?? "未安装")
                            .foregroundColor(report.ntfs3gPath == nil ? .red : .secondary)
                    }
                    LabeledContent("macFUSE") {
                        Text(report.macFUSEPresent ? "已安装" : "未安装")
                            .foregroundColor(report.macFUSEPresent ? .secondary : .red)
                    }
                    LabeledContent("SIP") {
                        Text(report.sipEnabled ? "已启用" : "已关闭")
                            .foregroundColor(.secondary)
                    }
                    ForEach(report.issues, id: \.self) { issue in
                        Text("\(issue)，请打开主窗口按向导安装")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("检测中…").font(.caption).foregroundColor(.secondary)
                    }
                }
                Button("重新检测") { checker.check() }
                    .disabled(checker.isChecking)
            }

            Section("启动") {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        applyLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 340)
        .onAppear { checker.check() }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册失败时回滚开关状态，避免界面与实际不一致
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
