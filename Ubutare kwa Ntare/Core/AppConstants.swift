import CoreLocation
import Foundation
import MapLibre

enum AppConstants {
    static let baseURL = "https://appservices.hitasoft.in:4000/"
    static let deviceTypeIOS = 2
    static let splashMinDuration: TimeInterval = 1.2

    static let streetStyleURL = "https://tiles.openfreemap.org/styles/bright"
    static let hybridStyleURL = "https://api.maptiler.com/maps/hybrid/style.json?key=OXeyRGPkJZNTw947HZ4k"

    enum MapStyleMessages {
        static let satelliteNoInternet =
            "No internet connection. Connect to Wi‑Fi or mobile data, then try Hybrid again."
        static let mapStyleMissing =
            "Map style file is missing. Please download the street map again."
        static let hybridSwitchedToOffline =
            "Offline hybrid map is now active."
        static let satelliteDownloadStarted =
            "Satellite map download started. Check the notification for progress."
        static let satelliteDownloadComplete =
            "Satellite map ready."
    }

    static let burundiMinLat = -5.50
    static let burundiMaxLat = -1.00
    static let burundiMinLon = 28.50
    static let burundiMaxLon = 31.50
    static let burundiCenterLat = -3.4
    static let burundiCenterLon = 29.9

    #if DEBUG
    /// Set to `true` to simulate being in Burundi while developing outside the country.
    static let useMockBurundiLocation = true
    static let mockUserLocationLat = -3.3822
    static let mockUserLocationLon = 29.3644

    static var mockUserLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: mockUserLocationLat, longitude: mockUserLocationLon)
    }

  /// How far the mock user moves along the route every navigation tick (DEBUG only).
    static let mockNavigationStepMeters: CLLocationDistance = 4000
    #endif

    static let navigationArrivalRadiusMeters: CLLocationDistance = 10
    static let burundiDefaultZoom: Double = 8.5
    static let burundiMinZoom: Double = 7.0
    static let burundiMinZoomHybrid: Double = 3.0
    //mapzoom14.0
    static let burundiMaxZoomStreet: Double = 16.0
    static let burundiMaxZoomHybrid: Double = 18.0

    static var burundiBounds: MLNCoordinateBounds {
        MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: burundiMinLat, longitude: burundiMinLon),
            ne: CLLocationCoordinate2D(latitude: burundiMaxLat, longitude: burundiMaxLon)
        )
    }
}

enum UserRole: String {
    case superAdmin = "super_admin"
    case admin = "admin"
    case mineralExplorer = "mineral_explorer"
    case mineralSiteVisitor = "mineral_site_visitor"

    var displayName: String {
        switch self {
        case .superAdmin: return "Super Admin"
        case .admin: return "Admin"
        case .mineralExplorer: return "Mineral Explorer"
        case .mineralSiteVisitor: return "Mineral Site Visitor"
        }
    }

    var canAddDiscovery: Bool {
        switch self {
        case .admin, .mineralExplorer: return true
        default: return false
        }
    }

    var canEditOwnDiscovery: Bool {
        switch self {
        case .superAdmin, .admin, .mineralExplorer: return true
        default: return false
        }
    }

    var showsBottomNav: Bool {
        self == .superAdmin
    }

    var showsNotifications: Bool {
        self == .superAdmin
    }

    var skipsPushNotifications: Bool {
        self == .mineralSiteVisitor
    }

    static func from(_ raw: String?) -> UserRole? {
        guard let raw else { return nil }
        return UserRole(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
