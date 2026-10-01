import Foundation
import SQLite3

/// Offline street map paths, readiness flags, and style generation (Android `OfflineMapManager`).
final class OfflineMapManager {
    static let shared = OfflineMapManager()

    static let streetsMBTilesFileName = "burundi_streets.mbtiles"
    static let satelliteMBTilesFileName = "burundi_satellite.mbtiles"
    static let streetStyleFileName = "burundi_street_style.json"
    static let hybridStyleFileName = "burundi_hybrid_style.json"
    static let styleCacheFileName = "bright_style_cache.json"
    static let tileServerStreetPort: UInt16 = 7070
    static let tileServerSatellitePort: UInt16 = 7071

    static let minZoom = 7
    //mapzoom 14
    static let maxZoomStreetsOffline = 14
    static let maxZoomSatelliteOffline = 14
    static let maxZoomHybridLabels = 14
    
    static let minSatelliteZoomReady = 14
    static let minTileCount = 20

    static let openFreeMapVectorTileURL =
        "https://tiles.openfreemap.org/planet/20260607_080001_pt/{z}/{x}/{y}.pbf"
    static let esriWorldImageryTileURL =
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    static let openFreeMapGlyphsURL =
        "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"

    private let streetReadyKey = "street_ready"
    private let satelliteReadyKey = "satellite_ready"
    private let satelliteDownloadingKey = "satellite_downloading"
    private let offlineSetupDownloadingKey = "offline_setup_downloading"

    private init() {}

    // MARK: - Paths

    func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func streetsMbTilesURL() -> URL {
        documentsDirectory().appendingPathComponent(Self.streetsMBTilesFileName)
    }

    func satelliteMbTilesURL() -> URL {
        documentsDirectory().appendingPathComponent(Self.satelliteMBTilesFileName)
    }

    func streetStyleFileURL() -> URL {
        documentsDirectory().appendingPathComponent(Self.streetStyleFileName)
    }

    func hybridStyleFileURL() -> URL {
        documentsDirectory().appendingPathComponent(Self.hybridStyleFileName)
    }

    func styleCacheFileURL() -> URL {
        documentsDirectory().appendingPathComponent(Self.styleCacheFileName)
    }

    func offlineStreetStyleURL() -> URL? {
        styleFileURLIfValid(streetStyleFileURL())
    }

    func offlineHybridStyleURL() -> URL? {
        styleFileURLIfValid(hybridStyleFileURL())
    }

    private func styleFileURLIfValid(_ file: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: file.path),
              fileSize(file) ?? 0 > 100 else {
            return nil
        }
        return file
    }

    // MARK: - Readiness

    var isStreetReady: Bool {
        get { UserDefaults.standard.bool(forKey: streetReadyKey) }
        set { UserDefaults.standard.set(newValue, forKey: streetReadyKey) }
    }

    var isSatelliteReady: Bool {
        get { UserDefaults.standard.bool(forKey: satelliteReadyKey) }
        set { UserDefaults.standard.set(newValue, forKey: satelliteReadyKey) }
    }

    var isSatelliteDownloading: Bool {
        get { UserDefaults.standard.bool(forKey: satelliteDownloadingKey) }
        set { UserDefaults.standard.set(newValue, forKey: satelliteDownloadingKey) }
    }

    var isOfflineSetupDownloading: Bool {
        get { UserDefaults.standard.bool(forKey: offlineSetupDownloadingKey) }
        set { UserDefaults.standard.set(newValue, forKey: offlineSetupDownloadingKey) }
    }

    func isStreetFullyDownloaded() -> Bool {
        MbTilesDownloader.isBurundiStreetMapComplete(file: streetsMbTilesURL())
    }

    func canDisplayOfflineStreet() -> Bool {
        let file = streetsMbTilesURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        return MbTilesDownloader.countTiles(in: file) >= Self.minTileCount
    }

    func canDisplayOfflineSatellite() -> Bool {
        let file = satelliteMbTilesURL()
        guard FileManager.default.fileExists(atPath: file.path),
              (fileSize(file) ?? 0) > 4_096 else { return false }
        guard MbTilesDownloader.countTiles(in: file) >= Self.minTileCount else { return false }
        return offlineSatelliteNativeMaxZoom() >= Self.minZoom
    }

    func isSatelliteFullyDownloaded() -> Bool {
        guard canDisplayOfflineSatellite() else { return false }
        return offlineSatelliteNativeMaxZoom() >= Self.maxZoomSatelliteOffline
    }

    func isSatelliteMapReady() -> Bool {
        canDisplayOfflineSatellite() && isSatelliteReady
    }

    func offlineSatelliteNativeMaxZoom() -> Int {
        let file = satelliteMbTilesURL()
        return MbTilesDownloader.readMbTilesActualMaxZoom(file: file)
            ?? MbTilesDownloader.readMbTilesMaxZoom(file: file)
            ?? Self.minSatelliteZoomReady
    }

    func offlineSatelliteDisplayMaxZoom() -> Double {
        Double(Self.maxZoomSatelliteOffline)
    }

    func isOfflineSetupComplete() -> Bool {
        guard AuthSessionManager.shared.isOfflineSetupComplete else { return false }
        return isStreetFullyDownloaded()
    }

    func isFullOfflineSetupComplete() -> Bool {
        isStreetFullyDownloaded() && OfflineNavigationHelper.shared.hasNavigationData()
    }

    func clearOfflineSetupCompleteIfIncomplete() {
        if !isStreetFullyDownloaded() {
            AuthSessionManager.shared.isOfflineSetupComplete = false
            isStreetReady = false
        }
    }

    func markStreetReady() {
        isStreetReady = true
    }

    func markSatelliteReady() {
        isSatelliteReady = true
    }

    func markOfflineSetupComplete() {
        AuthSessionManager.shared.isOfflineSetupComplete = true
    }

    func clearStreetReadyIfIncomplete() {
        if isStreetReady, !isStreetFullyDownloaded() {
            isStreetReady = false
        }
    }

    func recoverOfflineStateIfNeeded() {
        if isStreetFullyDownloaded() {
            if !isStreetReady { markStreetReady() }
            if !AuthSessionManager.shared.isOfflineSetupComplete { markOfflineSetupComplete() }
            if offlineStreetStyleURL() == nil {
                writeOfflineStreetStyleFile()
            }
        }
        recoverSatelliteMapReadyFlagIfNeeded()
    }

    func recoverSatelliteMapReadyFlagIfNeeded() {
        guard !isSatelliteMapReady() else { return }
        guard canDisplayOfflineSatellite() else { return }
        markSatelliteReady()
        writeOfflineHybridStyleFile()
    }

    func checkpointSatelliteMbTiles() {
        let file = satelliteMbTilesURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else { return }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close(db)
    }

    func ensureStreetTileServerRunning() -> Bool {
        guard canDisplayOfflineStreet() else { return false }
        return MBTilesServer.street.start(mbtilesPath: streetsMbTilesURL())
    }

    func ensureSatelliteTileServerRunning() -> Bool {
        guard canDisplayOfflineSatellite() else { return false }
        return MBTilesServer.satellite.start(mbtilesPath: satelliteMbTilesURL())
    }

    // MARK: - Style

    func cacheBrightStyleIfNeeded() async {
        let cache = styleCacheFileURL()
        if let size = fileSize(cache), size > 8_000 { return }
        guard NetworkMonitor.shared.isConnected,
              let json = await fetchStyleJSON(from: AppConstants.streetStyleURL) else {
            return
        }
        try? json.write(to: cache, atomically: true, encoding: .utf8)
    }

    func writeOfflineStreetStyleFile() {
        let json = buildOfflineStreetStyleJSON()
        try? json.write(to: streetStyleFileURL(), atomically: true, encoding: .utf8)
    }

    func writeOfflineHybridStyleFile() {
        let json = buildOfflineHybridStyleJSON()
        try? json.write(to: hybridStyleFileURL(), atomically: true, encoding: .utf8)
    }

    func getOfflineHybridStyleJSON() -> String? {
        if let file = offlineHybridStyleURL(),
           let json = try? String(contentsOf: file, encoding: .utf8),
           isCurrentOfflineHybridStyle(json) {
            return json
        }
        guard canDisplayOfflineSatellite() else { return nil }
        let json = buildOfflineHybridStyleJSON()
        try? json.write(to: hybridStyleFileURL(), atomically: true, encoding: .utf8)
        return json
    }

    func offlineHybridStyleFileURL() -> URL? {
        guard let json = getOfflineHybridStyleJSON() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ubutare-offline-hybrid-style.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func buildOfflineStreetStyleJSON() -> String {
        let localTiles = "http://127.0.0.1:\(Self.tileServerStreetPort)/tiles/{z}/{x}/{y}.pbf"

        if let template = readBrightStyleTemplate(),
           let patched = patchStyleJSON(template, localTiles: localTiles, name: "Burundi Offline Street (Bright)") {
            return patched
        }

        if let bundled = readBundledOfflineStreetStyle(),
           let patched = patchStyleJSON(bundled, localTiles: localTiles, name: "Burundi Offline Street") {
            return patched
        }

        return fallbackStreetStyleJSON(localTiles: localTiles)
    }

    func buildOfflineHybridStyleJSON() -> String {
        let localSatellite =
            "http://127.0.0.1:\(Self.tileServerSatellitePort)/tiles/{z}/{x}/{y}.jpg"
        let localLabelTiles =
            "http://127.0.0.1:\(Self.tileServerStreetPort)/tiles/{z}/{x}/{y}.pbf"
        let nativeMax = offlineSatelliteNativeMaxZoom()
            .clamped(to: Self.minZoom...Self.maxZoomSatelliteOffline)
        let useLabels = canDisplayOfflineStreet()

        var sources: [String: Any] = [
            "esri-satellite": [
                "type": "raster",
                "tiles": [localSatellite],
                "scheme": "xyz",
                "tileSize": 256,
                "minzoom": Self.minZoom,
                "maxzoom": nativeMax,
                "bounds": [AppConstants.burundiMinLon, AppConstants.burundiMinLat,
                           AppConstants.burundiMaxLon, AppConstants.burundiMaxLat]
            ] as [String: Any]
        ]

        var layers: [[String: Any]] = [
            [
                "id": "esri-satellite-layer",
                "type": "raster",
                "source": "esri-satellite",
                "maxzoom": Self.maxZoomSatelliteOffline
            ] as [String: Any]
        ]

        if useLabels {
            sources["osm-labels"] = [
                "type": "vector",
                "tiles": [localLabelTiles],
                "scheme": "xyz",
                "minzoom": Self.minZoom,
                "maxzoom": Self.maxZoomHybridLabels,
                "bounds": [AppConstants.burundiMinLon, AppConstants.burundiMinLat,
                           AppConstants.burundiMaxLon, AppConstants.burundiMaxLat]
            ] as [String: Any]
            layers.append(contentsOf: hybridLabelLayers(source: "osm-labels"))
        }

        let style: [String: Any] = [
            "version": 8,
            "name": "Burundi Hybrid Offline",
            "glyphs": Self.openFreeMapGlyphsURL,
            "sources": sources,
            "layers": layers
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: style, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func isCurrentOfflineHybridStyle(_ json: String) -> Bool {
        json.contains("127.0.0.1:\(Self.tileServerSatellitePort)")
            && json.contains("esri-satellite")
            && json.contains("256")
    }

    private func hybridLabelLayers(source: String) -> [[String: Any]] {
        [
            hybridPlaceLayer(id: "hybrid-place-country", source: source, placeClass: "country", textSize: 14, minZoom: Self.minZoom),
            hybridPlaceLayer(id: "hybrid-place-state", source: source, placeClass: "state", textSize: 13, minZoom: Self.minZoom),
            hybridPlaceLayer(id: "hybrid-place-city", source: source, placeClass: "city", textSize: 15, minZoom: 6),
            hybridPlaceLayer(id: "hybrid-place-town", source: source, placeClass: "town", textSize: 13, minZoom: 8),
            hybridSmallPlaceLayer(id: "hybrid-place-village", source: source, minZoom: 9),
            hybridRoadLabelLayer(id: "hybrid-road-label", source: source, minZoom: 11),
            hybridWaterLabelLayer(id: "hybrid-water-label", source: source, minZoom: 10)
        ]
    }

    private func hybridPlaceLayer(
        id: String, source: String, placeClass: String, textSize: Int, minZoom: Int
    ) -> [String: Any] {
        [
            "id": id,
            "type": "symbol",
            "source": source,
            "source-layer": "place",
            "minzoom": minZoom,
            "filter": ["==", ["get", "class"], placeClass],
            "layout": [
                "text-field": ["coalesce", ["get", "name:latin"], ["get", "name"]],
                "text-font": ["Noto Sans Regular"],
                "text-size": textSize,
                "text-allow-overlap": true,
                "text-ignore-placement": true
            ],
            "paint": [
                "text-color": "#ffffff",
                "text-halo-color": "rgba(0, 0, 0, 0.95)",
                "text-halo-width": 3
            ]
        ]
    }

    private func hybridSmallPlaceLayer(id: String, source: String, minZoom: Int) -> [String: Any] {
        [
            "id": id,
            "type": "symbol",
            "source": source,
            "source-layer": "place",
            "minzoom": minZoom,
            "filter": ["in", ["get", "class"], ["literal", ["village", "hamlet", "locality", "suburb", "neighbourhood", "isolated_dwelling"]]],
            "layout": [
                "text-field": ["coalesce", ["get", "name:latin"], ["get", "name"]],
                "text-font": ["Noto Sans Regular"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 9, 11, 13, 13, 16, 15],
                "text-allow-overlap": true,
                "text-ignore-placement": true
            ],
            "paint": [
                "text-color": "#ffffff",
                "text-halo-color": "rgba(0, 0, 0, 0.95)",
                "text-halo-width": 3
            ]
        ]
    }

    private func hybridRoadLabelLayer(id: String, source: String, minZoom: Int) -> [String: Any] {
        [
            "id": id,
            "type": "symbol",
            "source": source,
            "source-layer": "transportation_name",
            "minzoom": minZoom,
            "layout": [
                "symbol-placement": "line",
                "text-field": ["coalesce", ["get", "name:latin"], ["get", "name"]],
                "text-font": ["Noto Sans Regular"],
                "text-size": 12
            ],
            "paint": [
                "text-color": "#ffffff",
                "text-halo-color": "rgba(0, 0, 0, 0.95)",
                "text-halo-width": 2
            ]
        ]
    }

    private func hybridWaterLabelLayer(id: String, source: String, minZoom: Int) -> [String: Any] {
        [
            "id": id,
            "type": "symbol",
            "source": source,
            "source-layer": "water_name",
            "minzoom": minZoom,
            "layout": [
                "text-field": ["coalesce", ["get", "name:latin"], ["get", "name"]],
                "text-font": ["Noto Sans Regular"],
                "text-size": 12
            ],
            "paint": [
                "text-color": "#d0ecff",
                "text-halo-color": "rgba(0, 0, 0, 0.85)",
                "text-halo-width": 2
            ]
        ]
    }

    func readBrightStyleTemplate() -> String? {
        let cache = styleCacheFileURL()
        if let size = fileSize(cache), size > 8_000,
           let text = try? String(contentsOf: cache, encoding: .utf8) {
            return text
        }
        return readBundledAsset(named: "openfreemap_bright_style")
    }

    func readBundledOfflineStreetStyle() -> String? {
        readBundledAsset(named: "burundi_offline_street")
    }

    // MARK: - Private

    private func readBundledAsset(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func fetchStyleJSON(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("UbutarekwaNtare/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func patchStyleJSON(_ raw: String, localTiles: String, name: String) -> String? {
        guard var root = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            return nil
        }

        root["name"] = name
        if root["glyphs"] == nil {
            root["glyphs"] = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
        }

        if var sources = root["sources"] as? [String: Any] {
            for (key, value) in sources {
                guard var source = value as? [String: Any],
                      source["type"] as? String == "vector" else { continue }
                source["tiles"] = [localTiles]
                source["scheme"] = "xyz"
                source["minzoom"] = Self.minZoom
                source["maxzoom"] = Self.maxZoomStreetsOffline
                source["bounds"] = [AppConstants.burundiMinLon, AppConstants.burundiMinLat,
                                    AppConstants.burundiMaxLon, AppConstants.burundiMaxLat]
                sources[key] = source
            }
            root["sources"] = sources
        }

        removeOnlineOnlyRasterSources(&root)

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func removeOnlineOnlyRasterSources(_ root: inout [String: Any]) {
        guard var sources = root["sources"] as? [String: Any] else { return }
        let removeKeys = sources.compactMap { key, value -> String? in
            guard let source = value as? [String: Any],
                  source["type"] as? String == "raster",
                  let tiles = source["tiles"] as? [String],
                  tiles.contains(where: { $0.contains("hillshade") || $0.contains("terrain") }) else {
                return nil
            }
            return key
        }
        removeKeys.forEach { sources.removeValue(forKey: $0) }
        root["sources"] = sources

        if var layers = root["layers"] as? [[String: Any]] {
            layers.removeAll { layer in
                guard let source = layer["source"] as? String else { return false }
                return removeKeys.contains(source)
            }
            root["layers"] = layers
        }
    }

    private func fallbackStreetStyleJSON(localTiles: String) -> String {
        """
        {
          "version": 8,
          "name": "Burundi Offline Street",
          "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
          "sources": {
            "openmaptiles": {
              "type": "vector",
              "tiles": ["\(localTiles)"],
              "scheme": "xyz",
              "minzoom": \(Self.minZoom),
              "maxzoom": \(Self.maxZoomStreetsOffline),
              "bounds": [\(AppConstants.burundiMinLon), \(AppConstants.burundiMinLat), \(AppConstants.burundiMaxLon), \(AppConstants.burundiMaxLat)]
            }
          },
          "layers": [
            {
              "id": "background",
              "type": "background",
              "paint": { "background-color": "#f8f4f0" }
            }
          ]
        }
        """
    }

    private func fileSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }
}
