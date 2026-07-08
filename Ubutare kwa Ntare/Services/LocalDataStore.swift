import Foundation

final class LocalDataStore {
    static let shared = LocalDataStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let minerals = "cached_minerals"
        static let mineralTypes = "cached_mineral_types"
        static let users = "cached_users"
        static let notifications = "cached_notifications"
        static let settings = "cached_settings"
        static let roles = "cached_roles"
        static let pendingSync = "pending_mineral_sync"
        static let oneSignalAppId = "onesignal_app_id"
    }

    func saveMinerals(_ minerals: [MineralsListItem]) {
        save(minerals, key: Keys.minerals)
    }

    func getMinerals() -> [MineralsListItem] {
        load(key: Keys.minerals) ?? []
    }

    func saveMineralTypes(_ types: [MineralType]) {
        save(types, key: Keys.mineralTypes)
    }

    func getMineralTypes() -> [MineralType] {
        load(key: Keys.mineralTypes) ?? []
    }

    func saveUsers(_ users: [AuthUser]) {
        save(users, key: Keys.users)
    }

    func getUsers() -> [AuthUser] {
        load(key: Keys.users) ?? []
    }

    func saveNotifications(_ notifications: [AppNotification]) {
        save(notifications, key: Keys.notifications)
    }

    func getNotifications() -> [AppNotification] {
        load(key: Keys.notifications) ?? []
    }

    func saveSettings(_ settings: AppSettings) {
        save(settings, key: Keys.settings)
        save(settings.roles, key: Keys.roles)
        if let appId = settings.oneSignalAppId {
            defaults.set(appId, forKey: Keys.oneSignalAppId)
        }
    }

    func getSettings() -> AppSettings? {
        load(key: Keys.settings)
    }

    func getRoles() -> [RoleSetting] {
        load(key: Keys.roles) ?? []
    }

    func getOneSignalAppId() -> String? {
        defaults.string(forKey: Keys.oneSignalAppId)
    }

    func savePendingSync(_ items: [PendingMineralSync]) {
        save(items, key: Keys.pendingSync)
    }

    func getPendingSync() -> [PendingMineralSync] {
        load(key: Keys.pendingSync) ?? []
    }

    func addPendingSync(_ item: PendingMineralSync) {
        var items = getPendingSync()
        items.append(item)
        savePendingSync(items)
    }

    func removePendingSync(localId: String) {
        var items = getPendingSync()
        items.removeAll { $0.localId == localId }
        savePendingSync(items)
    }

    func clearAll() {
        [Keys.minerals, Keys.mineralTypes, Keys.users, Keys.notifications, Keys.settings, Keys.roles, Keys.pendingSync, Keys.oneSignalAppId].forEach {
            defaults.removeObject(forKey: $0)
        }
        AuthSessionManager.shared.isOfflineSetupComplete = false
        try? FileManager.default.removeItem(at: pendingImagesDirectory())
    }

    func pendingImagesDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_mineral_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
