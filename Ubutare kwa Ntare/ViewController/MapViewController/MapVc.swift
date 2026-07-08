import MapLibre
import UIKit
import CoreLocation
import MapKit

final class MapVc: UIViewController {
    private var mapView: MLNMapView!
    private var minerals: [MineralsListItem] = []
    private var mineralTypes: [MineralType] = []
    private var isHybridStyle = false
    private var hybridUsesLocalTiles = false
    private var selectedMineral: MineralsListItem?

    // UI
    private let profileButton = UIButton(type: .custom)
    private let searchBarContainer = UIView()
    private let searchField = UITextField()
    private let filterButton = UIButton(type: .custom)
    private let notificationButton = UIButton(type: .custom)
    private let myLocationButton = UIButton(type: .custom)
    private let streetButton = UIButton(type: .custom)
    private let hybridButton = UIButton(type: .custom)
    private let addButton = UIButton(type: .custom)
    private let centerCrosshair = UIView()
    private let filterContainer = UIView()
    private let filterTable = UITableView()
    private let satelliteDownloadBanner = UIView()
    private let satelliteDownloadLabel = UILabel()
    private let circularProgressButton = CircularProgressButton(type: .custom)
    private var selectedFilterTypeId: String?
    private var mineralAnnotations: [MLNPointAnnotation] = []
    private var mockUserLocationAnnotation: MLNPointAnnotation?
    private var hasCompletedInitialStyleLoad = false
    private var isSwitchingStyle = false
    private var savedCameraCenter: CLLocationCoordinate2D?
    private var savedCameraZoom: Double = AppConstants.burundiDefaultZoom
    private var streetStyleReloadToken = 0

    private var activeMineralTypes: [MineralType] {
        mineralTypes.filter { $0.isActive }
    }

    private let role: UserRole?
    private let navigationManager = MapNavigationManager()

    init() {
        role = AuthSessionManager.shared.currentRole
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupMap()
        setupOverlayUI()
        navigationManager.attach(mapView: mapView, hostView: view)
        navigationManager.presenter = self
        navigationManager.onMockLocationUpdated = { [weak self] coordinate in
            self?.updateMockUserLocationAnnotation(to: coordinate)
        }
        loadData()
        LocationService.shared.requestAuthorization()
        LocationService.shared.startUpdating()
        setupMockUserLocationIfNeeded()

        if OfflineNavigationHelper.shared.hasNavigationData() {
            OfflineNavigationHelper.shared.initialize()
            Task { _ = await OfflineNavigationHelper.shared.awaitReady() }
        }

        OfflineMapManager.shared.recoverOfflineStateIfNeeded()
        OfflineMapManager.shared.ensureStreetTileServerRunning()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkConnectivityChanged(_:)),
            name: .networkConnectivityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSatelliteDownloadProgress(_:)),
            name: .satelliteDownloadProgress,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSatelliteDownloadComplete),
            name: .satelliteDownloadComplete,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSatelliteDownloadFailed(_:)),
            name: .satelliteDownloadFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSatelliteDownloadStopped),
            name: .satelliteDownloadStopped,
            object: nil
        )

        SatelliteDownloadManager.shared.resumeIfNeeded()
        restoreSatelliteDownloadUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshMinerals()
        restoreSatelliteDownloadUI()
        showPendingSatelliteCompleteToastIfNeeded()
    }

    private func setupMap() {
        mapView = MLNMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = !LocationService.usesMockLocation
        configureBurundiMapLimits()
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: AppConstants.burundiCenterLat, longitude: AppConstants.burundiCenterLon),
            zoomLevel: AppConstants.burundiDefaultZoom,
            animated: false
        )
        view.addSubview(mapView)
        loadStreetStyle()
    }

    private func configureBurundiMapLimits() {
        mapView.maximumScreenBounds = AppConstants.burundiBounds
        mapView.minimumZoomLevel = isHybridStyle
            ? AppConstants.burundiMinZoomHybrid
            : AppConstants.burundiMinZoom
        mapView.maximumZoomLevel = isHybridStyle
            ? (hybridUsesLocalTiles
                ? OfflineMapManager.shared.offlineSatelliteDisplayMaxZoom()
                : AppConstants.burundiMaxZoomHybrid)
            : AppConstants.burundiMaxZoomStreet
    }

    private func updateStyleButtonColors() {
        streetButton.backgroundColor = isHybridStyle ? .white : AppColors.primary
        hybridButton.backgroundColor = isHybridStyle ? AppColors.primary : .white
    }

    private func clearMarkersForStyleSwitch() {
        guard !mineralAnnotations.isEmpty else { return }
        mapView.removeAnnotations(mineralAnnotations)
        mineralAnnotations.removeAll()
    }

    private func beginStyleSwitch() {
        isSwitchingStyle = true
        savedCameraCenter = mapView.centerCoordinate
        savedCameraZoom = mapView.zoomLevel
        clearMarkersForStyleSwitch()
    }

    private func setupOverlayUI() {
        // Profile
        profileButton.setImage(UIImage(named: "profileicon"), for: .normal)
        profileButton.backgroundColor = .white
        profileButton.layer.cornerRadius = 22
        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)

        // Search bar with filter inside (matches Android searchBarContainer)
        searchBarContainer.backgroundColor = .white
        searchBarContainer.layer.cornerRadius = 8
        searchBarContainer.layer.borderWidth = 1
        searchBarContainer.layer.borderColor = UIColor.systemGray4.cgColor
        searchBarContainer.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholder = "Search coordinates"
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.font = .systemFont(ofSize: 14)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self

        filterButton.setImage(UIImage(named: "filtericon"), for: .normal)
        filterButton.backgroundColor = .clear
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)

        searchBarContainer.addSubview(searchField)
        searchBarContainer.addSubview(filterButton)

        // Notification (super_admin only)
        notificationButton.setImage(UIImage(systemName: "bell.fill"), for: .normal)
        notificationButton.tintColor = AppColors.primary
        notificationButton.backgroundColor = .white
        notificationButton.layer.cornerRadius = 8
        notificationButton.isHidden = !(role?.showsNotifications ?? false)
        notificationButton.translatesAutoresizingMaskIntoConstraints = false
        notificationButton.addTarget(self, action: #selector(notificationsTapped), for: .touchUpInside)

        // Map controls
        myLocationButton.setImage(UIImage(named: "currentlocationicon"), for: .normal)
        myLocationButton.backgroundColor = .white
        myLocationButton.layer.cornerRadius = 22
        myLocationButton.translatesAutoresizingMaskIntoConstraints = false
        myLocationButton.addTarget(self, action: #selector(myLocationTapped), for: .touchUpInside)

        streetButton.setImage(UIImage(named: "normalview"), for: .normal)
        streetButton.backgroundColor = AppColors.primary
        streetButton.layer.cornerRadius = 8
        streetButton.translatesAutoresizingMaskIntoConstraints = false
        streetButton.addTarget(self, action: #selector(streetTapped), for: .touchUpInside)

        hybridButton.setImage(UIImage(named: "satelight"), for: .normal)
        hybridButton.backgroundColor = .white
        hybridButton.layer.cornerRadius = 8
        hybridButton.translatesAutoresizingMaskIntoConstraints = false
        hybridButton.addTarget(self, action: #selector(hybridTapped), for: .touchUpInside)

        // FAB
        addButton.setImage(UIImage(named: "plusicon"), for: .normal)
        addButton.backgroundColor = AppColors.primary
        addButton.layer.cornerRadius = 28
        addButton.isHidden = !(role?.canAddDiscovery ?? false)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        // Center crosshair
        centerCrosshair.backgroundColor = .clear
        centerCrosshair.translatesAutoresizingMaskIntoConstraints = false
        let hLine = UIView()
        hLine.backgroundColor = AppColors.primary
        hLine.translatesAutoresizingMaskIntoConstraints = false
        let vLine = UIView()
        vLine.backgroundColor = AppColors.primary
        vLine.translatesAutoresizingMaskIntoConstraints = false
        centerCrosshair.addSubview(hLine)
        centerCrosshair.addSubview(vLine)

        // Filter dropdown
        filterContainer.backgroundColor = .white
        filterContainer.layer.cornerRadius = 8
        filterContainer.layer.shadowOpacity = 0.2
        filterContainer.layer.shadowRadius = 4
        filterContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        filterContainer.isHidden = true
        filterContainer.translatesAutoresizingMaskIntoConstraints = false
        filterTable.dataSource = self
        filterTable.delegate = self
        filterTable.rowHeight = 44
        filterTable.separatorInset = .zero
        filterTable.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        filterTable.translatesAutoresizingMaskIntoConstraints = false
        filterContainer.addSubview(filterTable)

        satelliteDownloadBanner.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        satelliteDownloadBanner.layer.cornerRadius = 10
        satelliteDownloadBanner.isHidden = true
        satelliteDownloadBanner.translatesAutoresizingMaskIntoConstraints = false
        satelliteDownloadLabel.font = .systemFont(ofSize: 13, weight: .medium)
        satelliteDownloadLabel.textColor = .white
        satelliteDownloadLabel.numberOfLines = 2
        satelliteDownloadLabel.textAlignment = .center
        satelliteDownloadLabel.translatesAutoresizingMaskIntoConstraints = false
        satelliteDownloadBanner.addSubview(satelliteDownloadLabel)

        circularProgressButton.isHidden = true
        circularProgressButton.translatesAutoresizingMaskIntoConstraints = false
        circularProgressButton.addTarget(self, action: #selector(circularProgressButtonTapped), for: .touchUpInside)

        [profileButton, searchBarContainer, notificationButton,
         myLocationButton, streetButton, hybridButton, addButton,
         centerCrosshair, filterContainer, satelliteDownloadBanner, circularProgressButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            profileButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            profileButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            profileButton.widthAnchor.constraint(equalToConstant: 44),
            profileButton.heightAnchor.constraint(equalToConstant: 44),

            searchBarContainer.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),
            searchBarContainer.leadingAnchor.constraint(equalTo: profileButton.trailingAnchor, constant: 8),
            searchBarContainer.trailingAnchor.constraint(equalTo: notificationButton.isHidden
                ? view.trailingAnchor : notificationButton.leadingAnchor, constant: notificationButton.isHidden ? -12 : -8),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 40),

            searchField.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: filterButton.leadingAnchor, constant: -4),
            searchField.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),

            filterButton.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -8),
            filterButton.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 32),
            filterButton.heightAnchor.constraint(equalToConstant: 32),

            notificationButton.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),
            notificationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            notificationButton.widthAnchor.constraint(equalToConstant: 40),
            notificationButton.heightAnchor.constraint(equalToConstant: 40),

            myLocationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            myLocationButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            myLocationButton.widthAnchor.constraint(equalToConstant: 44),
            myLocationButton.heightAnchor.constraint(equalToConstant: 44),

            streetButton.topAnchor.constraint(equalTo: myLocationButton.bottomAnchor, constant: 12),
            streetButton.trailingAnchor.constraint(equalTo: myLocationButton.trailingAnchor),
            streetButton.widthAnchor.constraint(equalToConstant: 40),
            streetButton.heightAnchor.constraint(equalToConstant: 40),

            hybridButton.topAnchor.constraint(equalTo: streetButton.bottomAnchor, constant: 8),
            hybridButton.trailingAnchor.constraint(equalTo: myLocationButton.trailingAnchor),
            hybridButton.widthAnchor.constraint(equalToConstant: 40),
            hybridButton.heightAnchor.constraint(equalToConstant: 40),

            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56),

            centerCrosshair.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            centerCrosshair.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),
            centerCrosshair.widthAnchor.constraint(equalToConstant: 24),
            centerCrosshair.heightAnchor.constraint(equalToConstant: 24),

            hLine.centerYAnchor.constraint(equalTo: centerCrosshair.centerYAnchor),
            hLine.leadingAnchor.constraint(equalTo: centerCrosshair.leadingAnchor),
            hLine.trailingAnchor.constraint(equalTo: centerCrosshair.trailingAnchor),
            hLine.heightAnchor.constraint(equalToConstant: 2),

            vLine.centerXAnchor.constraint(equalTo: centerCrosshair.centerXAnchor),
            vLine.topAnchor.constraint(equalTo: centerCrosshair.topAnchor),
            vLine.bottomAnchor.constraint(equalTo: centerCrosshair.bottomAnchor),
            vLine.widthAnchor.constraint(equalToConstant: 2),

            filterContainer.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 4),
            filterContainer.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor),
            filterContainer.widthAnchor.constraint(equalToConstant: 220),
            filterContainer.heightAnchor.constraint(equalToConstant: 260),

            filterTable.topAnchor.constraint(equalTo: filterContainer.topAnchor, constant: 4),
            filterTable.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            filterTable.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor),
            filterTable.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: -4),

            satelliteDownloadBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            satelliteDownloadBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            satelliteDownloadBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            satelliteDownloadLabel.topAnchor.constraint(equalTo: satelliteDownloadBanner.topAnchor, constant: 10),
            satelliteDownloadLabel.bottomAnchor.constraint(equalTo: satelliteDownloadBanner.bottomAnchor, constant: -10),
            satelliteDownloadLabel.leadingAnchor.constraint(equalTo: satelliteDownloadBanner.leadingAnchor, constant: 12),
            satelliteDownloadLabel.trailingAnchor.constraint(equalTo: satelliteDownloadBanner.trailingAnchor, constant: -12),

            circularProgressButton.centerXAnchor.constraint(equalTo: myLocationButton.centerXAnchor),
            circularProgressButton.bottomAnchor.constraint(equalTo: myLocationButton.topAnchor, constant: -12),
            circularProgressButton.widthAnchor.constraint(equalToConstant: 44),
            circularProgressButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func loadData() {
        mineralTypes = LocalDataStore.shared.getMineralTypes()
        minerals = LocalDataStore.shared.getMinerals()
        refreshMarkers()
        MineralImageLoader.prefetchImages(for: minerals)
        Task { await syncMineralsFromServer() }
    }

    private func refreshMinerals() {
        minerals = LocalDataStore.shared.getMinerals()
        refreshMarkers()
        MineralImageLoader.prefetchImages(for: minerals)
    }

    private func syncMineralsFromServer() async {
        guard let token = AuthSessionManager.shared.token else { return }
        let center = mapView.centerCoordinate
        await MineralsSyncService.shared.syncAll(token: token, latitude: center.latitude, longitude: center.longitude)
        await MainActor.run {
            minerals = LocalDataStore.shared.getMinerals()
            mineralTypes = LocalDataStore.shared.getMineralTypes()
            filterTable.reloadData()
            refreshMarkers()
            MineralImageLoader.prefetchImages(for: minerals)
        }
    }

    private func refreshMarkers() {
        if !mineralAnnotations.isEmpty {
            mapView.removeAnnotations(mineralAnnotations)
            mineralAnnotations.removeAll()
        }

        let filtered = minerals.filter { mineral in
            guard let filterId = selectedFilterTypeId else { return true }
            return mineral.mineralTypeId.id == filterId
        }

        for mineral in filtered where isValidCoordinate(latitude: mineral.latitude, longitude: mineral.longitude) {
            let annotation = MLNPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: mineral.latitude, longitude: mineral.longitude)
            annotation.title = resolvedMineralTypeName(for: mineral)
            annotation.subtitle = mineral.id
            mapView.addAnnotation(annotation)
            mineralAnnotations.append(annotation)
        }
    }

    private func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        (latitude != 0 || longitude != 0) &&
        latitude >= -90 && latitude <= 90 &&
        longitude >= -180 && longitude <= 180
    }

    private func resolvedMineralTypeName(for mineral: MineralsListItem) -> String {
        if !mineral.mineralTypeId.name.isEmpty {
            return mineral.mineralTypeId.name
        }
        return activeMineralTypes.first { $0.id == mineral.mineralTypeId.id }?.name ?? "Mineral"
    }

    private func resolvedMineralTypeColor(for mineral: MineralsListItem) -> String {
        if !mineral.mineralTypeId.color.isEmpty {
            return mineral.mineralTypeId.color
        }
        return activeMineralTypes.first { $0.id == mineral.mineralTypeId.id }?.color ?? "#F4A300"
    }

    private func loadMineralTypesIfNeeded() async {
        guard mineralTypes.isEmpty, let token = AuthSessionManager.shared.token else { return }
        do {
            let response = try await APIClient.shared.getMineralTypes(token: token)
            if response.status, let types = response.result?.mineralTypes {
                LocalDataStore.shared.saveMineralTypes(types)
                await MainActor.run {
                    mineralTypes = types
                    filterTable.reloadData()
                }
            }
        } catch {
            #if DEBUG
            print("Failed to load mineral types for filter: \(error)")
            #endif
        }
    }

    private func applyStreetStyle() {
        guard isHybridStyle else { return }
        beginStyleSwitch()
        isHybridStyle = false
        hybridUsesLocalTiles = false
        updateStyleButtonColors()
        loadStreetStyle(forceReload: true)
    }

    private func applyHybridStyle() {
        guard !isHybridStyle else { return }

        if NetworkMonitor.shared.isConnected {
            loadOnlineHybridStyle()
            return
        }

        OfflineMapManager.shared.recoverSatelliteMapReadyFlagIfNeeded()
        if OfflineMapManager.shared.canDisplayOfflineSatellite() {
            loadOfflineHybridStyle(showOfflineToast: false)
            return
        }

        showToast(AppConstants.MapStyleMessages.satelliteNoInternet)
    }

    private func loadOnlineHybridStyle() {
        guard let hybridStyleURL = HybridMapStyle.onlineEsriStyleFileURL() else {
            showAlert("Satellite map style could not be prepared.")
            return
        }
        beginStyleSwitch()
        isHybridStyle = true
        hybridUsesLocalTiles = false
        updateStyleButtonColors()
        mapView.styleURL = hybridStyleURL
        startSatelliteDownloadIfNeeded()
    }

    private func loadOfflineHybridStyle(showOfflineToast: Bool) {
        guard let styleURL = OfflineMapManager.shared.offlineHybridStyleFileURL() else {
            showToast(AppConstants.MapStyleMessages.mapStyleMissing)
            return
        }

        OfflineMapManager.shared.checkpointSatelliteMbTiles()
        guard OfflineMapManager.shared.ensureSatelliteTileServerRunning() else {
            showToast(AppConstants.MapStyleMessages.mapStyleMissing)
            return
        }
        if OfflineMapManager.shared.canDisplayOfflineStreet() {
            OfflineMapManager.shared.ensureStreetTileServerRunning()
        }

        beginStyleSwitch()
        isHybridStyle = true
        hybridUsesLocalTiles = true
        updateStyleButtonColors()
        configureBurundiMapLimits()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.mapView.styleURL = styleURL
            if showOfflineToast {
                self.showToast(AppConstants.MapStyleMessages.hybridSwitchedToOffline)
            }
        }
        startSatelliteDownloadIfNeeded()
    }

    private func startSatelliteDownloadIfNeeded() {
        guard !OfflineMapManager.shared.isSatelliteFullyDownloaded() else { return }
        guard !SatelliteDownloadManager.shared.isDownloading else { return }
        guard NetworkMonitor.shared.isConnected else { return }
        showToast(AppConstants.MapStyleMessages.satelliteDownloadStarted)
        SatelliteDownloadManager.shared.startIfNeeded()
    }

    private func loadStreetStyle(forceReload: Bool = false) {
        if OfflineMapManager.shared.canDisplayOfflineStreet() {
            loadOfflineStreetStyle()
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            loadOfflineStreetStyle()
            return
        }

        streetStyleReloadToken += 1
        let urlString = forceReload
            ? "\(AppConstants.streetStyleURL)?reload=\(streetStyleReloadToken)"
            : AppConstants.streetStyleURL
        hybridUsesLocalTiles = false
        mapView.styleURL = URL(string: urlString)
    }

    private func loadOfflineStreetStyle() {
        guard OfflineMapManager.shared.canDisplayOfflineStreet() else {
            showToast(AppConstants.MapStyleMessages.mapStyleMissing)
            return
        }

        guard OfflineMapManager.shared.ensureStreetTileServerRunning() else {
            showToast(AppConstants.MapStyleMessages.mapStyleMissing)
            return
        }

        if OfflineMapManager.shared.offlineStreetStyleURL() == nil {
            OfflineMapManager.shared.writeOfflineStreetStyleFile()
        }

        guard let styleURL = OfflineMapManager.shared.offlineStreetStyleURL() else {
            showToast(AppConstants.MapStyleMessages.mapStyleMissing)
            return
        }

        hybridUsesLocalTiles = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.mapView.styleURL = styleURL
        }
    }

    @objc private func handleNetworkConnectivityChanged(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool else { return }
        if connected {
            if isHybridStyle, !hybridUsesLocalTiles { return }
            if !isHybridStyle, !OfflineMapManager.shared.canDisplayOfflineStreet() {
                loadStreetStyle(forceReload: true)
            }
            return
        }

        guard isHybridStyle, !hybridUsesLocalTiles else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.switchToOfflineHybridIfNeeded()
        }
    }

    private func switchToOfflineHybridIfNeeded() {
        guard isHybridStyle, !hybridUsesLocalTiles else { return }
        OfflineMapManager.shared.recoverSatelliteMapReadyFlagIfNeeded()
        guard OfflineMapManager.shared.canDisplayOfflineSatellite() else { return }
        loadOfflineHybridStyle(showOfflineToast: true)
    }

    @objc private func handleSatelliteDownloadProgress(_ notification: Notification) {
        guard let percent = notification.userInfo?["percent"] as? Int,
              let status = notification.userInfo?["status"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateSatelliteDownloadBanner(percent: percent, status: status)
        }
    }

    @objc private func handleSatelliteDownloadComplete() {
        DispatchQueue.main.async { [weak self] in
            self?.hideSatelliteDownloadBanner()
            _ = SatelliteDownloadManager.shared.consumePendingCompleteToast()
            self?.showToast(AppConstants.MapStyleMessages.satelliteDownloadComplete)
            if self?.isHybridStyle == true, self?.hybridUsesLocalTiles == true {
                self?.loadOfflineHybridStyle(showOfflineToast: false)
            }
        }
    }

    @objc private func handleSatelliteDownloadFailed(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.hideSatelliteDownloadBanner()
            if let error = notification.userInfo?["error"] as? String {
                self?.showToast(error)
            }
        }
    }

    @objc private func handleSatelliteDownloadStopped() {
        DispatchQueue.main.async { [weak self] in
            self?.hideSatelliteDownloadBanner()
        }
    }

    private func restoreSatelliteDownloadUI() {
        if OfflineMapManager.shared.isSatelliteFullyDownloaded() {
            hideSatelliteDownloadBanner()
            return
        }

        guard SatelliteDownloadManager.shared.isDownloading
            || MbTilesDownloader.hasPartialSatelliteDownload() else {
            hideSatelliteDownloadBanner()
            return
        }

        let progress = SatelliteDownloadManager.shared.restoredProgress()
        updateSatelliteDownloadBanner(percent: progress.percent, status: progress.status)
    }

    private func showPendingSatelliteCompleteToastIfNeeded() {
        guard SatelliteDownloadManager.shared.consumePendingCompleteToast() else { return }
        hideSatelliteDownloadBanner()
        showToast(AppConstants.MapStyleMessages.satelliteDownloadComplete)
    }

    private func updateSatelliteDownloadBanner(percent: Int, status: String) {
        if percent >= 100 {
            hideSatelliteDownloadBanner()
            return
        }
        circularProgressButton.progress = Float(percent) / 100.0
        circularProgressButton.isHidden = false
        view.bringSubviewToFront(circularProgressButton)
    }

    private func hideSatelliteDownloadBanner() {
        circularProgressButton.isHidden = true
    }

    @objc private func circularProgressButtonTapped() {
        let detailsVC = SatelliteDownloadDetailsViewController()
        detailsVC.modalPresentationStyle = .overFullScreen
        detailsVC.modalTransitionStyle = .crossDissolve
        present(detailsVC, animated: true)
    }

    @objc private func profileTapped() {
        navigationController?.pushViewController(ProfileViewController(), animated: true)
    }

    @objc private func notificationsTapped() {
        navigationController?.pushViewController(NotificationViewController(), animated: true)
    }

    @objc private func filterTapped() {
        Task {
            await loadMineralTypesIfNeeded()
            await MainActor.run {
                mineralTypes = LocalDataStore.shared.getMineralTypes()
                if activeMineralTypes.isEmpty {
                    showAlert("No mineral types to filter")
                    return
                }
                filterTable.reloadData()
                filterContainer.isHidden.toggle()
                if !filterContainer.isHidden {
                    view.bringSubviewToFront(filterContainer)
                }
            }
        }
    }

    @objc private func myLocationTapped() {
        guard let rawLocation = LocationService.shared.effectiveCoordinate
            ?? mapView.userLocation?.coordinate else { return }
        let location = clampedToBurundi(rawLocation)
        mapView.setCenter(location, zoomLevel: max(mapView.zoomLevel, 14), animated: true)
    }

    @objc private func streetTapped() { applyStreetStyle() }
    @objc private func hybridTapped() { applyHybridStyle() }

    @objc private func addTapped() {
        let center = mapView.centerCoordinate
        let sheet = AddMineralSheetViewController(
            latitude: center.latitude,
            longitude: center.longitude,
            mineralTypes: mineralTypes
        ) { [weak self] in
            self?.refreshMinerals()
            Task { await self?.syncMineralsFromServer() }
        }
        if let sheet = sheet.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private func showMineralDetail(_ mineral: MineralsListItem) {
        let canEdit = (role?.canEditOwnDiscovery ?? false)
            && mineral.isOwnedByCurrentUser(currentUserId: AuthSessionManager.shared.userId)
        let sheet = MineralDetailSheetViewController(
            mineral: mineral,
            canEdit: canEdit,
            canGetDirections: true,
            onChanged: { [weak self] in
                self?.refreshMinerals()
                Task { await self?.syncMineralsFromServer() }
            },
            onEdit: canEdit ? { [weak self] in
                self?.presentEditMineralSheet(mineral)
            } : nil,
            onGetDirections: { [weak self] in
                self?.navigationManager.startNavigation(to: mineral)
            }
        )
        if let sheet = sheet.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private func presentEditMineralSheet(_ mineral: MineralsListItem) {
        let sheet = AddMineralSheetViewController(
            latitude: mineral.latitude,
            longitude: mineral.longitude,
            mineralTypes: mineralTypes,
            editingMineral: mineral
        ) { [weak self] in
            self?.refreshMinerals()
            Task { await self?.syncMineralsFromServer() }
        }
        if let sheetController = sheet.sheetPresentationController {
            sheetController.detents = [.medium(), .large()]
            sheetController.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private func mineralForAnnotation(_ annotation: MLNAnnotation) -> MineralsListItem? {
        guard let subtitle = annotation.subtitle??.description else { return nil }
        return minerals.first { $0.id == subtitle }
    }

    private func clampedToBurundi(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, AppConstants.burundiMinLat), AppConstants.burundiMaxLat),
            longitude: min(max(coordinate.longitude, AppConstants.burundiMinLon), AppConstants.burundiMaxLon)
        )
    }
}

extension MapVc: MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        if isSwitchingStyle, let savedCameraCenter {
            let maxZoom = isHybridStyle
                ? (hybridUsesLocalTiles
                    ? OfflineMapManager.shared.offlineSatelliteDisplayMaxZoom()
                    : AppConstants.burundiMaxZoomHybrid)
                : AppConstants.burundiMaxZoomStreet
            let minZoom = isHybridStyle
                ? AppConstants.burundiMinZoomHybrid
                : AppConstants.burundiMinZoom
            let zoom = min(max(savedCameraZoom, minZoom), maxZoom)
            mapView.setCenter(savedCameraCenter, zoomLevel: zoom, animated: false)
            isSwitchingStyle = false
            self.savedCameraCenter = nil
        } else if !hasCompletedInitialStyleLoad {
            hasCompletedInitialStyleLoad = true
            mapView.setCenter(
                CLLocationCoordinate2D(latitude: AppConstants.burundiCenterLat, longitude: AppConstants.burundiCenterLon),
                zoomLevel: AppConstants.burundiDefaultZoom,
                animated: false
            )
        }

        configureBurundiMapLimits()
        navigationManager.registerRouteLayer(style: style)
        refreshMarkers()
    }

    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        let coordinate = LocationService.shared.effectiveCoordinate ?? userLocation?.coordinate
        guard let coordinate else { return }
        navigationManager.userLocationDidUpdate(coordinate)
    }

    private func setupMockUserLocationIfNeeded() {
        guard LocationService.usesMockLocation else { return }
        let annotation = MLNPointAnnotation()
        annotation.coordinate = AppConstants.mockUserLocation
        annotation.title = "You"
        mockUserLocationAnnotation = annotation
        mapView.addAnnotation(annotation)
        navigationManager.userLocationDidUpdate(AppConstants.mockUserLocation)
    }

    private func updateMockUserLocationAnnotation(to coordinate: CLLocationCoordinate2D) {
        guard let annotation = mockUserLocationAnnotation else { return }
        annotation.coordinate = coordinate
        mapView.setCenter(coordinate, zoomLevel: mapView.zoomLevel, animated: true)
    }

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
        #if DEBUG
        print("Map style failed to load: \(error.localizedDescription)")
        #endif
        isSwitchingStyle = false
        savedCameraCenter = nil

        if isHybridStyle {
            hybridUsesLocalTiles = false
            if OfflineMapManager.shared.canDisplayOfflineSatellite() {
                loadOfflineHybridStyle(showOfflineToast: false)
            } else if NetworkMonitor.shared.isConnected {
                loadOnlineHybridStyle()
            } else {
                isHybridStyle = false
                updateStyleButtonColors()
                loadOfflineStreetStyle()
                showToast(AppConstants.MapStyleMessages.satelliteNoInternet)
            }
            return
        }

        if !NetworkMonitor.shared.isConnected || OfflineMapManager.shared.canDisplayOfflineStreet() {
            loadOfflineStreetStyle()
        }
    }

    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        if annotation === mockUserLocationAnnotation {
            let reuseId = "mock-user-location"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
                ?? MLNAnnotationView(reuseIdentifier: reuseId)

            let dotSize: CGFloat = 18
            let dotView: UIView
            if let existing = annotationView.viewWithTag(9002) {
                dotView = existing
            } else {
                dotView = UIView(frame: CGRect(x: 0, y: 0, width: dotSize, height: dotSize))
                dotView.tag = 9002
                dotView.backgroundColor = UIColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1)
                dotView.layer.cornerRadius = dotSize / 2
                dotView.layer.borderColor = UIColor.white.cgColor
                dotView.layer.borderWidth = 3
                annotationView.addSubview(dotView)
            }

            annotationView.bounds = dotView.bounds
            annotationView.centerOffset = .zero
            return annotationView
        }

        guard let mineral = mineralForAnnotation(annotation) else { return nil }

        let hexColor = resolvedMineralTypeColor(for: mineral)
        let reuseId = "mineral-pin-\(hexColor.lowercased())"

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
            ?? MLNAnnotationView(reuseIdentifier: reuseId)

        let image = MineralMarkerRenderer.pinImage(hexColor: hexColor)
        let imageView: UIImageView
        if let existing = annotationView.viewWithTag(9001) as? UIImageView {
            imageView = existing
        } else {
            imageView = UIImageView()
            imageView.tag = 9001
            imageView.contentMode = .scaleAspectFit
            annotationView.addSubview(imageView)
        }

        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        annotationView.bounds = imageView.bounds
        // Pin tip sits at bottom-center; shift anchor so tip lands on the coordinate.
        annotationView.centerOffset = CGVector(dx: 0, dy: image.size.height / 2)

        return annotationView
    }

    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
        if let mineral = mineralForAnnotation(annotation) {
            showMineralDetail(mineral)
        }
        mapView.deselectAnnotation(annotation, animated: false)
    }
}

extension MapVc: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return true }
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              LocationService.shared.isWithinBurundi(latitude: lat, longitude: lon) else {
            showAlert("Enter valid coordinates within Burundi (lat, lon)")
            return true
        }
        mapView.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lon), zoomLevel: 14, animated: true)
        return true
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = "  \(message)  "
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.numberOfLines = 0
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -140),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        UIView.animate(withDuration: 0.25, delay: 2.5, options: [], animations: {
            toast.alpha = 0
        }, completion: { _ in
            toast.removeFromSuperview()
        })
    }
}

extension MapVc: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        activeMineralTypes.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.row == 0 {
            config.text = "All minerals"
        } else {
            let type = activeMineralTypes[indexPath.row - 1]
            config.text = type.name
            config.image = coloredDotImage(hex: type.color)
        }
        cell.contentConfiguration = config
        cell.accessoryType = isFilterSelected(at: indexPath) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectedFilterTypeId = indexPath.row == 0 ? nil : activeMineralTypes[indexPath.row - 1].id
        filterContainer.isHidden = true
        tableView.reloadData()
        refreshMarkers()
    }

    private func isFilterSelected(at indexPath: IndexPath) -> Bool {
        if indexPath.row == 0 {
            return selectedFilterTypeId == nil
        }
        return selectedFilterTypeId == activeMineralTypes[indexPath.row - 1].id
    }

    private func coloredDotImage(hex: String) -> UIImage? {
        let color = UIColor(hex: hex) ?? AppColors.primary
        let size = CGSize(width: 12, height: 12)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

private enum MineralMarkerRenderer {
    private static var imageCache: [String: UIImage] = [:]

    static func pinImage(hexColor: String, width: CGFloat = 48, height: CGFloat = 56) -> UIImage {
        let key = "\(hexColor.lowercased())-\(width)x\(height)"
        if let cached = imageCache[key] {
            return cached
        }

        let fillColor = UIColor(hex: hexColor) ?? AppColors.primary
        let image = drawPinImage(fillColor: fillColor, width: width, height: height)
        imageCache[key] = image
        return image
    }

    private static func drawPinImage(fillColor: UIColor, width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            let scale = height / 50.0
            let horizontalInset = (width - 50 * scale) / 2
            context.cgContext.translateBy(x: horizontalInset, y: 0)

            let pinPath = UIBezierPath()
            pinPath.move(to: CGPoint(x: 37.305 * scale, y: 6.438 * scale))
            pinPath.addCurve(
                to: CGPoint(x: 23.852 * scale, y: 1.602 * scale),
                controlPoint1: CGPoint(x: 33.656 * scale, y: 3.008 * scale),
                controlPoint2: CGPoint(x: 28.875 * scale, y: 1.281 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 7.039 * scale, y: 19.016 * scale),
                controlPoint1: CGPoint(x: 14.688 * scale, y: 2.172 * scale),
                controlPoint2: CGPoint(x: 7.297 * scale, y: 9.82 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 18.016 * scale, y: 36.094 * scale),
                controlPoint1: CGPoint(x: 6.828 * scale, y: 26.484 * scale),
                controlPoint2: CGPoint(x: 11.133 * scale, y: 33.188 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 19.844 * scale, y: 37.648 * scale),
                controlPoint1: CGPoint(x: 18.789 * scale, y: 36.422 * scale),
                controlPoint2: CGPoint(x: 19.414 * scale, y: 36.953 * scale)
            )
            pinPath.addLine(to: CGPoint(x: 24.336 * scale, y: 44.945 * scale))
            pinPath.addCurve(
                to: CGPoint(x: 25.0 * scale, y: 45.32 * scale),
                controlPoint1: CGPoint(x: 24.477 * scale, y: 45.172 * scale),
                controlPoint2: CGPoint(x: 24.727 * scale, y: 45.32 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 25.664 * scale, y: 44.945 * scale),
                controlPoint1: CGPoint(x: 25.274 * scale, y: 45.32 * scale),
                controlPoint2: CGPoint(x: 25.524 * scale, y: 45.18 * scale)
            )
            pinPath.addLine(to: CGPoint(x: 30.156 * scale, y: 37.648 * scale))
            pinPath.addCurve(
                to: CGPoint(x: 31.992 * scale, y: 36.094 * scale),
                controlPoint1: CGPoint(x: 30.578 * scale, y: 36.961 * scale),
                controlPoint2: CGPoint(x: 31.219 * scale, y: 36.422 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 42.969 * scale, y: 19.539 * scale),
                controlPoint1: CGPoint(x: 38.664 * scale, y: 33.273 * scale),
                controlPoint2: CGPoint(x: 42.969 * scale, y: 26.774 * scale)
            )
            pinPath.addCurve(
                to: CGPoint(x: 37.305 * scale, y: 6.438 * scale),
                controlPoint1: CGPoint(x: 42.969 * scale, y: 14.602 * scale),
                controlPoint2: CGPoint(x: 40.906 * scale, y: 9.828 * scale)
            )
            pinPath.close()

            fillColor.setFill()
            pinPath.fill()

            let dotRadius = 10.938 * scale / 2
            let dotCenter = CGPoint(x: 25 * scale, y: 19.531 * scale)
            let dotPath = UIBezierPath(
                arcCenter: dotCenter,
                radius: dotRadius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            UIColor.white.setFill()
            dotPath.fill()
        }
    }
}

final class CircularProgressButton: UIButton {
    private let progressLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let percentLabel = UILabel()
    
    var progress: Float = 0.0 {
        didSet {
            let clamped = max(0.0, min(1.0, progress))
            progressLayer.strokeEnd = CGFloat(clamped)
            percentLabel.text = "\(Int(clamped * 100))%"
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 22
        
        // Shadow to match other map buttons
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        
        // Setup layers
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.systemGray5.cgColor
        trackLayer.lineWidth = 3
        layer.addSublayer(trackLayer)
        
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
        
        // Label
        percentLabel.font = .systemFont(ofSize: 11, weight: .bold)
        percentLabel.textColor = .black
        percentLabel.textAlignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)
        
        NSLayoutConstraint.activate([
            percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (bounds.width - trackLayer.lineWidth) / 2
        let startAngle = -CGFloat.pi / 2
        let endAngle = 3 * CGFloat.pi / 2
        
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }
}
