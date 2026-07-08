import UIKit
internal import _LocationEssentials

final class LoginViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let phoneField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let footerLabel = UILabel()
    private let loader = UIActivityIndicatorView(style: .large)
    private var passwordVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.hidesBackButton = true
        setupUI()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        titleLabel.text = "Login account"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureField(phoneField, placeholder: "Mobile Number")
        phoneField.keyboardType = .phonePad
        configureField(passwordField, placeholder: "Password")
        passwordField.isSecureTextEntry = true

        loginButton.setTitle("Login", for: .normal)
        loginButton.backgroundColor = AppColors.primary
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        loginButton.layer.cornerRadius = 8
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        footerLabel.numberOfLines = 0
        footerLabel.textAlignment = .center
        footerLabel.font = .systemFont(ofSize: 13)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        let footer = NSMutableAttributedString(string: "Designed And Developed by ", attributes: [.foregroundColor: AppColors.primary])
        footer.append(NSAttributedString(string: "Gasape Group Innovation LTD", attributes: [.foregroundColor: UIColor.darkGray]))
        footerLabel.attributedText = footer

        loader.hidesWhenStopped = true
        loader.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, phoneField, passwordField, loginButton, footerLabel, loader].forEach { contentView.addSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            phoneField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            phoneField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            phoneField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            phoneField.heightAnchor.constraint(equalToConstant: 48),

            passwordField.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 16),
            passwordField.leadingAnchor.constraint(equalTo: phoneField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: phoneField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 48),

            loginButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 24),
            loginButton.leadingAnchor.constraint(equalTo: phoneField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: phoneField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),

            footerLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 40),
            footerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            footerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func loginTapped() {
        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !phone.isEmpty else {
            showAlert("Enter Mobile Number")
            return
        }
        guard !password.isEmpty else {
            showAlert("Enter password")
            return
        }

        setLoading(true)
        Task {
            do {
                let response = try await APIClient.shared.login(phone: phone, password: password)
                guard response.status, let result = response.result else {
                    await MainActor.run {
                        setLoading(false)
                        showAlert(response.message ?? "Login failed. Please check your credentials.")
                    }
                    return
                }

                AuthSessionManager.shared.saveSession(token: result.token, user: result.user)
                await SettingsSyncService.shared.fetchAndSave(token: result.token)

                if !(UserRole.from(result.user.role)?.skipsPushNotifications ?? false) {
                    OneSignalService.shared.requestPermission()
                }

                let regStatus = await DeviceRegistrationService.shared.registerAfterLogin(
                    token: result.token,
                    deviceToken: OneSignalService.shared.deviceToken
                )
                if regStatus == .unauthorized {
                    await MainActor.run {
                        setLoading(false)
                        showInactiveAlert()
                    }
                    return
                }

                await PendingMineralSyncService.shared.syncPending(token: result.token)
                let location = await LocationService.shared.resolveLocation()
                await MineralsSyncService.shared.syncAll(
                    token: result.token,
                    latitude: location.latitude,
                    longitude: location.longitude
                )

                await MainActor.run {
                    setLoading(false)
                    let next = OfflineSetupManager.shared.isComplete
                        ? HomeViewController()
                        : ConfirmViewController()
                    navigateTo(next)
                }
            } catch APIError.unauthorized {
                await MainActor.run {
                    setLoading(false)
                    showInactiveAlert()
                }
            } catch {
                await MainActor.run {
                    setLoading(false)
                    showAlert((error as? APIError)?.errorDescription ?? "Login failed. Please check your credentials.")
                }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        loginButton.isEnabled = !loading
        phoneField.isEnabled = !loading
        passwordField.isEnabled = !loading
        loading ? loader.startAnimating() : loader.stopAnimating()
    }

    private func showInactiveAlert() {
        let alert = UIAlertController(title: nil, message: "Your account is inactive", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            AuthSessionManager.shared.clearSession()
        })
        present(alert, animated: true)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func navigateTo(_ vc: UIViewController) {
        guard let window = view.window else { return }
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
    }
}
