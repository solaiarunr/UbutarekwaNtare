import CoreLocation
import MapLibre
import UIKit

final class MapNavigationManager {
    weak var presenter: UIViewController?
    private weak var mapView: MLNMapView?
    private weak var hostView: UIView?

    private let speechService = NavigationSpeechService()
    private let routeSourceId = "direction-route-source"
    private let routeLayerId = "direction-route-layer"

    private let bannerView = UIView()
    private let durationLabel = UILabel()
    private let distanceLabel = UILabel()
    private let stopButton = UIButton(type: .system)

    private var activeRoute: NavigationRoute?
    private var destination: CLLocationCoordinate2D?
    private var destinationMineral: MineralsListItem?
    private var navigationActive = false
    private var announced300 = false
    private var announced200 = false
    private var announced100 = false
    private var announcedArrival = false
    private var updateTimer: Timer?
    private var mockDistanceTraveled: CLLocationDistance = 0

    private let loadingOverlay = UIView()
    private let loadingLabel = UILabel()
    private let loadingSpinner = UIActivityIndicatorView(style: .large)

    var onMockLocationUpdated: ((CLLocationCoordinate2D) -> Void)?

    func attach(mapView: MLNMapView, hostView: UIView) {
        self.mapView = mapView
        self.hostView = hostView
        setupBanner()
        setupLoadingOverlay()
    }

    func registerRouteLayer(style: MLNStyle) {
        if style.source(withIdentifier: routeSourceId) != nil {
            redrawRouteIfNeeded()
            return
        }

        let source = MLNShapeSource(identifier: routeSourceId, shape: nil, options: nil)
        style.addSource(source)

        let layer = MLNLineStyleLayer(identifier: routeLayerId, source: source)
        layer.lineColor = NSExpression(forConstantValue: UIColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1))
        layer.lineWidth = NSExpression(forConstantValue: 6)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(layer)

        redrawRouteIfNeeded()
    }

    func startNavigation(to mineral: MineralsListItem) {
        Task { @MainActor in
            await showDirectionsTo(mineral: mineral)
        }
    }

    func stopNavigation(cancelSpeech: Bool = true) {
        navigationActive = false
        destination = nil
        destinationMineral = nil
        activeRoute = nil
        announced300 = false
        announced200 = false
        announced100 = false
        announcedArrival = false
        mockDistanceTraveled = 0
        updateTimer?.invalidate()
        updateTimer = nil
        if cancelSpeech {
            speechService.stop()
        }
        bannerView.isHidden = true
        clearRoutePolyline()
        #if DEBUG
        if LocationService.usesMockLocation {
            LocationService.shared.resetMockCoordinate()
            onMockLocationUpdated?(AppConstants.mockUserLocation)
        }
        #endif
    }

    func userLocationDidUpdate(_ coordinate: CLLocationCoordinate2D) {
        guard navigationActive else { return }
        updateNavigationProgress(from: coordinate)
    }

    @MainActor
    private func showDirectionsTo(mineral: MineralsListItem) async {
        let destinationCoordinate = CLLocationCoordinate2D(
            latitude: mineral.latitude,
            longitude: mineral.longitude
        )

        guard await hasLocationPermission() else {
            showToast("Waiting for location.")
            LocationService.shared.requestAuthorization()
            return
        }

        if OfflineNavigationHelper.shared.hasNavigationData() {
            await resolveOriginAndDrawRoute(to: destinationCoordinate, mineral: mineral)
            return
        }

        if !NetworkMonitor.shared.isConnected {
            showToast(NavigationMessages.downloadRequiresNetwork)
            return
        }

        showLoadingMessage("Downloading navigation data…")
        let downloaded = await NavigationDataDownloader.downloadIfNeeded { [weak self] percent in
            self?.showLoadingMessage("Downloading navigation… \(percent)%")
        }

        guard downloaded else {
            hideLoadingMessage()
            showToast("Could not download navigation data. Check your connection and try again.")
            return
        }

        OfflineNavigationHelper.shared.initialize()
        let ready = await OfflineNavigationHelper.shared.awaitReady()
        hideLoadingMessage()

        guard ready else {
            showToast(
                OfflineNavigationHelper.shared.lastErrorMessage()
                    ?? "Offline navigation is still preparing. Please wait and try again."
            )
            return
        }

        await resolveOriginAndDrawRoute(to: destinationCoordinate, mineral: mineral)
    }

    @MainActor
    private func resolveOriginAndDrawRoute(
        to destination: CLLocationCoordinate2D,
        mineral: MineralsListItem
    ) async {
        let origin = await resolveOrigin()
        guard NavigationRouteService.isValidCoordinate(origin),
              NavigationRouteService.isValidCoordinate(destination) else {
            showAlert("Invalid route coordinates.")
            return
        }
        await drawRouteFrom(origin: origin, to: destination, mineral: mineral)
    }

    @MainActor
    private func drawRouteFrom(
        origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mineral: MineralsListItem
    ) async {
        if !OfflineNavigationHelper.shared.isReady() {
            showToast("Preparing offline navigation, this may take a minute…")
        } else {
            showToast("Loading route…")
        }

        showLoadingMessage("Loading route…")
        defer { hideLoadingMessage() }

        let route = await withTaskTimeout(seconds: 300) {
            await NavigationRouteService.fetchNavigationRoute(from: origin, to: destination)
        } ?? NavigationRouteService.emptyRoute

        guard route.coordinates.count >= 2 else {
            showToast(NavigationMessages.routeLoadFailureMessage())
            return
        }

        startNavigationWithRoute(route, mineral: mineral)
    }

    private enum NavigationMessages {
        static let downloadRequiresNetwork =
            "Navigation data is missing. Connect to the internet to download it."
        static let navigationDataMissing =
            "Navigation file not found. Connect to the internet and try again."
        static let navigationStillPreparing =
            "Offline navigation is still preparing. Please wait and try again."
        static let routeLoadFailed =
            "Could not load driving route. Check internet or try again."

        static func routeLoadFailureMessage() -> String {
            if !OfflineNavigationHelper.shared.isReady(),
               OfflineNavigationHelper.shared.hasNavigationData() {
                return OfflineNavigationHelper.shared.lastErrorMessage() ?? navigationStillPreparing
            }
            if !OfflineNavigationHelper.shared.hasNavigationData() {
                if !NetworkMonitor.shared.isConnected {
                    return downloadRequiresNetwork
                }
                return navigationDataMissing
            }
            return OfflineNavigationHelper.shared.lastErrorMessage() ?? routeLoadFailed
        }
    }

    private func hasLocationPermission() async -> Bool {
        let status = LocationService.shared.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            LocationService.shared.requestAuthorization()
            return false
        default:
            return false
        }
    }

    private func withTaskTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            for await value in group {
                if let value {
                    group.cancelAll()
                    return value
                }
            }
            return nil
        }
    }

    @MainActor
    private func resolveOrigin() async -> CLLocationCoordinate2D {
        if let mockCoordinate = LocationService.shared.effectiveCoordinate,
           LocationService.usesMockLocation {
            return mockCoordinate
        }
        if let userCoordinate = mapView?.userLocation?.coordinate {
            return userCoordinate
        }
        if let cachedCoordinate = LocationService.shared.currentLocation {
            return cachedCoordinate
        }
        return await LocationService.shared.resolveLocation()
    }

    private func startNavigationWithRoute(_ route: NavigationRoute, mineral: MineralsListItem) {
        let destinationCoordinate = CLLocationCoordinate2D(
            latitude: mineral.latitude,
            longitude: mineral.longitude
        )

        stopNavigation()

        navigationActive = true
        destination = destinationCoordinate
        destinationMineral = mineral
        activeRoute = route
        mockDistanceTraveled = 0

        drawRoutePolyline(route.coordinates)
        fitMapToRoute(route.coordinates)

        let initialRemaining = route.distanceMeters
        showBanner(remainingMeters: initialRemaining, route: route)
        speechService.speak("Start")

        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.tickNavigationProgress()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func tickNavigationProgress() {
        #if DEBUG
        if LocationService.usesMockLocation, let route = activeRoute {
            mockDistanceTraveled += AppConstants.mockNavigationStepMeters
            let totalRouteMeters = NavigationRouteService.polylineLengthMeters(route.coordinates)
            let advanced: CLLocationCoordinate2D
            if mockDistanceTraveled >= totalRouteMeters, let destination {
                advanced = destination
            } else {
                advanced = NavigationRouteService.coordinateAlongRoute(
                    route.coordinates,
                    distanceFromStart: mockDistanceTraveled
                )
            }
            LocationService.shared.setMockCoordinate(advanced)
            onMockLocationUpdated?(advanced)
            updateNavigationProgress(from: advanced)
            return
        }
        #endif

        guard let current = LocationService.shared.effectiveCoordinate
            ?? mapView?.userLocation?.coordinate
            ?? LocationService.shared.currentLocation else { return }
        updateNavigationProgress(from: current)
    }

    private func updateNavigationProgress(from current: CLLocationCoordinate2D) {
        guard navigationActive, let destination, let route = activeRoute else { return }

        let remainingMeters = NavigationRouteService.straightLineDistanceMeters(
            from: current,
            to: destination
        )
        showBanner(remainingMeters: remainingMeters, route: route)
        announceDistanceIfNeeded(remainingMeters)

        if remainingMeters < AppConstants.navigationArrivalRadiusMeters, !announcedArrival {
            handleNavigationArrival()
        }
    }

    private func handleNavigationArrival() {
        guard let mineral = destinationMineral else { return }
        announcedArrival = true
        stopNavigation(cancelSpeech: false)
        speechService.speak("You have reached your destination.")
        showDestinationArrivalDialog(for: mineral)
    }

    private func announceDistanceIfNeeded(_ distanceMeters: CLLocationDistance) {
        if !announced300, distanceMeters < 300 {
            announced300 = true
            speechService.speak("In 300 meters, you will reach your destination.")
        }
        if !announced200, distanceMeters < 200 {
            announced200 = true
            speechService.speak("In 200 meters, you will reach your destination.")
        }
        if !announced100, distanceMeters < 100 {
            announced100 = true
            speechService.speak("In 100 meters, you will reach your destination.")
        }
    }

    private func showDestinationArrivalDialog(for mineral: MineralsListItem) {
        guard let presenter else { return }
        let dialog = DestinationArrivalViewController(mineral: mineral)
        presenter.present(dialog, animated: true)
    }

    private func showBanner(remainingMeters: CLLocationDistance, route: NavigationRoute) {
        let remainingSeconds = remainingDurationSeconds(
            remainingMeters: remainingMeters,
            route: route
        )
        durationLabel.text = formatDuration(remainingSeconds)
        distanceLabel.text = "\(formatDistance(remainingMeters)) · \(formatArrivalTime(remainingSeconds))"
        bannerView.isHidden = false
        hostView?.bringSubviewToFront(bannerView)
    }

    private func remainingDurationSeconds(
        remainingMeters: CLLocationDistance,
        route: NavigationRoute
    ) -> TimeInterval {
        guard route.distanceMeters > 0, route.expectedTravelTime > 0 else {
            return NavigationRouteService.estimateDuration(distanceMeters: remainingMeters)
        }
        let ratio = min(max(remainingMeters / route.distanceMeters, 0), 1)
        return route.expectedTravelTime * ratio
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(max(0, Int(meters.rounded()))) m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds + 59) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(totalMinutes) min"
    }

    private func formatArrivalTime(_ remainingSeconds: TimeInterval) -> String {
        let arrival = Date().addingTimeInterval(remainingSeconds)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrival)
    }

    private func drawRoutePolyline(_ coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2,
              let mapView,
              let style = mapView.style,
              let source = style.source(withIdentifier: routeSourceId) as? MLNShapeSource else { return }

        var mutableCoordinates = coordinates
        let polyline = MLNPolyline(coordinates: &mutableCoordinates, count: UInt(mutableCoordinates.count))
        source.shape = polyline
    }

    private func clearRoutePolyline() {
        guard let mapView,
              let style = mapView.style,
              let source = style.source(withIdentifier: routeSourceId) as? MLNShapeSource else { return }
        source.shape = nil
    }

    private func redrawRouteIfNeeded() {
        guard let coordinates = activeRoute?.coordinates, coordinates.count >= 2 else { return }
        drawRoutePolyline(coordinates)
    }

    private func fitMapToRoute(_ coordinates: [CLLocationCoordinate2D]) {
        guard let mapView, let first = coordinates.first else { return }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        )
        mapView.setVisibleCoordinateBounds(
            bounds,
            edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 160, right: 40),
            animated: true
        )
    }

    private func setupBanner() {
        guard let hostView else { return }

        bannerView.backgroundColor = .white
        bannerView.layer.cornerRadius = 12
        bannerView.layer.shadowColor = UIColor.black.cgColor
        bannerView.layer.shadowOpacity = 0.15
        bannerView.layer.shadowRadius = 6
        bannerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        bannerView.isHidden = true
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = .boldSystemFont(ofSize: 22)
        durationLabel.textColor = .black
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        distanceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        distanceLabel.textColor = AppColors.gray
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false

        stopButton.setTitle("Stop", for: .normal)
        stopButton.setTitleColor(AppColors.red, for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [durationLabel, distanceLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        bannerView.addSubview(textStack)
        bannerView.addSubview(stopButton)
        hostView.addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor, constant: 12),
            bannerView.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -88),

            textStack.topAnchor.constraint(equalTo: bannerView.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -12),

            stopButton.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor),
            stopButton.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -12)
        ])
    }

    @objc private func stopTapped() {
        stopNavigation()
    }

    private func showAlert(_ message: String) {
        guard let presenter else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        guard let hostView else { return }
        let toast = UILabel()
        toast.text = message
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.numberOfLines = 0
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false

        hostView.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -140),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -24)
        ])

        UIView.animate(withDuration: 0.25, delay: 2.0, options: [], animations: {
            toast.alpha = 0
        }, completion: { _ in
            toast.removeFromSuperview()
        })
    }

    private func setupLoadingOverlay() {
        guard let hostView else { return }

        loadingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        loadingOverlay.isHidden = true
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false

        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [loadingSpinner, loadingLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        loadingOverlay.addSubview(stack)
        hostView.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor)
        ])
    }

    private func showLoadingMessage(_ message: String) {
        loadingLabel.text = message
        loadingOverlay.isHidden = false
        loadingSpinner.startAnimating()
        hostView?.bringSubviewToFront(loadingOverlay)
    }

    private func hideLoadingMessage() {
        loadingSpinner.stopAnimating()
        loadingOverlay.isHidden = true
    }
}
