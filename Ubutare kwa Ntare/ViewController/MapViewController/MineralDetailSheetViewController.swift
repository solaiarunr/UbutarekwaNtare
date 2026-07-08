import UIKit

final class MineralDetailSheetViewController: UIViewController {
    private let mineral: MineralsListItem
    private let canEdit: Bool
    private let canGetDirections: Bool
    private let onChanged: () -> Void

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let imageLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let typeLabel = UILabel()
    private let treasureLabel = UILabel()
    private let coordsLabel = UILabel()
    private let sizeLabel = UILabel()
    private let depthLabel = UILabel()
    private let reporterLabel = UILabel()
    private let dateLabel = UILabel()
    private let directionsButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let onEdit: (() -> Void)?
    private let onGetDirections: (() -> Void)?

    init(
        mineral: MineralsListItem,
        canEdit: Bool,
        canGetDirections: Bool,
        onChanged: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        onGetDirections: (() -> Void)? = nil
    ) {
        self.mineral = mineral
        self.canEdit = canEdit
        self.canGetDirections = canGetDirections
        self.onChanged = onChanged
        self.onEdit = onEdit
        self.onGetDirections = onGetDirections
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Mineral Details"
        setupUI()
        populateData()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = AppColors.lightGray
        imageView.isUserInteractionEnabled = true
        imageView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped)))

        imageLoadingIndicator.hidesWhenStopped = true
        imageLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(imageLoadingIndicator)
        NSLayoutConstraint.activate([
            imageLoadingIndicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            imageLoadingIndicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])

        [typeLabel, treasureLabel, coordsLabel, sizeLabel, depthLabel, reporterLabel, dateLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .systemFont(ofSize: 15)
        }

        directionsButton.setTitle("Get Direction", for: .normal)
        directionsButton.backgroundColor = AppColors.primary
        directionsButton.setTitleColor(.white, for: .normal)
        directionsButton.layer.cornerRadius = 8
        directionsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        directionsButton.isHidden = !canGetDirections
        directionsButton.addTarget(self, action: #selector(directionsTapped), for: .touchUpInside)

        editButton.setTitle("Edit", for: .normal)
        editButton.backgroundColor = AppColors.primary
        editButton.setTitleColor(.white, for: .normal)
        editButton.layer.cornerRadius = 8
        editButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        editButton.isHidden = onEdit == nil
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        deleteButton.setTitle("Delete", for: .normal)
        deleteButton.backgroundColor = AppColors.red
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.layer.cornerRadius = 8
        deleteButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        deleteButton.isHidden = !canEdit
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        [imageView, typeLabel, treasureLabel, coordsLabel, sizeLabel, depthLabel,
         reporterLabel, dateLabel, directionsButton, editButton, deleteButton].forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])
    }

    private func populateData() {
        typeLabel.text = "Type: \(mineral.mineralTypeId.name)"
        treasureLabel.text = "Discovery: \(mineral.treasureType.capitalized)"
        coordsLabel.text = String(format: "Location: %.6f, %.6f", mineral.latitude, mineral.longitude)
        sizeLabel.text = "Size: \(mineral.sizeCubicMeters) m³"
        depthLabel.text = "Depth: \(mineral.depthCm ?? 0) cm"
        reporterLabel.text = "Reporter: \(mineral.addedBy?.displayName ?? "Unknown")"
        dateLabel.text = "Date: \(mineral.createdAt ?? "")"
        loadMineralImage()
    }

    private func loadMineralImage() {
        guard let imagePath = mineral.image, !imagePath.isEmpty else {
            imageView.isHidden = true
            return
        }

        imageView.isHidden = false
        imageView.isUserInteractionEnabled = false

        if let cached = MineralImageLoader.memoryCachedImage(mineralId: mineral.id, imagePath: imagePath) {
            imageView.image = cached
            imageView.isUserInteractionEnabled = true
            imageLoadingIndicator.stopAnimating()
            return
        }

        imageView.image = nil
        imageLoadingIndicator.startAnimating()

        Task {
            let image = await MineralImageLoader.loadImage(from: imagePath, mineralId: mineral.id)
            await MainActor.run {
                imageLoadingIndicator.stopAnimating()
                imageView.image = image
                imageView.isHidden = image == nil
                imageView.isUserInteractionEnabled = image != nil
            }
        }
    }

    @objc private func imageTapped() {
        guard let image = imageView.image else { return }
        let preview = ImagePreviewViewController(image: image)
        preview.modalPresentationStyle = .fullScreen
        present(preview, animated: true)
    }

    @objc private func editTapped() {
        dismiss(animated: true) { [onEdit] in
            onEdit?()
        }
    }

    @objc private func directionsTapped() {
        dismiss(animated: true) { [onGetDirections] in
            onGetDirections?()
        }
    }

    @objc private func deleteTapped() {
        let alert = UIAlertController(title: "Delete", message: "Are you sure you want to delete this discovery?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        present(alert, animated: true)
    }

    private func performDelete() {
        guard let token = AuthSessionManager.shared.token else { return }
        Task {
            do {
                let response = try await APIClient.shared.deleteMineral(token: token, id: mineral.id)
                if response.status {
                    var minerals = LocalDataStore.shared.getMinerals()
                    minerals.removeAll { $0.id == mineral.id }
                    LocalDataStore.shared.saveMinerals(minerals)
                    await MainActor.run {
                        onChanged()
                        dismiss(animated: true)
                    }
                }
            } catch {
                let pending = PendingMineralSync(
                    localId: UUID().uuidString,
                    serverId: mineral.id,
                    action: .delete,
                    mineralTypeId: mineral.mineralTypeId.id,
                    latitude: mineral.latitude,
                    longitude: mineral.longitude,
                    treasureType: mineral.treasureType,
                    sizeCubicMeters: mineral.sizeCubicMeters,
                    depthCm: mineral.depthCm ?? 0,
                    addedBy: AuthSessionManager.shared.userId ?? "",
                    imagePath: nil,
                    createdAt: Date()
                )
                LocalDataStore.shared.addPendingSync(pending)
                await MainActor.run {
                    onChanged()
                    dismiss(animated: true)
                }
            }
        }
    }
}
