import SwiftUI

@main
struct NTFS助手App: App {
    @StateObject private var logs: LogStore
    @StateObject private var diskObserver: DiskObserver
    @StateObject private var browser: FileBrowserModel
    @StateObject private var transfer: TransferManager
    @StateObject private var environmentChecker: EnvironmentChecker

    init() {
        // 各模块共享同一个日志实例，保证日志顺序一致
        let logStore = LogStore()
        _logs = StateObject(wrappedValue: logStore)
        _diskObserver = StateObject(wrappedValue: DiskObserver(logStore: logStore))
        _browser = StateObject(wrappedValue: FileBrowserModel(logStore: logStore))
        _transfer = StateObject(wrappedValue: TransferManager(logStore: logStore))
        _environmentChecker = StateObject(wrappedValue: EnvironmentChecker())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(logs)
                .environmentObject(diskObserver)
                .environmentObject(browser)
                .environmentObject(transfer)
                .environmentObject(environmentChecker)
                .frame(minWidth: 900, minHeight: 620)
        }

        MenuBarExtra("NTFS助手", systemImage: "externaldrive.fill") {
            MenuBarContent()
                .environmentObject(diskObserver)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(environmentChecker)
        }
    }
}
