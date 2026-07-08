import UIKit

final class ConfirmViewController: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()
    private let continueButton = UIButton(type: .system)
    private var isSetupComplete = false
    private var isDownloading = false
    private var downloadFailed = false
    private var setupTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.hidesBackButton = true
        setupUI()
        updateRoleMessage()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkConnectivityChanged(_:)),
            name: .networkConnectivityChanged,
            object: nil
        )
        OfflineSetupDownloadManager.shared.stop()
        startSetup()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setupTask?.cancel()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        setupTask?.cancel()
    }

    @objc private func handleNetworkConnectivityChanged(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        guard downloadFailed || !isSetupComplete, !isDownloading else { return }
        startSetup()
    }

    private func setupUI() {
        titleLabel.text = "Congratulations"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.progressTintColor = AppColors.primary
        progressView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = AppColors.gray
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        continueButton.setTitle("Continue", for: .normal)
        continueButton.backgroundColor = AppColors.primary
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        continueButton.layer.cornerRadius = 8
        continueButton.isHidden = true
        continueButton.isEnabled = false
        continueButton.alpha = 0.5
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        [titleLabel, messageLabel, progressView, statusLabel, continueButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 40),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            continueButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func updateRoleMessage() {
        let role = AuthSessionManager.shared.currentRole
        let roleName = role?.displayName ?? "User"
        messageLabel.text = "Your name has been successfully added to\nthe system as \(roleName)"
    }

    private func startSetup() {
        guard let token = AuthSessionManager.shared.token else {
            navigateTo(LoginViewController())
            return
        }

        setupTask?.cancel()
        isDownloading = true
        downloadFailed = false
        isSetupComplete = false
        hideContinueButton()
        progressView.isHidden = false

        if let partialPercent = currentPartialDownloadPercent() {
            updateDownloadProgress(percent: partialPercent, status: partialDownloadStatus(for: partialPercent))
        } else {
            updateDownloadProgress(percent: 0, status: "Downloading navigation file…")
        }

        setupTask = Task {
            MapDownloadNotificationService.shared.requestPermissionIfNeeded()
            let success = await OfflineSetupManager.shared.performSetup(token: token) { [weak self] percent, status in
                Task { @MainActor in
                    self?.updateDownloadProgress(percent: percent, status: status)
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                isDownloading = false

                if success, OfflineSetupManager.shared.isComplete {
                    MapDownloadNotificationService.shared.showSetupComplete()
                    showContinueButton()
                } else {
                    downloadFailed = true
                    MapDownloadNotificationService.shared.showSetupFailed("Map download failed. Tap Resume to try again.")
                    if let partialPercent = currentPartialDownloadPercent() {
                        updateDownloadProgress(
                            percent: partialPercent,
                            status: partialDownloadStatus(for: partialPercent)
                        )
                    }
                    showResumeButton()
                }
            }
        }
    }

    private func updateDownloadProgress(percent: Int, status: String) {
        isDownloading = true
        isSetupComplete = false
        downloadFailed = false
        progressView.progress = Float(percent.clamped(to: 0...100)) / 100.0
        statusLabel.text = status
        hideContinueButton()
        MapDownloadNotificationService.shared.updateSetupProgress(percent: percent, message: status)
    }

    private func showContinueButton() {
        guard OfflineSetupManager.shared.isComplete else {
            hideContinueButton()
            return
        }
        isSetupComplete = true
        downloadFailed = false
        isDownloading = false
        progressView.progress = 1.0
        continueButton.setTitle("Continue", for: .normal)
        continueButton.isHidden = false
        continueButton.isEnabled = true
        continueButton.alpha = 1.0
    }

    private func hideContinueButton() {
        continueButton.isHidden = true
        continueButton.isEnabled = false
        continueButton.alpha = 0.5
    }

    private func showResumeButton() {
        continueButton.setTitle("Resume Download", for: .normal)
        continueButton.isHidden = false
        continueButton.isEnabled = true
        continueButton.alpha = 1.0
    }

    private func currentPartialDownloadPercent() -> Int? {
        if let streetPercent = MbTilesDownloader.currentDownloadPercent(),
           !OfflineMapManager.shared.isStreetFullyDownloaded() {
            return 10 + (streetPercent * 90 + 50) / 100
        }
        if let navPercent = NavigationDataDownloader.currentDownloadPercent(),
           !OfflineNavigationHelper.shared.hasNavigationData() {
            return navPercent * 10 / 100
        }
        return nil
    }

    private func partialDownloadStatus(for percent: Int) -> String {
        if MbTilesDownloader.hasPartialDownload(), !OfflineMapManager.shared.isStreetFullyDownloaded() {
            return "Downloading Map files… \(percent)%"
        }
        if NavigationDataDownloader.hasPartialDownload(), !OfflineNavigationHelper.shared.hasNavigationData() {
            return "Download paused at \(percent)%. Tap Resume Download to continue."
        }
        return "Downloading Map files… \(percent)%"
    }

    @objc private func continueTapped() {
        if isSetupComplete, OfflineSetupManager.shared.isComplete {
            navigateTo(HomeViewController())
            return
        }

        if downloadFailed || !isSetupComplete {
            startSetup()
        }
    }

    private func navigateTo(_ vc: UIViewController) {
        guard let window = view.window else { return }
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
    }
}
