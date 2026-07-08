import Foundation

final class MineralsSyncService {
    static let shared = MineralsSyncService()

    func syncAll(token: String, latitude: Double, longitude: Double) async {
        var page = 1
        let limit = 100
        var allMinerals: [MineralsListItem] = []

        do {
            let typesResponse = try await APIClient.shared.getMineralTypes(token: token)
            if typesResponse.status, let types = typesResponse.result?.mineralTypes {
                LocalDataStore.shared.saveMineralTypes(types)
            }

            while true {
                let response = try await APIClient.shared.getMinerals(
                    token: token,
                    latitude: latitude,
                    longitude: longitude,
                    page: page,
                    limit: limit
                )
                guard response.status, let result = response.result else { break }
                allMinerals.append(contentsOf: result.minerals)
                if allMinerals.count >= result.total || result.minerals.isEmpty { break }
                page += 1
            }
            LocalDataStore.shared.saveMinerals(allMinerals)
            MineralImageLoader.prefetchImages(for: allMinerals)
        } catch {
            // Background sync; failures are non-fatal.
        }
    }
}
