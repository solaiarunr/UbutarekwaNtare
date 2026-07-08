import Foundation
import UIKit

/// Resumes offline setup when the app relaunches (Android `OfflineSetupDownloadService.resumeIfNeeded`).
final class OfflineSetupDownloadManager {
    static let shared = OfflineSetupDownloadManager()

    private var downloadTask: Task<Void, Never>?

    private init() {}

    func resumeIfNeeded() {
        guard AuthSessionManager.shared.isLoggedIn else { return }
        guard !OfflineMapManager.shared.isFullOfflineSetupComplete() else { return }
        guard downloadTask == nil else { return }

        MapDownloadNotificationService.shared.requestPermissionIfNeeded()
        OfflineMapManager.shared.isOfflineSetupDownloading = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "OfflineSetupDownload")

        downloadTask = Task {
            await performDownloadLoop()
            OfflineMapManager.shared.isOfflineSetupDownloading = false
            downloadTask = nil
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        OfflineMapManager.shared.isOfflineSetupDownloading = false
        MapDownloadNotificationService.shared.clearSetup()
    }

    private func performDownloadLoop() async {
        guard let token = AuthSessionManager.shared.token else { return }

        while !OfflineMapManager.shared.isFullOfflineSetupComplete() {
            if Task.isCancelled { return }

            OfflineMapManager.shared.clearStreetReadyIfIncomplete()

            if !NetworkMonitor.shared.isConnected {
                postProgress(
                    currentPartialPercent(),
                    "No internet — download paused."
                )
                try? await waitForNetwork()
                postProgress(currentPartialPercent(), "Resuming download…")
                continue
            }

            let success = await OfflineSetupManager.shared.performSetup(token: token) { percent, status in
                self.postProgress(percent, status)
            }

            if success {
                postProgress(100, "Burundi map ready.")
                MapDownloadNotificationService.shared.showSetupComplete()
                NotificationCenter.default.post(name: .offlineSetupDownloadProgress, object: nil, userInfo: [
                    "percent": 100,
                    "status": "Burundi map ready.",
                    "complete": true
                ])
                return
            }

            if OfflineMapManager.shared.isFullOfflineSetupComplete() {
                return
            }

            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func waitForNetwork() async throws {
        while !NetworkMonitor.shared.isConnected {
            if Task.isCancelled { return }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func currentPartialPercent() -> Int {
        if let street = MbTilesDownloader.currentDownloadPercent(),
           !OfflineMapManager.shared.isStreetFullyDownloaded() {
            return 10 + (street * 90 + 50) / 100
        }
        if let nav = NavigationDataDownloader.currentDownloadPercent(),
           !OfflineNavigationHelper.shared.hasNavigationData() {
            return nav * 10 / 100
        }
        return 0
    }

    private func postProgress(_ percent: Int, _ status: String) {
        NotificationCenter.default.post(
            name: .offlineSetupDownloadProgress,
            object: nil,
            userInfo: ["percent": percent, "status": status, "complete": false]
        )
        MapDownloadNotificationService.shared.updateSetupProgress(percent: percent, message: status)
    }
}
