import UIKit

final class SplashViewController: UIViewController {
    private let logoLabel: UILabel = {
        let label = UILabel()
        label.text = "Ubutare kwa Ntare"
        label.font = .boldSystemFont(ofSize: 28)
        label.textColor = AppColors.primary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Burundi Mineral Maps"
        label.font = .systemFont(ofSize: 16)
        label.textColor = AppColors.gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        view.addSubview(logoLabel)
        view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            logoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        Task { await routeAfterSplash() }
    }

    private func routeAfterSplash() async {
        try? await Task.sleep(nanoseconds: UInt64(AppConstants.splashMinDuration * 1_000_000_000))

        if let token = AuthSessionManager.shared.token, !token.isEmpty {
            let status = await DeviceRegistrationService.shared.registerAfterLogin(
                token: token,
                deviceToken: OneSignalService.shared.deviceToken
            )
            if status == .unauthorized {
                await MainActor.run { showInactiveAlert() }
                return
            }
            await PendingMineralSyncService.shared.syncPending(token: token)
        }

        await MainActor.run {
            let next: UIViewController
            if !AuthSessionManager.shared.isLoggedIn {
                next = LoginViewController()
            } else if !OfflineSetupManager.shared.isComplete {
                next = ConfirmViewController()
            } else {
                next = HomeViewController()
            }
            navigateTo(next)
        }
    }

    private func showInactiveAlert() {
        let alert = UIAlertController(title: nil, message: "Your account is inactive", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            AuthSessionManager.shared.clearSession()
            self?.navigateTo(LoginViewController())
        })
        present(alert, animated: true)
    }

    private func navigateTo(_ vc: UIViewController) {
        guard let window = view.window ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
    }
}
