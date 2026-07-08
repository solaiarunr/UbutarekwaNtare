import CoreLocation
import Foundation

struct CachedNavigationRoute: Codable {
    let cacheKey: String
    let coordinates: [[Double]]
    let distanceMeters: Double
    let expectedTravelTime: Double
    let savedAt: TimeInterval
}

final class NavigationRouteCache {
    static let shared = NavigationRouteCache()

    private let expirySeconds: TimeInterval = 7 * 24 * 60 * 60
    private let defaultsKey = "cached_navigation_routes"
    private let maxEntries = 40

    private init() {}

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> NavigationRoute? {
        let key = cacheKey(from: origin, to: destination)
        var entries = loadEntries()
        guard let index = entries.firstIndex(where: { $0.cacheKey == key }) else {
            return nil
        }

        let entry = entries[index]
        if Date().timeIntervalSince1970 - entry.savedAt > expirySeconds {
            entries.remove(at: index)
            saveEntries(entries)
            return nil
        }

        let coordinates = entry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        guard coordinates.count >= 2 else { return nil }

        return NavigationRoute(
            coordinates: coordinates,
            distanceMeters: entry.distanceMeters,
            expectedTravelTime: entry.expectedTravelTime
        )
    }

    func save(
        _ route: NavigationRoute,
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) {
        guard route.coordinates.count >= 2 else { return }

        let key = cacheKey(from: origin, to: destination)
        let entry = CachedNavigationRoute(
            cacheKey: key,
            coordinates: route.coordinates.map { [$0.latitude, $0.longitude] },
            distanceMeters: route.distanceMeters,
            expectedTravelTime: route.expectedTravelTime,
            savedAt: Date().timeIntervalSince1970
        )

        var entries = loadEntries().filter { $0.cacheKey != key }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveEntries(entries)
    }

    func hasCachedRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Bool {
        route(from: origin, to: destination) != nil
    }

    func cacheKey(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> String {
        String(
            format: "%.5f,%.5f,%.5f,%.5f",
            origin.latitude, origin.longitude,
            destination.latitude, destination.longitude
        )
    }

    private func loadEntries() -> [CachedNavigationRoute] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([CachedNavigationRoute].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries(_ entries: [CachedNavigationRoute]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
