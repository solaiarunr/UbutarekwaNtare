import UIKit

final class CreateUserViewController: UIViewController {
    private let nameField = UITextField()
    private let phoneField = UITextField()
    private let passwordField = UITextField()
    private let confirmPasswordField = UITextField()
    private let rolePicker = UIPickerView()
    private let createButton = UIButton(type: .system)
    private var roles: [RoleSetting] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Create Account"
        loadRoles()
        setupUI()
    }

    private func loadRoles() {
        let localRoles = LocalDataStore.shared.getRoles()
        roles = localRoles.isEmpty
            ? [
                RoleSetting(key: "admin", label: "Admin"),
                RoleSetting(key: "mineral_explorer", label: "Mineral Explorer"),
                RoleSetting(key: "mineral_site_visitor", label: "Mineral Site Visitor")
            ]
            : localRoles.filter { !$0.key.lowercased().contains("super_admin") }
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        [nameField, phoneField, passwordField, confirmPasswordField].forEach {
            $0.borderStyle = .roundedRect
        }
        nameField.placeholder = "Enter User Name"
        phoneField.placeholder = "Mobile Number"
        phoneField.keyboardType = .phonePad
        passwordField.placeholder = "Set Password"
        passwordField.isSecureTextEntry = true
        confirmPasswordField.placeholder = "Re-enter password"
        confirmPasswordField.isSecureTextEntry = true

        rolePicker.dataSource = self
        rolePicker.delegate = self

        createButton.setTitle("Done", for: .normal)
        createButton.backgroundColor = AppColors.primary
        createButton.setTitleColor(.white, for: .normal)
        createButton.layer.cornerRadius = 8
        createButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        let roleLabel = UILabel()
        roleLabel.text = "Select Role"
        roleLabel.font = .boldSystemFont(ofSize: 14)

        [nameField, phoneField, passwordField, confirmPasswordField, roleLabel, rolePicker, createButton]
            .forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
            rolePicker.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    @objc private func createTapped() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        let confirm = confirmPasswordField.text ?? ""

        guard !name.isEmpty else { showAlert("Enter Name"); return }
        guard !phone.isEmpty else { showAlert("Enter Mobile Number"); return }
        guard !password.isEmpty else { showAlert("Enter password"); return }
        guard password == confirm else { showAlert("Password and confirm password do not match"); return }
        guard !roles.isEmpty else { showAlert("No roles available"); return }

        let role = roles[rolePicker.selectedRow(inComponent: 0)]
        guard let token = AuthSessionManager.shared.token else {
            showAlert("Session expired. Please login again.")
            return
        }

        createButton.isEnabled = false
        Task {
            do {
                let response = try await APIClient.shared.createUser(
                    token: token,
                    request: CreateUserRequest(
                        phone: phone,
                        password: password,
                        confirmPassword: confirm,
                        role: role.key,
                        displayName: name
                    )
                )
                await MainActor.run {
                    createButton.isEnabled = true
                    if response.status {
                        showAlert("User created successfully")
                        clearFields()
                    } else {
                        showAlert(response.message ?? "Failed to create user")
                    }
                }
            } catch {
                await MainActor.run {
                    createButton.isEnabled = true
                    showAlert((error as? APIError)?.errorDescription ?? "Failed to create user")
                }
            }
        }
    }

    private func clearFields() {
        nameField.text = ""
        phoneField.text = ""
        passwordField.text = ""
        confirmPasswordField.text = ""
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension CreateUserViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { roles.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        roles[row].label
    }
}
