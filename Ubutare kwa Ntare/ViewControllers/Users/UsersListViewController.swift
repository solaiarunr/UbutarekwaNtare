import UIKit

final class UsersListViewController: UIViewController {
    private let tableView = UITableView()
    private var users: [AuthUser] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Users"
        setupUI()
        loadUsers()
    }

    private func setupUI() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UserCell.self, forCellReuseIdentifier: UserCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadUsers() {
        guard let token = AuthSessionManager.shared.token else { return }
        Task {
            do {
                let response = try await APIClient.shared.listUsers(token: token)
                if response.status, let result = response.result {
                    LocalDataStore.shared.saveUsers(result.users)
                    await MainActor.run {
                        users = result.users
                        tableView.reloadData()
                    }
                }
            } catch {
                await MainActor.run {
                    users = LocalDataStore.shared.getUsers()
                    tableView.reloadData()
                }
            }
        }
    }

    private func toggleActive(for user: AuthUser, isActive: Bool) {
        guard let token = AuthSessionManager.shared.token else { return }
        Task {
            do {
                _ = try await APIClient.shared.updateUserActive(token: token, userId: user.id, isActive: isActive)
                await MainActor.run { loadUsers() }
            } catch {
                await MainActor.run {
                    showAlert((error as? APIError)?.errorDescription ?? "Failed to update user")
                }
            }
        }
    }

    private func changePassword(for user: AuthUser) {
        let alert = UIAlertController(title: "Change Password", message: user.displayName, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "New password"; $0.isSecureTextEntry = true }
        alert.addTextField { $0.placeholder = "Confirm password"; $0.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let password = alert.textFields?[0].text,
                  let confirm = alert.textFields?[1].text,
                  password == confirm,
                  let token = AuthSessionManager.shared.token else { return }
            Task {
                do {
                    _ = try await APIClient.shared.changePassword(
                        token: token,
                        userId: user.id,
                        request: ChangePasswordRequest(password: password, confirmPassword: confirm)
                    )
                    await MainActor.run { self?.showAlert("Password changed successfully") }
                } catch {
                    await MainActor.run {
                        self?.showAlert((error as? APIError)?.errorDescription ?? "Failed to change password")
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension UsersListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { users.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UserCell.reuseId, for: indexPath) as! UserCell
        let user = users[indexPath.row]
        cell.configure(with: user) { [weak self] isActive in
            self?.toggleActive(for: user, isActive: isActive)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        changePassword(for: users[indexPath.row])
    }
}

private final class UserCell: UITableViewCell {
    static let reuseId = "UserCell"
    private let nameLabel = UILabel()
    private let phoneLabel = UILabel()
    private let roleLabel = UILabel()
    private let activeSwitch = UISwitch()
    private var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        nameLabel.font = .boldSystemFont(ofSize: 16)
        phoneLabel.font = .systemFont(ofSize: 14)
        phoneLabel.textColor = AppColors.gray
        roleLabel.font = .systemFont(ofSize: 13)
        roleLabel.textColor = AppColors.primary
        activeSwitch.onTintColor = AppColors.primary
        activeSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [nameLabel, phoneLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        activeSwitch.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentView.addSubview(activeSwitch)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: activeSwitch.leadingAnchor, constant: -12),
            activeSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            activeSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with user: AuthUser, onToggle: @escaping (Bool) -> Void) {
        nameLabel.text = user.displayName
        phoneLabel.text = user.phone
        roleLabel.text = UserRole.from(user.role)?.displayName ?? user.role
        activeSwitch.isOn = user.isActive
        self.onToggle = onToggle
    }

    @objc private func switchChanged() {
        onToggle?(activeSwitch.isOn)
    }
}
