import Foundation
import SQLite3

struct MapDownloadProgressInfo {
    let percent: Int
    let status: String
    let zoom: Int
    let totalSaved: Int
    let totalTarget: Int
    let thisZoomSaved: Int
    let thisZoomTotal: Int
    let fileName: String
}

/// Downloads OpenFreeMap vector tiles into a local MBTiles file (Android `MbTilesDownloader`).
enum MbTilesDownloader {
    private static let maxConcurrency = 30
    private static let maxRetryPasses = 6
    private static let progressBatchSize = 8

    private static let burundiStreetTiles: [(z: Int, x: Int, y: Int)] = {
        collectTiles(
            minZoom: OfflineMapManager.minZoom,
            maxZoom: OfflineMapManager.maxZoomStreetsOffline,
            fullBoundsMaxZoom: OfflineMapManager.maxZoomStreetsOffline,
            minLat: AppConstants.burundiMinLat,
            maxLat: AppConstants.burundiMaxLat,
            minLon: AppConstants.burundiMinLon,
            maxLon: AppConstants.burundiMaxLon
        )
    }()

    static func downloadStreetMap(onProgress: @escaping (Int, String) -> Void) async throws {
        let outputFile = OfflineMapManager.shared.streetsMbTilesURL()
        let overallTotal = burundiStreetTiles.count

        onProgress(0, "Preparing map files…")
        await OfflineMapManager.shared.cacheBrightStyleIfNeeded()

        let templates = resolveVectorTemplates()
        guard !templates.isEmpty else {
            throw MbTilesDownloadError.noTileURLs
        }

        let baselineSaved = loadExistingTileKeys(file: outputFile).count
        reportProgress(
            saved: baselineSaved,
            total: overallTotal,
            status: "Preparing street files…",
            onProgress: onProgress
        )

        var saved = baselineSaved
        for z in OfflineMapManager.minZoom...OfflineMapManager.maxZoomStreetsOffline {
            guard NetworkMonitor.shared.isConnected else {
                throw MbTilesDownloadError.noNetwork
            }

            let beforeZoom = loadExistingTileKeys(file: outputFile).count
            saved = try await downloadTilesParallel(
                outputFile: outputFile,
                templates: templates,
                zoom: z,
                overallTotal: overallTotal,
                onProgress: { info in
                    onProgress(info.percent, info.status)
                }
            )
            if saved == beforeZoom {
                let refreshed = resolveVectorTemplates()
                if !refreshed.isEmpty, refreshed != templates {
                    #if DEBUG
                    print("Refreshing street tile URLs after z\(z) failures")
                    #endif
                }
            }
        }

        onProgress(100, "Street tiles saved")
        guard isBurundiStreetMapComplete(file: outputFile) else {
            throw MbTilesDownloadError.incomplete(saved: saved, total: overallTotal)
        }
    }

    static func currentDownloadPercent() -> Int? {
        let file = OfflineMapManager.shared.streetsMbTilesURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let saved = loadExistingTileKeys(file: file).count
        guard saved > 0 else { return nil }
        let total = burundiStreetTiles.count
        guard total > 0 else { return nil }
        return min(99, saved * 100 / total)
    }

    static func hasPartialDownload() -> Bool {
        currentDownloadPercent() != nil
    }

    static func currentSatelliteDownloadPercent() -> Int? {
        let file = OfflineMapManager.shared.satelliteMbTilesURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let saved = loadExistingTileKeys(file: file).count
        guard saved > 0 else { return nil }
        let total = burundiSatelliteTiles.count
        guard total > 0 else { return nil }
        return min(99, saved * 100 / total)
    }

    static func hasPartialSatelliteDownload() -> Bool {
        currentSatelliteDownloadPercent() != nil && !OfflineMapManager.shared.isSatelliteFullyDownloaded()
    }

    static func downloadSatelliteMap(onProgress: @escaping (MapDownloadProgressInfo) -> Void) async throws {
        let outputFile = OfflineMapManager.shared.satelliteMbTilesURL()
        let templates = [OfflineMapManager.esriWorldImageryTileURL]
        let overallTotal = burundiSatelliteTiles.count

        let initialInfo = MapDownloadProgressInfo(
            percent: 0,
            status: "Preparing satellite files…",
            zoom: OfflineMapManager.minZoom,
            totalSaved: 0,
            totalTarget: overallTotal,
            thisZoomSaved: 0,
            thisZoomTotal: 0,
            fileName: "burundi_satellite.mbtiles"
        )
        onProgress(initialInfo)
        
        let baselineSaved = loadExistingTileKeys(file: outputFile).count
        reportProgress(
            saved: baselineSaved,
            total: overallTotal,
            status: "Preparing satellite files…",
            onProgress: onProgress
        )

        var saved = baselineSaved
        for z in OfflineMapManager.minZoom...OfflineMapManager.maxZoomSatelliteOffline {
            guard NetworkMonitor.shared.isConnected else {
                throw MbTilesDownloadError.noNetwork
            }
            saved = try await downloadTilesParallel(
                outputFile: outputFile,
                templates: templates,
                zoom: z,
                overallTotal: overallTotal,
                metaName: "Burundi Satellite",
                metaFormat: "jpg",
                minCompletionRatio: satelliteZoomCompletionRatio(z),
                onProgress: onProgress
            )
            if z >= OfflineMapManager.minSatelliteZoomReady {
                OfflineMapManager.shared.writeOfflineHybridStyleFile()
            }
        }

        let finalInfo = MapDownloadProgressInfo(
            percent: 100,
            status: "Satellite tiles saved",
            zoom: OfflineMapManager.maxZoomSatelliteOffline,
            totalSaved: overallTotal,
            totalTarget: overallTotal,
            thisZoomSaved: 0,
            thisZoomTotal: 0,
            fileName: "burundi_satellite.mbtiles"
        )
        onProgress(finalInfo)
        guard OfflineMapManager.shared.isSatelliteFullyDownloaded() else {
            throw MbTilesDownloadError.incomplete(saved: saved, total: overallTotal)
        }
    }

    static func readMbTilesMaxZoom(file: URL) -> Int? {
        readMetadataValue(file: file, name: "maxzoom").flatMap(Int.init)
    }

    static func readMbTilesActualMaxZoom(file: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(zoom_level) FROM tiles", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let zoom = Int(sqlite3_column_int(statement, 0))
        return zoom > 0 ? zoom : nil
    }

    private static let burundiSatelliteTiles: [(z: Int, x: Int, y: Int)] = {
        collectTiles(
            minZoom: OfflineMapManager.minZoom,
            maxZoom: OfflineMapManager.maxZoomSatelliteOffline,
            fullBoundsMaxZoom: OfflineMapManager.maxZoomSatelliteOffline,
            minLat: AppConstants.burundiMinLat,
            maxLat: AppConstants.burundiMaxLat,
            minLon: AppConstants.burundiMinLon,
            maxLon: AppConstants.burundiMaxLon
        )
    }()

    static func satelliteZoomCompletionRatio(_ zoom: Int) -> Double {
        if zoom >= 14 { return 0.80 }
        return 0.85
    }

    private static func readMetadataValue(file: URL, name: String) -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT value FROM metadata WHERE name=? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    static func isBurundiStreetMapComplete(file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let existing = loadExistingTileKeys(file: file)
        guard !existing.isEmpty else { return false }

        let byZoom = Dictionary(grouping: burundiStreetTiles, by: \.z)
        return byZoom.allSatisfy { z, tiles in
            let required = max(1, Int(Double(tiles.count) * streetZoomCompletionRatio(z)))
            let have = tiles.count { tile in
                existing.contains(tileKeyForDb(z: tile.z, x: tile.x, y: tile.y))
            }
            return have >= required
        }
    }

    static func countTiles(in file: URL) -> Int {
        loadExistingTileKeys(file: file).count
    }

    // MARK: - Download pipeline

    private static func downloadTilesParallel(
        outputFile: URL,
        templates: [String],
        zoom: Int,
        overallTotal: Int,
        metaName: String = "Burundi Streets",
        metaFormat: String = "pbf",
        minCompletionRatio: Double? = nil,
        onProgress: @escaping (MapDownloadProgressInfo) -> Void
    ) async throws -> Int {
        let allTiles = (metaFormat == "jpg" ? burundiSatelliteTiles : burundiStreetTiles).filter { $0.z == zoom }
        let existingKeys = loadExistingTileKeys(file: outputFile)
        let tiles = allTiles.filter { !existingKeys.contains(tileKeyForDb(z: $0.z, x: $0.x, y: $0.y)) }

        if tiles.isEmpty {
            return existingKeys.count
        }

        let alreadyDone = existingKeys.count
        let ratio = minCompletionRatio ?? streetZoomCompletionRatio(zoom)
        let minNewTiles = max(1, Int(Double(tiles.count) * ratio))

        let writer = TileDatabaseWriter(outputFile: outputFile)
        try writer.open()

        var saved = alreadyDone
        var attempts = 0
        var failed: [(z: Int, x: Int, y: Int)] = []

        func report(savedCount: Int, passLabel: String) {
            let zoomDone = max(0, savedCount - alreadyDone)
            let estimatedOverall = min(overallTotal, alreadyDone + zoomDone)
            let percent = overallTotal > 0 ? (estimatedOverall * 100) / overallTotal : 0
            let tileLabel = metaFormat == "jpg" ? "satellite" : "streets"
            let status = "\(passLabel) \(tileLabel) z\(zoom): \(savedCount) / \(overallTotal) files"
            
            let thisZoomTotalCount = allTiles.count
            let thisZoomRemaining = tiles.count
            let thisZoomAlreadyDone = thisZoomTotalCount - thisZoomRemaining
            let thisZoomSavedCount = thisZoomAlreadyDone + zoomDone
            
            let info = MapDownloadProgressInfo(
                percent: percent,
                status: status,
                zoom: zoom,
                totalSaved: savedCount,
                totalTarget: overallTotal,
                thisZoomSaved: thisZoomSavedCount,
                thisZoomTotal: thisZoomTotalCount,
                fileName: metaFormat == "jpg" ? "burundi_satellite.mbtiles" : "burundi_streets.mbtiles"
            )
            onProgress(info)
        }

        report(savedCount: saved, passLabel: "Starting")

        for pass in 0..<maxRetryPasses {
            let passTiles = pass == 0 ? tiles : failed
            failed.removeAll(keepingCapacity: true)
            if passTiles.isEmpty { break }

            var tileIndex = 0
            while tileIndex < passTiles.count {
                guard NetworkMonitor.shared.isConnected else {
                    try writer.close(metadataMaxZoom: zoom)
                    throw MbTilesDownloadError.noNetwork
                }

                let chunkEnd = min(tileIndex + maxConcurrency, passTiles.count)
                let chunk = Array(passTiles[tileIndex..<chunkEnd])
                tileIndex = chunkEnd

                let results = await withTaskGroup(of: (Int, Int, Int, Data?).self) { group in
                    for tile in chunk {
                        group.addTask {
                            let data = await downloadTile(templates: templates, z: tile.z, x: tile.x, y: tile.y)
                            return (tile.z, tile.x, tile.y, data)
                        }
                    }

                    var collected: [(Int, Int, Int, Data)] = []
                    var chunkFailed: [(z: Int, x: Int, y: Int)] = []
                    for await result in group {
                        attempts += 1
                        if let data = result.3 {
                            collected.append((result.0, result.1, result.2, data))
                        } else {
                            chunkFailed.append((result.0, result.1, result.2))
                        }
                    }
                    failed.append(contentsOf: chunkFailed)
                    return collected
                }

                for payload in results {
                    try writer.insertTile(z: payload.0, x: payload.1, y: payload.2, data: payload.3)
                    saved += 1
                }

                if attempts % progressBatchSize == 0 {
                    report(savedCount: saved, passLabel: pass == 0 ? "Downloading" : "Retrying")
                }

                let newSaved = saved - alreadyDone
                if newSaved >= minNewTiles { break }
            }

            let newSaved = saved - alreadyDone
            if newSaved >= minNewTiles || failed.isEmpty { break }
        }

        try writer.close(
            name: metaName,
            format: metaFormat,
            metadataMinZoom: OfflineMapManager.minZoom,
            metadataMaxZoom: zoom
        )
        report(savedCount: saved, passLabel: "Finished")
        return saved
    }

    private static func downloadTile(templates: [String], z: Int, x: Int, y: Int) async -> Data? {
        for template in templates {
            let urlString = buildTileURL(template: template, z: z, x: x, y: y)
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("UbutarekwaNtare/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                    continue
                }
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    private static func reportProgress(
        saved: Int,
        total: Int,
        status: String,
        onProgress: @escaping (Int, String) -> Void
    ) {
        let percent = total > 0 ? min(99, saved * 100 / total) : 0
        onProgress(percent, status)
    }

    private static func reportProgress(
        saved: Int,
        total: Int,
        status: String,
        onProgress: @escaping (MapDownloadProgressInfo) -> Void
    ) {
        let percent = total > 0 ? min(99, saved * 100 / total) : 0
        let info = MapDownloadProgressInfo(
            percent: percent,
            status: status,
            zoom: OfflineMapManager.minZoom,
            totalSaved: saved,
            totalTarget: total,
            thisZoomSaved: 0,
            thisZoomTotal: 0,
            fileName: "burundi_satellite.mbtiles"
        )
        onProgress(info)
    }

    // MARK: - Tile math

    static func streetZoomCompletionRatio(_ zoom: Int) -> Double {
        if zoom >= 14 { return 0.85 }
        if zoom >= 12 { return 0.90 }
        return 0.85
    }

    private static func collectTiles(
        minZoom: Int,
        maxZoom: Int,
        fullBoundsMaxZoom: Int,
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double
    ) -> [(z: Int, x: Int, y: Int)] {
        var result: [(z: Int, x: Int, y: Int)] = []
        result.reserveCapacity(8192)
        for z in minZoom...maxZoom {
            let useHD = z > fullBoundsMaxZoom
            let latMin = useHD ? minLat : AppConstants.burundiMinLat
            let latMax = useHD ? maxLat : AppConstants.burundiMaxLat
            let lonMin = useHD ? minLon : AppConstants.burundiMinLon
            let lonMax = useHD ? maxLon : AppConstants.burundiMaxLon
            let xMin = latLonToTile(lat: 0, lon: lonMin, zoom: z).x
            let xMax = latLonToTile(lat: 0, lon: lonMax, zoom: z).x
            let yNorth = latLonToTile(lat: latMax, lon: 0, zoom: z).y
            let ySouth = latLonToTile(lat: latMin, lon: 0, zoom: z).y
            for x in xMin...xMax {
                for y in yNorth...ySouth {
                    result.append((z, x, y))
                }
            }
        }
        return result
    }

    private static func latLonToTile(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = 1 << zoom
        let x = Int(floor((lon + 180.0) / 360.0 * Double(n))).clamped(to: 0...(n - 1))
        let latRad = lat * .pi / 180.0
        let y = (Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * Double(n))))
            .clamped(to: 0...(n - 1))
        return (x, y)
    }

    private static func buildTileURL(template: String, z: Int, x: Int, y: Int) -> String {
        template
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
    }

    private static func resolveVectorTemplates() -> [String] {
        if let asset = bundledTileTemplates(named: "openfreemap_planet_tilejson") {
            return asset
        }
        return [OfflineMapManager.openFreeMapVectorTileURL]
    }

    private static func bundledTileTemplates(named name: String) -> [String]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiles = json["tiles"] as? [String],
              !tiles.isEmpty else {
            return nil
        }
        return tiles.filter { $0.contains("{z}") && $0.contains("{x}") && $0.contains("{y}") }
    }

    private static func tileKeyForDb(z: Int, x: Int, y: Int) -> String {
        let tmsY = (1 << z) - 1 - y
        return "\(z):\(x):\(tmsY)"
    }

    private static func loadExistingTileKeys(file: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            return []
        }
        defer { sqlite3_close(db) }

        var keys = Set<String>()
        var statement: OpaquePointer?
        let sql = "SELECT zoom_level, tile_column, tile_row FROM tiles"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let z = Int(sqlite3_column_int(statement, 0))
            let x = Int(sqlite3_column_int(statement, 1))
            let row = Int(sqlite3_column_int(statement, 2))
            keys.insert("\(z):\(x):\(row)")
        }
        return keys
    }
}

enum MbTilesDownloadError: LocalizedError {
    case noNetwork
    case noTileURLs
    case incomplete(saved: Int, total: Int)

    var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "No internet connection. Connect to Wi‑Fi or mobile data, then try again."
        case .noTileURLs:
            return "No street tile URLs found. Check internet connection."
        case let .incomplete(saved, total):
            return "Street map download incomplete (\(saved) / \(total) tiles). Check internet connection."
        }
    }
}

private final class TileDatabaseWriter {
    private let outputFile: URL
    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?
    private var pendingWrites = 0

    init(outputFile: URL) {
        self.outputFile = outputFile
    }

    func open() throws {
        if sqlite3_open(outputFile.path, &db) != SQLITE_OK {
            throw MbTilesDownloadError.noTileURLs
        }
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS tiles (
                zoom_level INTEGER NOT NULL,
                tile_column INTEGER NOT NULL,
                tile_row INTEGER NOT NULL,
                tile_data BLOB NOT NULL,
                PRIMARY KEY (zoom_level, tile_column, tile_row)
            );
            CREATE TABLE IF NOT EXISTS metadata (
                name TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            nil, nil, nil
        )

        let sql = "INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &insertStatement, nil) == SQLITE_OK else {
            throw MbTilesDownloadError.noTileURLs
        }
    }

    func insertTile(z: Int, x: Int, y: Int, data: Data) throws {
        guard let db, let insertStatement else { return }
        let tmsY = (1 << z) - 1 - y
        sqlite3_reset(insertStatement)
        sqlite3_clear_bindings(insertStatement)
        sqlite3_bind_int(insertStatement, 1, Int32(z))
        sqlite3_bind_int(insertStatement, 2, Int32(x))
        sqlite3_bind_int(insertStatement, 3, Int32(tmsY))
        _ = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(insertStatement, 4, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
        guard sqlite3_step(insertStatement) == SQLITE_DONE else {
            throw MbTilesDownloadError.noTileURLs
        }
        pendingWrites += 1
        if pendingWrites >= 500 {
            sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
            pendingWrites = 0
        }
    }

    func close(
        name: String = "Burundi Streets",
        format: String = "pbf",
        metadataMinZoom: Int = OfflineMapManager.minZoom,
        metadataMaxZoom: Int = OfflineMapManager.maxZoomStreetsOffline
    ) throws {
        guard let db else { return }
        writeMetadata(name: name, format: format, minZoom: metadataMinZoom, maxZoom: metadataMaxZoom)
        sqlite3_finalize(insertStatement)
        insertStatement = nil
        sqlite3_close(db)
        self.db = nil
    }

    private func writeMetadata(name: String, format: String, minZoom: Int, maxZoom: Int) {
        guard let db else { return }
        let entries: [(String, String)] = [
            ("name", name),
            ("format", format),
            ("bounds", "\(AppConstants.burundiMinLon),\(AppConstants.burundiMinLat),\(AppConstants.burundiMaxLon),\(AppConstants.burundiMaxLat)"),
            ("minzoom", String(minZoom)),
            ("maxzoom", String(maxZoom)),
            ("center", "\(AppConstants.burundiCenterLon),\(AppConstants.burundiCenterLat),\(Int(AppConstants.burundiDefaultZoom))")
        ]
        for (key, value) in entries {
            var statement: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO metadata (name, value) VALUES (?, ?)"
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
