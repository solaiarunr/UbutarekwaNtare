import Foundation
import UIKit

final class AuthSessionManager {
    static let shared = AuthSessionManager()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let token = "auth_token"
        static let userId = "auth_user_id"
        static let phone = "auth_phone"
        static let displayName = "auth_display_name"
        static let role = "auth_role"
        static let isActive = "auth_is_active"
        static let offlineSetupComplete = "offline_setup_complete"
    }

    var currentRole: UserRole? { UserRole.from(defaults.string(forKey: Keys.role)) }

    var isLoggedIn: Bool {
        guard let token = defaults.string(forKey: Keys.token) else { return false }
        return !token.isEmpty
    }

    var token: String? { defaults.string(forKey: Keys.token) }
    var userId: String? { defaults.string(forKey: Keys.userId) }
    var phone: String? { defaults.string(forKey: Keys.phone) }
    var displayName: String? { defaults.string(forKey: Keys.displayName) }
    var role: String? { defaults.string(forKey: Keys.role) }

    var isOfflineSetupComplete: Bool {
        get { defaults.bool(forKey: Keys.offlineSetupComplete) }
        set { defaults.set(newValue, forKey: Keys.offlineSetupComplete) }
    }

    func saveSession(token: String, user: AuthUser) {
        defaults.set(token, forKey: Keys.token)
        defaults.set(user.id, forKey: Keys.userId)
        defaults.set(user.phone, forKey: Keys.phone)
        defaults.set(user.displayName, forKey: Keys.displayName)
        defaults.set(user.role, forKey: Keys.role)
        defaults.set(user.isActive, forKey: Keys.isActive)
    }

    func clearSession() {
        [Keys.token, Keys.userId, Keys.phone, Keys.displayName, Keys.role].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.removeObject(forKey: Keys.isActive)
        LocalDataStore.shared.clearAll()
    }

    func deviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}
