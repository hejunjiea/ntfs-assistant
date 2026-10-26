import Foundation
import UserNotifications

/// 系统通知封装：挂载完成、传输结束等关键节点提示
final class NotificationService {
    static let shared = NotificationService()

    private var authorized = false
    private var didRequest = false

    /// 首次使用时申请通知权限
    func prepare() {
        guard !didRequest, Bundle.main.bundleIdentifier != nil else { return }
        didRequest = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notify(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
