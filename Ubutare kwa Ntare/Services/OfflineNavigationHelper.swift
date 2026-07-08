import CoreLocation
import Foundation

/// iOS counterpart to Android [OfflineRouteHelper] — navigation file + routing readiness.
final class OfflineNavigationHelper {
    static let shared = OfflineNavigationHelper()

    private static let osmFileName = "burundi.osm.pbf"
    private static let minOsmBytes: Int64 = 5 * 1024 * 1024

    private var lastError: String?
    private var isPrepared = false
    private var preparationTask: Task<Bool, Never>?

    private init() {}

    func hasNavigationData() -> Bool {
        resolveOsmFileURL() != nil
    }

    func isReady() -> Bool {
        isPrepared
    }

    func lastErrorMessage() -> String? {
        lastError
    }

    func navigationOsmFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("graphhopper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(Self.osmFileName)
    }

    func initialize() {
        guard hasNavigationData() else {
            lastError = "Navigation map file not found. Finish download on the setup screen."
            return
        }
        guard !isPrepared else { return }
        guard preparationTask == nil else { return }

        preparationTask = Task {
            let success = await prepareNavigationEngine()
            await MainActor.run {
                self.isPrepared = success
                self.preparationTask = nil
            }
            return success
        }
    }

    func awaitReady(timeout: TimeInterval = 300) async -> Bool {
        if isPrepared { return true }
        guard hasNavigationData() else {
            lastError = "Navigation map file not found. Finish download on the setup screen."
            return false
        }
        initialize()
        guard let preparationTask else { return false }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await preparationTask.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    func getRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> NavigationRoute? {
        guard isPrepared else { return nil }

        if NetworkMonitor.shared.isConnected {
            if let route = await NavigationRouteService.fetchOnlineDrivingRoute(
                from: origin,
                to: destination
            ) {
                NavigationRouteCache.shared.save(route, from: origin, to: destination)
                return route
            }
            return nil
        }

        guard hasNavigationData() else { return nil }

        let route = NavigationRouteService.offlineFallbackRoute(from: origin, to: destination)
        NavigationRouteCache.shared.save(route, from: origin, to: destination)
        return route
    }

    private func resolveOsmFileURL() -> URL? {
        let canonical = navigationOsmFileURL()
        if fileIsValid(canonical) { return canonical }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidates = [
            documents.appendingPathComponent(Self.osmFileName),
            documents.appendingPathComponent("graphhopper").appendingPathComponent(Self.osmFileName)
        ]
        guard let found = candidates.first(where: { fileIsValid($0) }) else { return nil }

        do {
            if FileManager.default.fileExists(atPath: canonical.path) {
                try FileManager.default.removeItem(at: canonical)
            }
            try FileManager.default.copyItem(at: found, to: canonical)
            return canonical
        } catch {
            return found
        }
    }

    private func fileIsValid(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else { return false }
        return size >= Self.minOsmBytes
    }

    private func prepareNavigationEngine() async -> Bool {
        guard resolveOsmFileURL() != nil else {
            lastError = "Navigation map file not found. Finish download on the setup screen."
            return false
        }

        // GraphHopper is Android-only; on iOS we validate the same navigation file is present.
        lastError = nil
        return true
    }
}
