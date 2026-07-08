import Foundation
import Network

extension Notification.Name {
    static let networkConnectivityChanged = Notification.Name("networkConnectivityChanged")
    static let satelliteDownloadProgress = Notification.Name("satelliteDownloadProgress")
    static let satelliteDownloadComplete = Notification.Name("satelliteDownloadComplete")
    static let satelliteDownloadFailed = Notification.Name("satelliteDownloadFailed")
    static let satelliteDownloadStopped = Notification.Name("satelliteDownloadStopped")
    static let offlineSetupDownloadProgress = Notification.Name("offlineSetupDownloadProgress")
}

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ubutare.network-monitor")
    private var isStarted = false
    private(set) var isConnected = true

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.isConnected != connected
                self.isConnected = connected
                if changed {
                    NotificationCenter.default.post(
                        name: .networkConnectivityChanged,
                        object: self,
                        userInfo: ["isConnected": connected]
                    )
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
