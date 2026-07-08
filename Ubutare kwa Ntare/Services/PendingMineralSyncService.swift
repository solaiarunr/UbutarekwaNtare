import Foundation

final class PendingMineralSyncService {
    static let shared = PendingMineralSyncService()

    func syncPending(token: String) async {
        let pending = LocalDataStore.shared.getPendingSync()
        guard !pending.isEmpty else { return }

        var created: [BulkMineralCreateItem] = []
        var updated: [BulkMineralUpdateItem] = []
        var deleted: [BulkMineralDeleteItem] = []

        for item in pending {
            switch item.action {
            case .create:
                created.append(BulkMineralCreateItem(
                    localId: item.localId,
                    mineralTypeId: item.mineralTypeId,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    treasureType: item.treasureType,
                    sizeCubicMeters: item.sizeCubicMeters,
                    depthCm: item.depthCm,
                    addedBy: item.addedBy,
                    image: item.imagePath ?? ""
                ))
            case .update:
                if let serverId = item.serverId {
                    updated.append(BulkMineralUpdateItem(
                        id: serverId,
                        localId: item.localId,
                        mineralTypeId: item.mineralTypeId,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        treasureType: item.treasureType,
                        sizeCubicMeters: item.sizeCubicMeters,
                        depthCm: item.depthCm,
                        addedBy: item.addedBy,
                        image: item.imagePath
                    ))
                }
            case .delete:
                if let serverId = item.serverId {
                    deleted.append(BulkMineralDeleteItem(id: serverId, localId: item.localId))
                }
            }
        }

        do {
            let response = try await APIClient.shared.bulkMineralSync(
                token: token,
                request: BulkMineralSyncRequest(created: created, updated: updated, deleted: deleted)
            )
            if response.status {
                LocalDataStore.shared.savePendingSync([])
            }
        } catch {
            // Will retry on next launch.
        }
    }
}
