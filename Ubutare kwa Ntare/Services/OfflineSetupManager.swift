import Foundation

final class OfflineSetupManager {
    static let shared = OfflineSetupManager()

    private let osmProgressWeight = 10

    var isComplete: Bool {
        OfflineMapManager.shared.isFullOfflineSetupComplete()
            && AuthSessionManager.shared.isOfflineSetupComplete
    }

    func markComplete() {
        OfflineMapManager.shared.markStreetReady()
        OfflineMapManager.shared.markOfflineSetupComplete()
    }

    func performSetup(token: String, progress: @escaping (Int, String) -> Void) async -> Bool {
        OfflineMapManager.shared.clearStreetReadyIfIncomplete()
        OfflineMapManager.shared.clearOfflineSetupCompleteIfIncomplete()

        // Phase 1 — navigation OSM (~10%)
        if !OfflineNavigationHelper.shared.hasNavigationData() {
            guard NetworkMonitor.shared.isConnected else {
                if let partial = NavigationDataDownloader.currentDownloadPercent() {
                    progress(mapOsmProgress(partial), "Download paused at \(partial)%. Connect to the internet and tap Resume Download.")
                } else {
                    progress(0, "Connect to the internet to download navigation data.")
                }
                return false
            }

            let downloaded = await NavigationDataDownloader.downloadIfNeeded { filePercent in
                let label = NavigationDataDownloader.hasPartialDownload() && filePercent < 100
                    ? "Resuming download… \(filePercent)%"
                    : "Downloading navigation file… \(filePercent)%"
                progress(self.mapOsmProgress(filePercent), label)
            }

            guard downloaded else {
                progress(0, "Could not download navigation data. Check your connection and try again.")
                return false
            }

            OfflineNavigationHelper.shared.initialize()
            guard await OfflineNavigationHelper.shared.awaitReady() else {
                progress(0, "Offline navigation is still preparing. Please try again.")
                return false
            }
        } else {
            OfflineNavigationHelper.shared.initialize()
            guard await OfflineNavigationHelper.shared.awaitReady() else {
                progress(0, "Offline navigation is still preparing. Please try again.")
                return false
            }
            progress(mapOsmProgress(100), "Navigation file ready.")
        }

        // Phase 2 — street MBTiles (~90%)
        if !OfflineMapManager.shared.isStreetFullyDownloaded() {
            guard NetworkMonitor.shared.isConnected else {
                if let partial = MbTilesDownloader.currentDownloadPercent() {
                    progress(mapStreetProgress(partial), "Map download paused at \(partial)%. Connect to the internet and tap Resume Download.")
                } else if let partial = NavigationDataDownloader.currentDownloadPercent() {
                    progress(mapOsmProgress(partial), "Download paused. Connect to the internet and tap Resume Download.")
                } else {
                    progress(mapOsmProgress(100), "Connect to the internet to download the Burundi street map.")
                }
                return false
            }

            progress(mapStreetProgress(1), "Downloading Map files…")
            do {
                try await MbTilesDownloader.downloadStreetMap { streetPercent, status in
                    progress(self.mapStreetProgress(streetPercent), status)
                }
            } catch {
                if let partial = MbTilesDownloader.currentDownloadPercent() {
                    progress(mapStreetProgress(partial), error.localizedDescription)
                } else {
                    progress(mapOsmProgress(100), error.localizedDescription)
                }
                return false
            }
        } else {
            progress(mapStreetProgress(100), "Street map ready.")
        }

        guard OfflineMapManager.shared.isStreetFullyDownloaded() else {
            progress(mapStreetProgress(MbTilesDownloader.currentDownloadPercent() ?? 0), "Street map download is incomplete. Tap Resume Download to continue.")
            return false
        }

        OfflineMapManager.shared.writeOfflineStreetStyleFile()
        OfflineMapManager.shared.markStreetReady()

        progress(95, "Downloading mineral types…")
        await prefetchMineralTypes(token: token)

        guard OfflineNavigationHelper.shared.hasNavigationData() else {
            progress(0, "Navigation file not found. Please try again.")
            return false
        }

        progress(100, "Burundi map ready. Tap Continue to open the map.")
        markComplete()
        return true
    }

    private func mapOsmProgress(_ filePercent: Int) -> Int {
        filePercent.clamped(to: 0...100) * osmProgressWeight / 100
    }

    private func mapStreetProgress(_ streetPercent: Int) -> Int {
        let street = streetPercent.clamped(to: 0...100)
        let streetSpan = 100 - osmProgressWeight
        return osmProgressWeight + (street * streetSpan + 50) / 100
    }

    private func prefetchMineralTypes(token: String) async {
        if !LocalDataStore.shared.getMineralTypes().isEmpty {
            return
        }

        do {
            let response = try await APIClient.shared.getMineralTypes(token: token)
            if response.status, let types = response.result?.mineralTypes, !types.isEmpty {
                LocalDataStore.shared.saveMineralTypes(types)
            }
        } catch {
            #if DEBUG
            print("Mineral types prefetch failed (non-fatal): \(error)")
            #endif
        }
    }
}
