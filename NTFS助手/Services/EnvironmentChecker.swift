import Foundation
import Combine

/// 运行环境自检报告
struct EnvironmentReport {
    var homebrewPath: String?
    var ntfs3gPath: String?
    var ntfs3gVersion: String?
    var macFUSEPresent = false
    var sipEnabled = false
    var issues: [String] = []

    /// 能否正常挂载 NTFS 读写卷
    var isReady: Bool {
        ntfs3gPath != nil && macFUSEPresent
    }

    /// 已定位到 Homebrew 时用完整路径，避免 PATH 未配置导致 command not found
    private var brewCommand: String {
        homebrewPath ?? "brew"
    }

    /// 安装 macFUSE 的命令
    var installMacFUSECommand: String {
        "\(brewCommand) install --cask macfuse"
    }

    /// 安装 ntfs-3g 的命令
    var installNTFS3GCommand: String {
        "\(brewCommand) install ntfs-3g-mac"
    }

    /// 安装 Homebrew 的命令
    var installHomebrewCommand: String {
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    }
}

/// 检测 Homebrew / ntfs-3g / macFUSE / SIP 状态，并给出对应的安装命令
final class EnvironmentChecker: ObservableObject {
    @Published private(set) var report: EnvironmentReport?
    @Published private(set) var isChecking = false

    private let queue = DispatchQueue(label: "com.disk.envcheck", qos: .userInitiated)

    func check() {
        guard !isChecking else { return }
        isChecking = true
        queue.async { [weak self] in
            guard let self else { return }
            var report = EnvironmentReport()

            let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            report.homebrewPath = brewCandidates.first { FileManager.default.fileExists(atPath: $0) }

            let drivers = ["/usr/local/sbin/ntfs-3g", "/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"]
            report.ntfs3gPath = drivers.first { FileManager.default.fileExists(atPath: $0) }
            if let path = report.ntfs3gPath {
                report.ntfs3gVersion = Self.output(of: path, arguments: ["--version"])?
                    .components(separatedBy: .newlines).first
            }

            report.macFUSEPresent = FileManager.default.fileExists(atPath: "/Library/Filesystems/macfuse.fs")

            if let status = Self.output(of: "/usr/bin/csrutil", arguments: ["status"]) {
                report.sipEnabled = status.contains("enabled")
            }

            if !report.macFUSEPresent {
                report.issues.append("未安装 macFUSE")
            }
            if report.ntfs3gPath == nil {
                report.issues.append("未安装 ntfs-3g")
            }

            DispatchQueue.main.async {
                self.report = report
                self.isChecking = false
            }
        }
    }

    private static func output(of path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
