import UIKit

final class HomeViewController: UIViewController {
    private let containerView = UIView()
    private let bottomNav = UIStackView()
    private var currentChild: UIViewController?

    private let mapButton = UIButton(type: .system)
    private let createUserButton = UIButton(type: .system)
    private let usersButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.hidesBackButton = true
        setupLayout()
        showMap()
        configureBottomNav()
    }

    private func setupLayout() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        bottomNav.axis = .horizontal
        bottomNav.distribution = .fillEqually
        bottomNav.backgroundColor = .black
        bottomNav.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(containerView)
        view.addSubview(bottomNav)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNav.topAnchor.constraint(equalTo: containerView.bottomAnchor),
            bottomNav.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomNav.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNav.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomNav.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configureBottomNav() {
        let isSuperAdmin = AuthSessionManager.shared.currentRole?.showsBottomNav ?? false
        bottomNav.isHidden = !isSuperAdmin
        guard isSuperAdmin else { return }

        configureNavButton(mapButton, title: "View Map", action: #selector(showMapTapped))
        configureNavButton(createUserButton, title: "Create User", action: #selector(showCreateUserTapped))
        configureNavButton(usersButton, title: "Users", action: #selector(showUsersTapped))

        bottomNav.addArrangedSubview(mapButton)
        bottomNav.addArrangedSubview(createUserButton)
        bottomNav.addArrangedSubview(usersButton)
        selectTab(mapButton)
    }

    private func configureNavButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func showMapTapped() {
        selectTab(mapButton)
        showMap()
    }

    @objc private func showCreateUserTapped() {
        selectTab(createUserButton)
        showChild(CreateUserViewController())
    }

    @objc private func showUsersTapped() {
        selectTab(usersButton)
        showChild(UsersListViewController())
    }

    private func selectTab(_ selected: UIButton) {
        for button in [mapButton, createUserButton, usersButton] {
            button.backgroundColor = button === selected
                ? AppColors.primary.withAlphaComponent(0.3)
                : .clear
        }
    }

    private func showMap() {
        showChild(MapVc())
    }

    private func showChild(_ child: UIViewController) {
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        child.didMove(toParent: self)
        currentChild = child
    }
}
