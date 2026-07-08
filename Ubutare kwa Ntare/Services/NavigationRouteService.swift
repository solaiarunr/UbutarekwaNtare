import CoreLocation
import Foundation
import MapKit

struct NavigationRoute {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

enum NavigationRouteService {
    private static let userAgent = "UbutarekwaNtare/1.0 (iOS)"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetchNavigationRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> NavigationRoute {
        guard isValidCoordinate(origin), isValidCoordinate(destination) else {
            return emptyRoute
        }

        if let cached = NavigationRouteCache.shared.route(from: origin, to: destination) {
            return cached
        }

        let ready = await OfflineNavigationHelper.shared.awaitReady()
        if ready, let offlineRoute = await OfflineNavigationHelper.shared.getRoute(
            from: origin,
            to: destination
        ), offlineRoute.coordinates.count >= 2 {
            return offlineRoute
        }

        return emptyRoute
    }

    static func fetchOnlineDrivingRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> NavigationRoute? {
        guard isValidCoordinate(origin), isValidCoordinate(destination) else { return nil }
        guard NetworkMonitor.shared.isConnected else { return nil }

        if let route = await fetchOSRMRoute(from: origin, to: destination) {
            return route
        }
        if let route = await fetchMKDirections(from: origin, to: destination) {
            return route
        }
        return nil
    }

    static var emptyRoute: NavigationRoute {
        NavigationRoute(coordinates: [], distanceMeters: 0, expectedTravelTime: 0)
    }

    static func fetchCachedRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> NavigationRoute? {
        NavigationRouteCache.shared.route(from: origin, to: destination)
    }

    // MARK: - OSRM (primary — same providers as Android RouteHelper)

    private static func fetchOSRMRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> NavigationRoute? {
        let querySuffix = "overview=full&steps=false&alternatives=false"
        let templates = [
            "https://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?\(querySuffix)&geometries=geojson",
            "https://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?\(querySuffix)&geometries=polyline",
            "https://routing.openstreetmap.de/routed-car/route/v1/driving/%f,%f;%f,%f?\(querySuffix)&geometries=geojson",
            "https://routing.openstreetmap.de/routed-car/route/v1/driving/%f,%f;%f,%f?\(querySuffix)&geometries=polyline"
        ]

        for template in templates {
            let urlString = String(
                format: template,
                origin.longitude, origin.latitude,
                destination.longitude, destination.latitude
            )
            guard let url = URL(string: urlString),
                  let route = await fetchOSRM(url: url) else { continue }
            return route
        }
        return nil
    }

    private static func fetchOSRM(url: URL) async -> NavigationRoute? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200...299).contains(http.statusCode) else {
                #if DEBUG
                print("OSRM HTTP \(http.statusCode) for \(url.host ?? "")")
                #endif
                return nil
            }
            return parseOSRM(data)
        } catch {
            #if DEBUG
            print("OSRM request failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private static func parseOSRM(_ data: Data) -> NavigationRoute? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let code = json["code"] as? String
        guard code == "Ok" else {
            #if DEBUG
            print("OSRM code=\(code ?? "nil") message=\(json["message"] as? String ?? "")")
            #endif
            return nil
        }

        guard let routes = json["routes"] as? [[String: Any]],
              let first = routes.first,
              let geometry = first["geometry"] else {
            return nil
        }

        let points: [CLLocationCoordinate2D]
        if let geoJson = geometry as? [String: Any],
           let coordinates = geoJson["coordinates"] as? [[Double]] {
            points = coordinates.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        } else if let encoded = geometry as? String {
            points = decodePolyline(encoded)
        } else {
            return nil
        }

        guard points.count >= 2 else { return nil }

        let distance = (first["distance"] as? Double) ?? polylineLengthMeters(points)
        let duration = (first["duration"] as? Double) ?? estimateDuration(distanceMeters: distance)
        return NavigationRoute(
            coordinates: points,
            distanceMeters: distance,
            expectedTravelTime: duration
        )
    }

    // MARK: - Apple MapKit

    @MainActor
    private static func fetchMKDirections(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> NavigationRoute? {
        await withCheckedContinuation { continuation in
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .automobile
            request.requestsAlternateRoutes = false

            MKDirections(request: request).calculate { response, error in
                if let error {
                    #if DEBUG
                    print("MKDirections failed: \(error.localizedDescription)")
                    #endif
                }

                guard let route = response?.routes.first,
                      route.polyline.pointCount >= 2 else {
                    continuation.resume(returning: nil)
                    return
                }

                var coordinates = [CLLocationCoordinate2D](
                    repeating: kCLLocationCoordinate2DInvalid,
                    count: route.polyline.pointCount
                )
                route.polyline.getCoordinates(
                    &coordinates,
                    range: NSRange(location: 0, length: route.polyline.pointCount)
                )

                continuation.resume(returning: NavigationRoute(
                    coordinates: coordinates,
                    distanceMeters: route.distance,
                    expectedTravelTime: route.expectedTravelTime
                ))
            }
        }
    }

    // MARK: - Fallback

    static func offlineFallbackRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> NavigationRoute {
        let distance = straightLineDistanceMeters(from: origin, to: destination)
        let coordinates = interpolateCoordinates(from: origin, to: destination, segments: 24)
        return NavigationRoute(
            coordinates: coordinates,
            distanceMeters: distance,
            expectedTravelTime: estimateDuration(distanceMeters: distance)
        )
    }

    private static func buildFallbackRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> NavigationRoute {
        let distance = straightLineDistanceMeters(from: origin, to: destination)
        let coordinates = interpolateCoordinates(from: origin, to: destination, segments: 24)
        return NavigationRoute(
            coordinates: coordinates,
            distanceMeters: distance,
            expectedTravelTime: estimateDuration(distanceMeters: distance)
        )
    }

    private static func interpolateCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        guard segments > 1 else { return [origin, destination] }
        return (0...segments).map { step in
            let fraction = Double(step) / Double(segments)
            return CLLocationCoordinate2D(
                latitude: origin.latitude + (destination.latitude - origin.latitude) * fraction,
                longitude: origin.longitude + (destination.longitude - origin.longitude) * fraction
            )
        }
    }

    // MARK: - Polyline decode (Google/OSRM encoded polyline)

    private static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let characters = Array(encoded.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < characters.count {
            var shift = 0
            var value = 0
            var byte: Int
            repeat {
                guard index < characters.count else { return coordinates }
                byte = Int(characters[index]) - 63
                index += 1
                value |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < characters.count
            let deltaLat = ((value & 1) != 0 ? ~(value >> 1) : (value >> 1))
            latitude += deltaLat

            shift = 0
            value = 0
            repeat {
                guard index < characters.count else { return coordinates }
                byte = Int(characters[index]) - 63
                index += 1
                value |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < characters.count
            let deltaLon = ((value & 1) != 0 ? ~(value >> 1) : (value >> 1))
            longitude += deltaLon

            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(latitude) / 1e5,
                longitude: Double(longitude) / 1e5
            ))
        }
        return coordinates
    }

    // MARK: - Helpers

    static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate) &&
        !(coordinate.latitude == 0 && coordinate.longitude == 0) &&
        coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
        coordinate.longitude >= -180 && coordinate.longitude <= 180
    }

    static func polylineLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 0..<(coordinates.count - 1) {
            let start = CLLocation(latitude: coordinates[index].latitude, longitude: coordinates[index].longitude)
            let end = CLLocation(latitude: coordinates[index + 1].latitude, longitude: coordinates[index + 1].longitude)
            total += start.distance(from: end)
        }
        return total
    }

    static func coordinateAlongRoute(
        _ coordinates: [CLLocationCoordinate2D],
        distanceFromStart: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard let first = coordinates.first else {
            return kCLLocationCoordinate2DInvalid
        }
        guard coordinates.count >= 2, distanceFromStart > 0 else { return first }

        var remaining = distanceFromStart
        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let segmentStart = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let segmentEnd = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let segmentLength = segmentStart.distance(from: segmentEnd)

            if segmentLength == 0 { continue }

            if remaining <= segmentLength {
                let fraction = remaining / segmentLength
                return CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
            }

            remaining -= segmentLength
        }

        return coordinates.last ?? first
    }

    static func straightLineDistanceMeters(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let end = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return start.distance(from: end)
    }

    static func estimateDuration(distanceMeters: CLLocationDistance) -> TimeInterval {
        let speedMps = 35.0 / 3.6
        return max(distanceMeters / speedMps, 1)
    }
}
