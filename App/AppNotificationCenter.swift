import Foundation
import SmoovLog
@preconcurrency import UserNotifications
import WorkspaceSidebar
import WorkspaceState

final class AppNotificationCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  static let shared = AppNotificationCenter()

  private let center = UNUserNotificationCenter.current()
  private var didRequestAuthorization = false
  @MainActor var onNotificationResponse: ((NotificationFocusRoute) -> Void)?

  func configure() {
    center.delegate = self
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "unknown"
    let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "unknown"
    SmoovLog.info("notifications configuring bundleId=\(bundleId) displayName=\(displayName) bundleName=\(bundleName)")
    requestAuthorizationIfNeeded()
  }

  func post(_ notification: TerminalNotification, route: NotificationFocusRoute? = nil) {
    SmoovLog.info("notification requested title=\(notification.title) body=\(notification.body)")
    requestAuthorizationIfNeeded { [weak self] granted in
      guard granted else {
        SmoovLog.warn("notification skipped because authorization is not granted")
        return
      }
      guard let self else { return }
      let content = UNMutableNotificationContent()
      content.title = notification.title
      content.body = notification.body
      content.sound = .default
      if let route {
        content.userInfo = route.userInfo
      }
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request) { error in
        if let error {
          SmoovLog.error("notification delivery failed: \(error)")
        } else {
          SmoovLog.info("notification delivered to notification center")
        }
      }
    }
  }

  private func requestAuthorizationIfNeeded(completion: (@Sendable (Bool) -> Void)? = nil) {
    if didRequestAuthorization {
      center.getNotificationSettings { settings in
        SmoovLog.info("notification settings status=\(Self.statusName(settings.authorizationStatus))")
        completion?(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
      }
      return
    }

    didRequestAuthorization = true
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error {
        SmoovLog.error("notification authorization request failed: \(error)")
      } else {
        SmoovLog.info("notification authorization request completed granted=\(granted)")
      }
      completion?(granted)
    }
  }

  private static func statusName(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    case .provisional:
      return "provisional"
    case .ephemeral:
      return "ephemeral"
    @unknown default:
      return "unknown"
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    Task { @MainActor [weak self] in
      if let route = NotificationFocusRoute(userInfo: userInfo) {
        self?.onNotificationResponse?(route)
      } else {
        SmoovLog.warn("notification response missing focus route")
      }
    }
    completionHandler()
  }
}
