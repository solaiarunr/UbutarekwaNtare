import Foundation
import UIKit

/// Background satellite MBTiles download (Android `SatelliteDownloadService`).
final class SatelliteDownloadManager {
    static let shared = SatelliteDownloadManager()

    private var downloadTask: Task<Void, Never>?
    private(set) var currentPercent = 0
    private(set) var currentStatus = ""
    private(set) var currentProgressInfo: MapDownloadProgressInfo?

    private let progressPercentKey = "satellite_download_progress_percent"
    private let progressStatusKey = "satellite_download_progress_status"
    private let pendingCompleteToastKey = "satellite_download_pending_toast"

    private init() {}

    var isDownloading: Bool {
        OfflineMapManager.shared.isSatelliteDownloading
    }

    var hasPendingCompleteToast: Bool {
        UserDefaults.standard.bool(forKey: pendingCompleteToastKey)
    }

    func consumePendingCompleteToast() -> Bool {
        guard hasPendingCompleteToast else { return false }
        UserDefaults.standard.set(false, forKey: pendingCompleteToastKey)
        return true
    }

    func resumeIfNeeded() {
        if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            if OfflineMapManager.shared.isSatelliteDownloading {
                finalizeCompletedDownload(notifyUI: true)
            }
            return
        }

        guard shouldResumeDownload() else { return }

        if !OfflineMapManager.shared.isSatelliteDownloading {
            OfflineMapManager.shared.isSatelliteDownloading = true
        }

        let restored = restoredProgress()
        currentPercent = restored.percent
        currentStatus = restored.status
        postProgress(restored.percent, restored.status)
        start()
    }

    func startIfNeeded() {
        guard !OfflineMapManager.shared.isSatelliteFullyDownloaded() else { return }
        guard !isDownloading else { return }
        OfflineMapManager.shared.isSatelliteDownloading = true
        start()
    }

    func start() {
        guard downloadTask == nil else { return }
        if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            finalizeCompletedDownload(notifyUI: true)
            return
        }

        MapDownloadNotificationService.shared.requestPermissionIfNeeded()
        OfflineMapManager.shared.isSatelliteDownloading = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SatelliteDownload")

        downloadTask = Task {
            await performDownloadLoop()
            OfflineMapManager.shared.isSatelliteDownloading = false
            downloadTask = nil
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        OfflineMapManager.shared.isSatelliteDownloading = false
        MapDownloadNotificationService.shared.clearSatellite()
        NotificationCenter.default.post(name: .satelliteDownloadStopped, object: nil)
    }

    func restoredProgress() -> (percent: Int, status: String) {
        let filePercent = MbTilesDownloader.currentSatelliteDownloadPercent() ?? 0
        let savedPercent = UserDefaults.standard.integer(forKey: progressPercentKey)
        let percent = max(filePercent, savedPercent, currentPercent).clamped(to: 0...99)

        if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            return (100, "Satellite map ready.")
        }

        let savedStatus = UserDefaults.standard.string(forKey: progressStatusKey)
        let status = [savedStatus, currentStatus]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Downloading satellite map…"

        return (percent > 0 ? percent : 1, status)
    }

    func restoredProgressInfo() -> MapDownloadProgressInfo {
        if let info = currentProgressInfo {
            return info
        }
        let restored = restoredProgress()
        let total = 37881
        let saved = Int(Double(total) * Double(restored.percent) / 100.0)
        return MapDownloadProgressInfo(
            percent: restored.percent,
            status: restored.status,
            zoom: 13,
            totalSaved: saved,
            totalTarget: total,
            thisZoomSaved: 0,
            thisZoomTotal: 0,
            fileName: "burundi_satellite.mbtiles"
        )
    }

    // MARK: - Private

    private func shouldResumeDownload() -> Bool {
        OfflineMapManager.shared.isSatelliteDownloading
            || MbTilesDownloader.hasPartialSatelliteDownload()
    }

    private func performDownloadLoop() async {
        if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            finalizeCompletedDownload(notifyUI: true)
            return
        }

        let restored = restoredProgress()
        postProgress(restored.percent, restored.status)

        var idlePasses = 0
        let satelliteFile = OfflineMapManager.shared.satelliteMbTilesURL()

        while !OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            if Task.isCancelled { return }

            if !NetworkMonitor.shared.isConnected {
                postProgress(currentPercent, "Waiting for internet…")
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                idlePasses += 1
                if idlePasses >= 40 {
                    postFailed("No internet connection. Connect to Wi‑Fi or mobile data, then try Hybrid again.")
                    return
                }
                continue
            }

            idlePasses = 0
            let tilesBefore = MbTilesDownloader.countTiles(in: satelliteFile)
            do {
                try await MbTilesDownloader.downloadSatelliteMap { [weak self] info in
                    self?.postProgress(info)
                }
            } catch {
                if !NetworkMonitor.shared.isConnected {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    continue
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }

            OfflineMapManager.shared.writeOfflineHybridStyleFile()
            OfflineMapManager.shared.checkpointSatelliteMbTiles()
            let tilesAfter = MbTilesDownloader.countTiles(in: satelliteFile)
            if tilesAfter <= tilesBefore {
                idlePasses += 1
                let delay: UInt64 = idlePasses > 3 ? 30_000_000_000 : 5_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            } else {
                idlePasses = 0
            }

            if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
                break
            }
        }

        finalizeCompletedDownload(notifyUI: true)
    }

    private func finalizeCompletedDownload(notifyUI: Bool) {
        OfflineMapManager.shared.writeOfflineHybridStyleFile()
        OfflineMapManager.shared.markSatelliteReady()
        OfflineMapManager.shared.checkpointSatelliteMbTiles()
        OfflineMapManager.shared.isSatelliteDownloading = false
        clearPersistedProgress()
        UserDefaults.standard.set(true, forKey: pendingCompleteToastKey)

        if notifyUI {
            postComplete()
        }
    }

    private func postProgress(_ percent: Int, _ status: String) {
        let clamped = percent.clamped(to: 0...100)
        currentPercent = clamped
        currentStatus = status
        
        let total = 37881
        let saved = Int(Double(total) * Double(clamped) / 100.0)
        let info = MapDownloadProgressInfo(
            percent: clamped,
            status: status,
            zoom: 13,
            totalSaved: saved,
            totalTarget: total,
            thisZoomSaved: 0,
            thisZoomTotal: 0,
            fileName: "burundi_satellite.mbtiles"
        )
        currentProgressInfo = info
        
        UserDefaults.standard.set(clamped, forKey: progressPercentKey)
        UserDefaults.standard.set(status, forKey: progressStatusKey)
        NotificationCenter.default.post(
            name: .satelliteDownloadProgress,
            object: nil,
            userInfo: ["percent": clamped, "status": status, "progressInfo": info]
        )
        MapDownloadNotificationService.shared.updateSatelliteProgress(percent: clamped, message: status)
    }

    private func postProgress(_ info: MapDownloadProgressInfo) {
        currentProgressInfo = info
        currentPercent = info.percent
        currentStatus = info.status
        UserDefaults.standard.set(info.percent, forKey: progressPercentKey)
        UserDefaults.standard.set(info.status, forKey: progressStatusKey)
        NotificationCenter.default.post(
            name: .satelliteDownloadProgress,
            object: nil,
            userInfo: ["percent": info.percent, "status": info.status, "progressInfo": info]
        )
        MapDownloadNotificationService.shared.updateSatelliteProgress(percent: info.percent, message: info.status)
    }

    private func postComplete() {
        postProgress(100, "Satellite map ready.")
        MapDownloadNotificationService.shared.showSatelliteComplete()
        NotificationCenter.default.post(name: .satelliteDownloadComplete, object: nil)
    }

    private func postFailed(_ message: String) {
        OfflineMapManager.shared.isSatelliteDownloading = false
        MapDownloadNotificationService.shared.showSatelliteFailed(message)
        NotificationCenter.default.post(
            name: .satelliteDownloadFailed,
            object: nil,
            userInfo: ["error": message]
        )
    }

    private func clearPersistedProgress() {
        UserDefaults.standard.removeObject(forKey: progressPercentKey)
        UserDefaults.standard.removeObject(forKey: progressStatusKey)
    }
}
