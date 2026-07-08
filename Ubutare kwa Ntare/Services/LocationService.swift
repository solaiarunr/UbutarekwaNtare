import CoreLocation
import Foundation

final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Never>?

    var currentLocation: CLLocationCoordinate2D?

    static var usesMockLocation: Bool {
        #if DEBUG
        return AppConstants.useMockBurundiLocation
        #else
        return false
        #endif
    }

    var effectiveCoordinate: CLLocationCoordinate2D? {
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            return currentLocation ?? AppConstants.mockUserLocation
        }
        #endif
        return currentLocation
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            currentLocation = AppConstants.mockUserLocation
        }
        #endif
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func startUpdating() {
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            currentLocation = AppConstants.mockUserLocation
            return
        }
        #endif
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func resolveLocation() async -> CLLocationCoordinate2D {
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            currentLocation = AppConstants.mockUserLocation
            return AppConstants.mockUserLocation
        }
        #endif
        if let currentLocation { return currentLocation }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestAuthorization()
            manager.requestLocation()
        }
    }

    func isWithinBurundi(latitude: Double, longitude: Double) -> Bool {
        latitude >= AppConstants.burundiMinLat && latitude <= AppConstants.burundiMaxLat &&
        longitude >= AppConstants.burundiMinLon && longitude <= AppConstants.burundiMaxLon
    }

    #if DEBUG
    func setMockCoordinate(_ coordinate: CLLocationCoordinate2D) {
        guard AppConstants.useMockBurundiLocation else { return }
        currentLocation = coordinate
    }

    func resetMockCoordinate() {
        guard AppConstants.useMockBurundiLocation else { return }
        currentLocation = AppConstants.mockUserLocation
    }
    #endif

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            currentLocation = AppConstants.mockUserLocation
            continuation?.resume(returning: AppConstants.mockUserLocation)
            continuation = nil
            return
        }
        #endif
        currentLocation = location.coordinate
        continuation?.resume(returning: location.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        if AppConstants.useMockBurundiLocation {
            currentLocation = AppConstants.mockUserLocation
            continuation?.resume(returning: AppConstants.mockUserLocation)
            continuation = nil
            return
        }
        #endif
        let fallback = CLLocationCoordinate2D(
            latitude: AppConstants.burundiCenterLat,
            longitude: AppConstants.burundiCenterLon
        )
        continuation?.resume(returning: fallback)
        continuation = nil
    }
}
