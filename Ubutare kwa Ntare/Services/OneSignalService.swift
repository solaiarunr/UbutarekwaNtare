import OneSignalFramework
import UIKit

final class OneSignalService {
    static let shared = OneSignalService()

    private(set) var deviceToken: String = ""

    func configure(appId: String?) {
        guard let appId, !appId.isEmpty else { return }
        OneSignal.initialize(appId, withLaunchOptions: nil)
        OneSignal.Notifications.requestPermission({ [weak self] accepted in
            if accepted {
                self?.refreshDeviceToken()
            }
        }, fallbackToSettings: true)
        refreshDeviceToken()
    }

    func configureFromCache() {
        if let appId = LocalDataStore.shared.getOneSignalAppId() {
            configure(appId: appId)
        }
    }

    func requestPermission() {
        OneSignal.Notifications.requestPermission({ [weak self] _ in
            self?.refreshDeviceToken()
        }, fallbackToSettings: true)
    }

    func refreshDeviceToken() {
        deviceToken = OneSignal.User.pushSubscription.id ?? ""
    }
}
