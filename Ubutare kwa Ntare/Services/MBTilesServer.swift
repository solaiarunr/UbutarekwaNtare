import Foundation
import Network
import SQLite3
import zlib

/// Serves local MBTiles over HTTP for MapLibre (Android `MBTilesServer`).
final class MBTilesServer {
    static let street = MBTilesServer(port: OfflineMapManager.tileServerStreetPort)
    static let satellite = MBTilesServer(port: OfflineMapManager.tileServerSatellitePort)

    private let port: UInt16
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var db: OpaquePointer?
    private var mbtilesPath: URL?
    private(set) var isRunning = false

    init(port: UInt16) {
        self.port = port
        self.queue = DispatchQueue(label: "com.ubutare.mbtiles-server.\(port)", qos: .userInitiated)
    }

    @discardableResult
    func start(mbtilesPath: URL) -> Bool {
        if isRunning, self.mbtilesPath == mbtilesPath { return true }
        stop()

        guard FileManager.default.fileExists(atPath: mbtilesPath.path) else { return false }

        var database: OpaquePointer?
        guard sqlite3_open_v2(mbtilesPath.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return false
        }

        self.mbtilesPath = mbtilesPath
        self.db = database

        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            closeDatabase()
            return false
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener?.start(queue: queue)
        isRunning = true
        return true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        closeDatabase()
        mbtilesPath = nil
        isRunning = false
    }

    private func closeDatabase() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                .components(separatedBy: "\r\n")
                .first ?? ""
            let response = self.httpResponse(for: requestLine)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func httpResponse(for requestLine: String) -> Data {
        guard requestLine.hasPrefix("GET /tiles/") else {
            return buildHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
        }

        let path = requestLine
            .components(separatedBy: " ").dropFirst().first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let parts = path
            .replacingOccurrences(of: "/tiles/", with: "")
            .split(separator: "/")
            .map(String.init)

        guard parts.count == 3,
              let z = Int(parts[0]),
              let x = Int(parts[1]) else {
            return vectorTileResponse(data: Self.emptyVectorTile)
        }

        let yRaw = parts[2]
            .replacingOccurrences(of: ".pbf", with: "")
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")

        guard let y = Int(yRaw) else {
            return vectorTileResponse(data: Self.emptyVectorTile)
        }

        let isVector = path.hasSuffix(".pbf")
        if let blob = findTile(z: z, x: x, y: y, isVector: isVector) {
            if isVector {
                let data = Self.isGzipped(blob) ? (Self.decompressGzip(blob) ?? blob) : blob
                return vectorTileResponse(data: data)
            }
            let mime = path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") ? "image/jpeg" : "image/png"
            return buildHTTPResponse(status: "200 OK", contentType: mime, body: blob)
        }

        return isVector
            ? vectorTileResponse(data: Self.emptyVectorTile)
            : buildHTTPResponse(status: "200 OK", contentType: "image/png", body: Self.emptyPNG)
    }

    private func vectorTileResponse(data: Data) -> Data {
        buildHTTPResponse(
            status: "200 OK",
            contentType: "application/vnd.mapbox-vector-tile",
            body: data
        )
    }

    private func buildHTTPResponse(status: String, contentType: String, body: Data) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: public, max-age=86400\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func findTile(z: Int, x: Int, y: Int, isVector: Bool) -> Data? {
        guard db != nil else { return nil }
        if isVector {
            let tmsY = (1 << z) - 1 - y
            return findTileRaw(z: z, x: x, row: tmsY)
        }

        var cz = z
        var cx = x
        var cy = y
        while cz >= 0 {
            let tmsY = (1 << cz) - 1 - cy
            if let tile = findTileRaw(z: cz, x: cx, row: tmsY) {
                return tile
            }
            if cz == 0 { break }
            cz -= 1
            cx >>= 1
            cy >>= 1
        }
        return nil
    }

    private func findTileRaw(z: Int, x: Int, row: Int) -> Data? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(z))
        sqlite3_bind_int(statement, 2, Int32(x))
        sqlite3_bind_int(statement, 3, Int32(row))

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 0))
        return Data(bytes: bytes, count: length)
    }

    private static let emptyVectorTile = Data([0x1A, 0x02, 0x10, 0x00])

    private static let emptyPNG = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    ])

    private static func isGzipped(_ bytes: Data) -> Bool {
        bytes.count >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B
    }

    private static func decompressGzip(_ data: Data) -> Data? {
        data.withUnsafeBytes { inputBuffer in
            guard let inputPointer = inputBuffer.bindMemory(to: Bytef.self).baseAddress else { return nil }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer)
            stream.avail_in = uInt(data.count)

            var output = Data()
            let chunkSize = 16_384
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }
            defer { inflateEnd(&stream) }

            var status: Int32 = Z_OK
            repeat {
                let produced: Int = buffer.withUnsafeMutableBytes { rawBuffer in
                    guard let outPointer = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
                    stream.next_out = outPointer
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END else { return nil }
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while status != Z_STREAM_END

            return output.isEmpty ? nil : output
        }
    }
}
