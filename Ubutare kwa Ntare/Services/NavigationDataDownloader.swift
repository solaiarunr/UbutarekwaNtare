import Foundation

/// Downloads the Burundi OSM PBF used for offline navigation (same file as Android).
enum NavigationDataDownloader {
    private static let downloadURL = URL(
        string: "https://download.geofabrik.de/africa/burundi-latest.osm.pbf"
    )!
    private static let minOsmBytes: Int64 = 5 * 1024 * 1024
    private static let estimatedBytes: Int64 = 20 * 1024 * 1024
    private static let expectedSizeKey = "navigation_osm_expected_bytes"
    private static let writeChunkSize = 65_536

    static func downloadIfNeeded(onProgress: @escaping (Int) -> Void) async -> Bool {
        if OfflineNavigationHelper.shared.hasNavigationData() {
            clearDownloadState()
            onProgress(100)
            return true
        }
        guard NetworkMonitor.shared.isConnected else { return false }

        let destination = OfflineNavigationHelper.shared.navigationOsmFileURL()
        let tempURL = tempDownloadURL(for: destination)

        if let size = fileSize(destination), size > 0, size < minOsmBytes {
            try? FileManager.default.removeItem(at: destination)
        }

        if let partialPercent = currentDownloadPercent() {
            await MainActor.run {
                onProgress(partialPercent)
            }
        }

        do {
            try await downloadResumable(to: tempURL, onProgress: onProgress)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            clearDownloadState()
            onProgress(100)
            return OfflineNavigationHelper.shared.hasNavigationData()
        } catch {
            #if DEBUG
            print("Navigation OSM download failed: \(error.localizedDescription)")
            #endif
            if let partialPercent = currentDownloadPercent() {
                await MainActor.run {
                    onProgress(partialPercent)
                }
            }
            return false
        }
    }

    static func currentDownloadPercent() -> Int? {
        let destination = OfflineNavigationHelper.shared.navigationOsmFileURL()
        let tempURL = tempDownloadURL(for: destination)
        guard let downloaded = fileSize(tempURL), downloaded > 0 else { return nil }

        let expected = expectedTotalBytes() ?? estimatedBytes
        guard expected > 0 else { return nil }
        return min(99, Int((downloaded * 100) / expected))
    }

    static func hasPartialDownload() -> Bool {
        currentDownloadPercent() != nil
    }

    private static func downloadResumable(
        to destination: URL,
        onProgress: @escaping (Int) -> Void
    ) async throws {
        let existingBytes = fileSize(destination) ?? 0

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 300
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let isResume = existingBytes > 0 && http.statusCode == 206
        if existingBytes > 0, http.statusCode == 200 {
            try? FileManager.default.removeItem(at: destination)
            UserDefaults.standard.removeObject(forKey: expectedSizeKey)
            try await downloadResumable(to: destination, onProgress: onProgress)
            return
        }

        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let totalBytes = resolveTotalBytes(
            response: http,
            existingBytes: isResume ? existingBytes : 0
        )
        if totalBytes > 0 {
            UserDefaults.standard.set(Int(totalBytes), forKey: expectedSizeKey)
        }

        let handle: FileHandle
        if isResume {
            handle = try FileHandle(forWritingTo: destination)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            handle = try FileHandle(forWritingTo: destination)
        }
        defer { try? handle.close() }

        var downloaded = isResume ? existingBytes : 0
        var lastPercent = -1
        var buffer = Data()
        buffer.reserveCapacity(writeChunkSize)

        for try await byte in asyncBytes {
            if !NetworkMonitor.shared.isConnected {
                try handle.write(contentsOf: buffer)
                throw URLError(.networkConnectionLost)
            }

            buffer.append(byte)
            downloaded += 1

            if buffer.count >= writeChunkSize {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            let percent = progressPercent(downloaded: downloaded, totalBytes: totalBytes)
            if percent != lastPercent {
                lastPercent = percent
                await MainActor.run {
                    onProgress(percent)
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        let finalSize = fileSize(destination) ?? 0
        guard finalSize >= minOsmBytes else {
            throw URLError(.cannotDecodeContentData)
        }

        if totalBytes > 0, finalSize < totalBytes {
            throw URLError(.downloadDecodingFailedMidStream)
        }
    }

    private static func resolveTotalBytes(
        response: HTTPURLResponse,
        existingBytes: Int64
    ) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range") {
            if let total = parseContentRangeTotal(contentRange) {
                return total
            }
        }

        if response.expectedContentLength > 0 {
            if response.statusCode == 206 {
                return existingBytes + response.expectedContentLength
            }
            return response.expectedContentLength
        }

        return expectedTotalBytes() ?? estimatedBytes
    }

    private static func parseContentRangeTotal(_ value: String) -> Int64? {
        // Example: bytes 1000-1999/5000
        guard let slashIndex = value.lastIndex(of: "/") else { return nil }
        let totalPart = value[value.index(after: slashIndex)...]
        guard totalPart != "*" else { return nil }
        return Int64(totalPart)
    }

    private static func progressPercent(downloaded: Int64, totalBytes: Int64) -> Int {
        guard totalBytes > 0 else {
            return min(99, Int((downloaded * 100) / estimatedBytes))
        }
        return min(99, Int((downloaded * 100) / totalBytes))
    }

    private static func expectedTotalBytes() -> Int64? {
        let value = UserDefaults.standard.object(forKey: expectedSizeKey) as? Int64
        if let value, value > 0 { return value }
        let intValue = UserDefaults.standard.object(forKey: expectedSizeKey) as? Int
        if let intValue, intValue > 0 { return Int64(intValue) }
        return nil
    }

    private static func tempDownloadURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent("\(destination.lastPathComponent).download")
    }

    private static func clearDownloadState() {
        UserDefaults.standard.removeObject(forKey: expectedSizeKey)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else { return nil }
        return size
    }
}
