import UIKit

final class ProfileViewController: UIViewController {
    private let nameField = UITextField()
    private let phoneField = UITextField()
    private let roleField = UITextField()
    private let changePasswordButton = UIButton(type: .system)
    private let logoutButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Personal Info"
        setupNavigation()
        setupUI()
        loadProfile()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func setupUI() {
        [nameField, phoneField, roleField].forEach {
            $0.borderStyle = .roundedRect
            $0.isEnabled = false
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        nameField.placeholder = "Name"
        phoneField.placeholder = "Mobile Number"
        roleField.placeholder = "Role"

        changePasswordButton.setTitle("Change Password", for: .normal)
        changePasswordButton.backgroundColor = AppColors.primary
        changePasswordButton.setTitleColor(.white, for: .normal)
        changePasswordButton.layer.cornerRadius = 8
        changePasswordButton.translatesAutoresizingMaskIntoConstraints = false
        changePasswordButton.addTarget(self, action: #selector(changePasswordTapped), for: .touchUpInside)

        logoutButton.setTitle("Logout", for: .normal)
        logoutButton.backgroundColor = AppColors.red
        logoutButton.setTitleColor(.white, for: .normal)
        logoutButton.layer.cornerRadius = 8
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        view.addSubview(changePasswordButton)
        view.addSubview(logoutButton)

        NSLayoutConstraint.activate([
            nameField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nameField.heightAnchor.constraint(equalToConstant: 48),

            phoneField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),
            phoneField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            phoneField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            phoneField.heightAnchor.constraint(equalToConstant: 48),

            roleField.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 16),
            roleField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            roleField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            roleField.heightAnchor.constraint(equalToConstant: 48),

            changePasswordButton.topAnchor.constraint(equalTo: roleField.bottomAnchor, constant: 32),
            changePasswordButton.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            changePasswordButton.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            changePasswordButton.heightAnchor.constraint(equalToConstant: 48),

            logoutButton.topAnchor.constraint(equalTo: changePasswordButton.bottomAnchor, constant: 16),
            logoutButton.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            logoutButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func loadProfile() {
        nameField.text = AuthSessionManager.shared.displayName
        phoneField.text = AuthSessionManager.shared.phone
        roleField.text = AuthSessionManager.shared.currentRole?.displayName ?? AuthSessionManager.shared.role
    }

    @objc private func changePasswordTapped() {
        let alert = UIAlertController(title: "Change Password", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "New password"; $0.isSecureTextEntry = true }
        alert.addTextField { $0.placeholder = "Confirm password"; $0.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let password = alert.textFields?[0].text,
                  let confirm = alert.textFields?[1].text else { return }
            if password != confirm {
                self?.showAlert("Password and confirm password do not match")
                return
            }
            self?.performChangePassword(password: password, confirm: confirm)
        })
        present(alert, animated: true)
    }

    private func performChangePassword(password: String, confirm: String) {
        guard let token = AuthSessionManager.shared.token,
              let userId = AuthSessionManager.shared.userId else {
            showAlert("Session expired. Please login again.")
            return
        }
        Task {
            do {
                let response = try await APIClient.shared.changePassword(
                    token: token,
                    userId: userId,
                    request: ChangePasswordRequest(password: password, confirmPassword: confirm)
                )
                await MainActor.run {
                    showAlert(response.message ?? "Password changed successfully")
                }
            } catch {
                await MainActor.run {
                    showAlert((error as? APIError)?.errorDescription ?? "Failed to change password")
                }
            }
        }
    }

    @objc private func logoutTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            AuthSessionManager.shared.clearSession()
            self?.navigateToLogin()
        })
        present(alert, animated: true)
    }

    private func navigateToLogin() {
        guard let window = view.window else { return }
        window.rootViewController = UINavigationController(rootViewController: LoginViewController())
        window.makeKeyAndVisible()
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
