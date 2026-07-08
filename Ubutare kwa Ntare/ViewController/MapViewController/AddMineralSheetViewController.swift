import UIKit
import PhotosUI

final class AddMineralSheetViewController: UIViewController {
    private let latitude: Double
    private let longitude: Double
    private let mineralTypes: [MineralType]
    private let editingMineral: MineralsListItem?
    private let onSaved: () -> Void

    private let scrollView = UIScrollView()
    private let mineralTypePicker = UIPickerView()
    private let sizeField = UITextField()
    private let depthField = UITextField()
    private let treasureSegment = UISegmentedControl(items: ["Natural", "Hidden Treasure"])
    private let latLabel = UILabel()
    private let lonLabel = UILabel()
    private let photoButton = UIButton(type: .system)
    private let photoPreview = UIImageView()
    private let saveButton = UIButton(type: .system)
    private var selectedImage: UIImage?
    private var selectedImageData: Data?

    init(
        latitude: Double,
        longitude: Double,
        mineralTypes: [MineralType],
        editingMineral: MineralsListItem? = nil,
        onSaved: @escaping () -> Void
    ) {
        if let editingMineral {
            self.latitude = editingMineral.latitude
            self.longitude = editingMineral.longitude
        } else {
            self.latitude = latitude
            self.longitude = longitude
        }
        self.mineralTypes = mineralTypes
        self.editingMineral = editingMineral
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = editingMineral == nil ? "Add Discovery" : "Edit Discovery"
        setupUI()
        if let editingMineral {
            prefillForEditing(editingMineral)
        }
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        latLabel.text = String(format: "Latitude: %.6f", latitude)
        lonLabel.text = String(format: "Longitude: %.6f", longitude)
        [latLabel, lonLabel].forEach { $0.font = .systemFont(ofSize: 14) }

        mineralTypePicker.dataSource = self
        mineralTypePicker.delegate = self

        configureField(sizeField, placeholder: "Estimated size (m³)")
        sizeField.keyboardType = .decimalPad
        configureField(depthField, placeholder: "Depth (cm) *")
        depthField.keyboardType = .decimalPad
        treasureSegment.selectedSegmentIndex = 0

        photoPreview.contentMode = .scaleAspectFill
        photoPreview.clipsToBounds = true
        photoPreview.layer.cornerRadius = 8
        photoPreview.backgroundColor = AppColors.lightGray
        photoPreview.isHidden = true
        photoPreview.heightAnchor.constraint(equalToConstant: 160).isActive = true

        photoButton.setTitle("Upload Photo (optional)", for: .normal)
        photoButton.setTitleColor(AppColors.primary, for: .normal)
        photoButton.addTarget(self, action: #selector(photoTapped), for: .touchUpInside)

        saveButton.setTitle(editingMineral == nil ? "Save" : "Update", for: .normal)
        saveButton.backgroundColor = AppColors.primary
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 8
        saveButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let typeLabel = UILabel()
        typeLabel.text = "Mineral Type"
        typeLabel.font = .boldSystemFont(ofSize: 14)

        [typeLabel, mineralTypePicker, latLabel, lonLabel, sizeField, depthField,
         treasureSegment, photoPreview, photoButton, saveButton].forEach { stack.addArrangedSubview($0) }

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
            mineralTypePicker.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func prefillForEditing(_ mineral: MineralsListItem) {
        if let index = mineralTypes.firstIndex(where: { $0.id == mineral.mineralTypeId.id }) {
            mineralTypePicker.selectRow(index, inComponent: 0, animated: false)
        }
        if mineral.sizeCubicMeters > 0 {
            sizeField.text = String(mineral.sizeCubicMeters)
        }
        if let depthCm = mineral.depthCm {
            depthField.text = String(depthCm)
        }
        treasureSegment.selectedSegmentIndex = mineral.treasureType.lowercased() == "hidden" ? 1 : 0

        guard let imagePath = mineral.image, !imagePath.isEmpty else { return }
        Task {
            let image = await MineralImageLoader.loadImage(from: imagePath, mineralId: mineral.id)
            await MainActor.run {
                guard let image else { return }
                selectedImage = image
                photoPreview.image = image
                photoPreview.isHidden = false
                photoButton.setTitle("Change Photo", for: .normal)
            }
        }
    }

    private func configureField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
    }

    @objc private func photoTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func saveTapped() {
        guard !mineralTypes.isEmpty else {
            showAlert("No mineral types available")
            return
        }
        let typeIndex = mineralTypePicker.selectedRow(inComponent: 0)
        let mineralType = mineralTypes[typeIndex]
        guard let sizeText = sizeField.text, let size = Double(sizeText) else {
            showAlert("Enter estimated size")
            return
        }
        guard let depthText = depthField.text, let depth = Double(depthText) else {
            showAlert("Depth is required")
            return
        }
        let treasureType = treasureSegment.selectedSegmentIndex == 0 ? "natural" : "hidden"
        let imageData = selectedImageData ?? selectedImage?.jpegData(compressionQuality: 0.8)

        guard let token = AuthSessionManager.shared.token else {
            showAlert("Session expired. Please login again.")
            return
        }

        saveButton.isEnabled = false
        Task {
            if let editingMineral {
                await updateDiscovery(
                    token: token,
                    mineral: editingMineral,
                    mineralTypeId: mineralType.id,
                    treasureType: treasureType,
                    size: size,
                    depth: depth,
                    imageData: imageData
                )
            } else {
                await createDiscovery(
                    token: token,
                    mineralTypeId: mineralType.id,
                    treasureType: treasureType,
                    size: size,
                    depth: depth,
                    imageData: imageData
                )
            }
        }
    }

    private func createDiscovery(
        token: String,
        mineralTypeId: String,
        treasureType: String,
        size: Double,
        depth: Double,
        imageData: Data?
    ) async {
        do {
            let response = try await APIClient.shared.createMineral(
                token: token,
                mineralTypeId: mineralTypeId,
                latitude: latitude,
                longitude: longitude,
                treasureType: treasureType,
                sizeCubicMeters: size,
                depthCm: depth,
                imageData: imageData
            )
            if response.status {
                await MainActor.run {
                    onSaved()
                    dismiss(animated: true)
                }
            } else {
                await saveOffline(
                    action: .create,
                    serverId: nil,
                    mineralTypeId: mineralTypeId,
                    treasureType: treasureType,
                    size: size,
                    depth: depth,
                    imageData: imageData
                )
            }
        } catch {
            await saveOffline(
                action: .create,
                serverId: nil,
                mineralTypeId: mineralTypeId,
                treasureType: treasureType,
                size: size,
                depth: depth,
                imageData: imageData
            )
        }
    }

    private func updateDiscovery(
        token: String,
        mineral: MineralsListItem,
        mineralTypeId: String,
        treasureType: String,
        size: Double,
        depth: Double,
        imageData: Data?
    ) async {
        do {
            let response = try await APIClient.shared.updateMineral(
                token: token,
                id: mineral.id,
                mineralTypeId: mineralTypeId,
                latitude: latitude,
                longitude: longitude,
                treasureType: treasureType,
                sizeCubicMeters: size,
                depthCm: depth,
                imageData: imageData
            )
            if response.status {
                await MainActor.run {
                    onSaved()
                    dismiss(animated: true)
                }
            } else {
                await saveOffline(
                    action: .update,
                    serverId: mineral.id,
                    mineralTypeId: mineralTypeId,
                    treasureType: treasureType,
                    size: size,
                    depth: depth,
                    imageData: imageData
                )
            }
        } catch {
            await saveOffline(
                action: .update,
                serverId: mineral.id,
                mineralTypeId: mineralTypeId,
                treasureType: treasureType,
                size: size,
                depth: depth,
                imageData: imageData
            )
        }
    }

    private func saveOffline(
        action: PendingMineralSync.Action,
        serverId: String?,
        mineralTypeId: String,
        treasureType: String,
        size: Double,
        depth: Double,
        imageData: Data?
    ) async {
        let localId = UUID().uuidString
        var imagePath: String?
        if let imageData {
            let url = LocalDataStore.shared.pendingImagesDirectory().appendingPathComponent("\(localId).jpg")
            try? imageData.write(to: url)
            imagePath = url.path
        }
        let pending = PendingMineralSync(
            localId: localId,
            serverId: serverId,
            action: action,
            mineralTypeId: mineralTypeId,
            latitude: latitude,
            longitude: longitude,
            treasureType: treasureType,
            sizeCubicMeters: size,
            depthCm: depth,
            addedBy: AuthSessionManager.shared.userId ?? "",
            imagePath: imagePath,
            createdAt: Date()
        )
        LocalDataStore.shared.addPendingSync(pending)
        await MainActor.run {
            let message = action == .update
                ? "Updated offline. Will sync when connected."
                : "Saved offline. Will sync when connected."
            showAlert(message)
            onSaved()
            dismiss(animated: true)
        }
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension AddMineralSheetViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { mineralTypes.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        mineralTypes[row].name
    }
}

extension AddMineralSheetViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self, let image = image as? UIImage else { return }
                self.selectedImage = image
                self.selectedImageData = image.jpegData(compressionQuality: 0.8)
                self.photoPreview.image = image
                self.photoPreview.isHidden = false
                self.photoButton.setTitle("Change Photo", for: .normal)
            }
        }
    }
}
