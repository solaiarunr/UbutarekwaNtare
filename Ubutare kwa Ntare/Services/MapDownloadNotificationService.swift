import Foundation
import UIKit
import UserNotifications

/// Android `SatelliteDownloadNotification` / `OfflineSetupDownloadNotification` parity.
final class MapDownloadNotificationService: NSObject {
    static let shared = MapDownloadNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let satelliteIdentifier = "burundi_satellite_map_download"
    private let setupIdentifier = "burundi_offline_setup_download"
    private let threadIdentifier = "map_downloads"

    private var satelliteLastPercent = -1
    private var satelliteLastUpdate = Date.distantPast
    private var setupLastPercent = -1
    private var setupLastUpdate = Date.distantPast

    private let minUpdateInterval: TimeInterval = 2.0
    private let minPercentStep = 2

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        requestPermissionIfNeeded()
    }

    func requestPermissionIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Satellite

    func updateSatelliteProgress(percent: Int, message: String) {
        let clamped = percent.clamped(to: 0...100)
        guard shouldPostSatellite(percent: clamped) else { return }
        post(
            identifier: satelliteIdentifier,
            title: "Burundi satellite map",
            body: progressBody(message: message, percent: clamped),
            sound: nil,
            ongoing: clamped < 100
        )
    }

    func showSatelliteComplete() {
        resetSatelliteThrottle()
        post(
            identifier: satelliteIdentifier,
            title: "Burundi satellite map",
            body: AppConstants.MapStyleMessages.satelliteDownloadComplete,
            sound: .default,
            ongoing: false
        )
    }

    func showSatelliteFailed(_ error: String) {
        resetSatelliteThrottle()
        let body = error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Satellite map download failed"
            : error
        post(
            identifier: satelliteIdentifier,
            title: "Burundi satellite map",
            body: body,
            sound: .default,
            ongoing: false
        )
    }

    func clearSatellite() {
        center.removeDeliveredNotifications(withIdentifiers: [satelliteIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [satelliteIdentifier])
        resetSatelliteThrottle()
    }

    // MARK: - Offline setup

    func updateSetupProgress(percent: Int, message: String) {
        let clamped = percent.clamped(to: 0...100)
        guard shouldPostSetup(percent: clamped) else { return }
        post(
            identifier: setupIdentifier,
            title: "Burundi offline map",
            body: progressBody(message: message, percent: clamped),
            sound: nil,
            ongoing: clamped < 100
        )
    }

    func showSetupComplete() {
        resetSetupThrottle()
        post(
            identifier: setupIdentifier,
            title: "Burundi offline map",
            body: "Burundi map ready.",
            sound: .default,
            ongoing: false
        )
    }

    func showSetupFailed(_ error: String) {
        resetSetupThrottle()
        let body = error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Map download failed"
            : error
        post(
            identifier: setupIdentifier,
            title: "Burundi offline map",
            body: body,
            sound: .default,
            ongoing: false
        )
    }

    func clearSetup() {
        center.removeDeliveredNotifications(withIdentifiers: [setupIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [setupIdentifier])
        resetSetupThrottle()
    }

    // MARK: - Private

    private func progressBody(message: String, percent: Int) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard percent < 100 else { return trimmed.isEmpty ? "Download complete." : trimmed }
        if trimmed.isEmpty {
            return "Downloading… \(percent)%"
        }
        if trimmed.contains("%") {
            return trimmed
        }
        return "\(trimmed) \(percent)%"
    }

    private func shouldPostSatellite(percent: Int) -> Bool {
        let now = Date()
        if percent >= 100 || satelliteLastPercent < 0 {
            satelliteLastPercent = percent
            satelliteLastUpdate = now
            return true
        }
        let percentChanged = abs(percent - satelliteLastPercent) >= minPercentStep
        let intervalElapsed = now.timeIntervalSince(satelliteLastUpdate) >= minUpdateInterval
        guard percentChanged || intervalElapsed else { return false }
        satelliteLastPercent = percent
        satelliteLastUpdate = now
        return true
    }

    private func shouldPostSetup(percent: Int) -> Bool {
        let now = Date()
        if percent >= 100 || setupLastPercent < 0 {
            setupLastPercent = percent
            setupLastUpdate = now
            return true
        }
        let percentChanged = abs(percent - setupLastPercent) >= minPercentStep
        let intervalElapsed = now.timeIntervalSince(setupLastUpdate) >= minUpdateInterval
        guard percentChanged || intervalElapsed else { return false }
        setupLastPercent = percent
        setupLastUpdate = now
        return true
    }

    private func resetSatelliteThrottle() {
        satelliteLastPercent = -1
        satelliteLastUpdate = .distantPast
    }

    private func resetSetupThrottle() {
        setupLastPercent = -1
        setupLastUpdate = .distantPast
    }

    private func post(
        identifier: String,
        title: String,
        body: String,
        sound: UNNotificationSound?,
        ongoing: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.threadIdentifier = threadIdentifier
        content.userInfo = ["ongoing": ongoing, "mapDownload": true]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = ongoing ? .passive : .active
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }
}

extension MapDownloadNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.content.userInfo["mapDownload"] as? Bool == true else {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        let ongoing = notification.request.content.userInfo["ongoing"] as? Bool ?? false
        if ongoing {
            completionHandler([.list, .badge])
        } else {
            completionHandler([.banner, .list, .sound, .badge])
        }
    }
}
