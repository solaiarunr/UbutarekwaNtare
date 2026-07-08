import Foundation

final class SettingsSyncService {
    static let shared = SettingsSyncService()

    func fetchAndSave(token: String) async {
        do {
            let response = try await APIClient.shared.getSettings(token: token)
            if response.status, let settings = response.result {
                LocalDataStore.shared.saveSettings(settings)
                if let appId = settings.oneSignalAppId {
                    OneSignalService.shared.configure(appId: appId)
                }
            }
        } catch {
            // Settings sync is best-effort at login.
        }
    }
}
