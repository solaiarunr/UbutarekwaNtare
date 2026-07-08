//
//  AppDelegate.swift
//  Ubutare kwa Ntare
//
//  Created by HTS-PRO-2018 on 30/06/26.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        OneSignalService.shared.configureFromCache()
        MapDownloadNotificationService.shared.configure()
        NetworkMonitor.shared.start()
        OfflineMapManager.shared.recoverOfflineStateIfNeeded()
        OfflineMapManager.shared.ensureStreetTileServerRunning()
        OfflineSetupDownloadManager.shared.resumeIfNeeded()
        SatelliteDownloadManager.shared.resumeIfNeeded()
        if OfflineNavigationHelper.shared.hasNavigationData() {
            OfflineNavigationHelper.shared.initialize()
        }

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: SplashViewController())
        window?.makeKeyAndVisible()
        return true
    }
}
