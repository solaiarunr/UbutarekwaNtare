import UIKit

final class NotificationViewController: UIViewController {
    private let tableView = UITableView()
    private var notifications: [AppNotification] = []
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Notifications"
        setupUI()
        loadNotifications()
    }

    private func setupUI() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "No notification to show. Check again later"
        emptyLabel.textColor = AppColors.gray
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func loadNotifications() {
        guard let token = AuthSessionManager.shared.token else { return }
        Task {
            do {
                let response = try await APIClient.shared.getNotifications(token: token)
                if response.status, let items = response.result {
                    LocalDataStore.shared.saveNotifications(items)
                    await MainActor.run {
                        notifications = items
                        updateUI()
                    }
                }
            } catch {
                await MainActor.run {
                    notifications = LocalDataStore.shared.getNotifications()
                    updateUI()
                }
            }
        }
    }

    private func updateUI() {
        emptyLabel.isHidden = !notifications.isEmpty
        tableView.reloadData()
    }
}

extension NotificationViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        notifications.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let notification = notifications[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = notification.title ?? "Notification"
        config.secondaryText = notification.body
        cell.contentConfiguration = config
        return cell
    }
}
