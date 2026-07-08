import UIKit

final class SatelliteDownloadDetailsViewController: UIViewController {
    
    // UI Elements
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    private let zoomLabel = UILabel()
    private let totalFilesLabel = UILabel()
    private let thisZoomLabel = UILabel()
    private let fileLabel = UILabel()
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let percentLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
        updateUI()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        
        // Card Container
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 24
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        // Title
        titleLabel.text = "Burundi satellite map"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)
        
        // Subtitle (Status)
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = AppColors.gray
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(subtitleLabel)
        
        // Stats stack
        let statsStack = UIStackView()
        statsStack.axis = .vertical
        statsStack.spacing = 8
        statsStack.alignment = .leading
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statsStack)
        
        [zoomLabel, totalFilesLabel, thisZoomLabel, fileLabel].forEach { label in
            label.textColor = .black
            label.font = .systemFont(ofSize: 15, weight: .regular)
            label.translatesAutoresizingMaskIntoConstraints = false
            statsStack.addArrangedSubview(label)
        }
        fileLabel.textColor = AppColors.gray
        fileLabel.font = .systemFont(ofSize: 13, weight: .regular)
        
        // Progress view
        progressView.progressTintColor = AppColors.orange
        progressView.trackTintColor = UIColor.systemGray5
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressView)
        
        // Percent label
        percentLabel.font = .systemFont(ofSize: 16, weight: .bold)
        percentLabel.textColor = .black
        percentLabel.textAlignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(percentLabel)
        
        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = AppColors.orange
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        cancelButton.layer.cornerRadius = 22
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        containerView.addSubview(cancelButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            statsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            statsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            statsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            progressView.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            progressView.heightAnchor.constraint(equalToConstant: 6),
            
            percentLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            percentLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            percentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            cancelButton.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            cancelButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProgressNotification(_:)),
            name: .satelliteDownloadProgress,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissSelf),
            name: .satelliteDownloadComplete,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissSelf),
            name: .satelliteDownloadFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissSelf),
            name: .satelliteDownloadStopped,
            object: nil
        )
    }
    
    private func updateUI(with info: MapDownloadProgressInfo? = nil) {
        let progressInfo = info ?? SatelliteDownloadManager.shared.restoredProgressInfo()
        
        // 1. Subtitle status
        subtitleLabel.text = progressInfo.status
        
        // 2. Zoom Level
        zoomLabel.text = "Zoom level: z\(progressInfo.zoom)"
        
        // 3. Total Files
        let savedFormatted = formatNumber(progressInfo.totalSaved)
        let targetFormatted = formatNumber(progressInfo.totalTarget)
        totalFilesLabel.text = "Total files: \(savedFormatted) / \(targetFormatted)"
        
        // 4. This Zoom
        let thisZoomSavedFormatted = formatNumber(progressInfo.thisZoomSaved)
        let thisZoomTotalFormatted = formatNumber(progressInfo.thisZoomTotal)
        thisZoomLabel.text = "This zoom: \(thisZoomSavedFormatted) / \(thisZoomTotalFormatted)"
        
        // 5. File Label
        fileLabel.text = "File: \(progressInfo.fileName)"
        
        // 6. Progress and percent text
        let percent = progressInfo.percent
        progressView.progress = Float(percent) / 100.0
        percentLabel.text = "\(percent)%"
    }
    
    @objc private func handleProgressNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            if let info = notification.userInfo?["progressInfo"] as? MapDownloadProgressInfo {
                self?.updateUI(with: info)
            } else {
                self?.updateUI()
            }
        }
    }
    
    @objc private func dismissSelf() {
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: true)
        }
    }
    
    @objc private func cancelTapped() {
        dismissSelf()
    }
    
    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
