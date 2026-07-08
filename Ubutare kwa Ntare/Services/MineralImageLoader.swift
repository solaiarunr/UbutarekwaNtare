import UIKit

enum MineralImageLoader {
    private static let memoryCache = NSCache<NSString, UIImage>()
    private static let cacheDirectoryName = "cached_mineral_images"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    static func resolvedURL(for imagePath: String) -> URL? {
        let trimmed = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }

        if FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }

        let base = AppConstants.baseURL
        if trimmed.hasPrefix("/") {
            let baseWithoutSlash = base.hasSuffix("/") ? String(base.dropLast()) : base
            return URL(string: baseWithoutSlash + trimmed)
        }

        return URL(string: base + trimmed)
    }

    /// Returns an already-loaded image from memory (instant, no I/O).
    static func memoryCachedImage(mineralId: String?, imagePath: String) -> UIImage? {
        memoryCache.object(forKey: cacheKey(mineralId: mineralId, imagePath: imagePath))
    }

    static func loadImage(from imagePath: String?, mineralId: String? = nil) async -> UIImage? {
        guard let imagePath, !imagePath.isEmpty else { return nil }
        let key = cacheKey(mineralId: mineralId, imagePath: imagePath)

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        if FileManager.default.fileExists(atPath: imagePath),
           let image = UIImage(contentsOfFile: imagePath) {
            store(image, key: key)
            return image
        }

        if let mineralId, let diskImage = loadDiskImage(mineralId: mineralId, imagePath: imagePath) {
            store(diskImage, key: key)
            return diskImage
        }

        guard let url = resolvedURL(for: imagePath) else { return nil }
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            store(image, key: key)
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            if let mineralId {
                saveDiskImage(mineralId: mineralId, imagePath: imagePath, data: data)
            }
            store(image, key: key)
            return image
        } catch {
            return nil
        }
    }

    static func prefetchImages(for minerals: [MineralsListItem]) {
        Task.detached(priority: .utility) {
            for mineral in minerals {
                guard let imagePath = mineral.image, !imagePath.isEmpty else { continue }
                _ = await loadImage(from: imagePath, mineralId: mineral.id)
            }
        }
    }

    private static func cacheKey(mineralId: String?, imagePath: String) -> NSString {
        if let mineralId, !mineralId.isEmpty {
            return mineralId as NSString
        }
        return imagePath as NSString
    }

    private static func store(_ image: UIImage, key: NSString) {
        memoryCache.setObject(image, forKey: key)
    }

    private static func cacheDirectory() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func diskImageURL(mineralId: String) -> URL {
        cacheDirectory().appendingPathComponent("\(mineralId).jpg")
    }

    private static func diskMetaURL(mineralId: String) -> URL {
        cacheDirectory().appendingPathComponent("\(mineralId).url")
    }

    private static func loadDiskImage(mineralId: String, imagePath: String) -> UIImage? {
        let fileURL = diskImageURL(mineralId: mineralId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        if !isLocalImagePath(imagePath) {
            let storedPath = try? String(contentsOf: diskMetaURL(mineralId: mineralId), encoding: .utf8)
            if storedPath != imagePath { return nil }
        }

        return UIImage(contentsOfFile: fileURL.path)
    }

    private static func saveDiskImage(mineralId: String, imagePath: String, data: Data) {
        let fileURL = diskImageURL(mineralId: mineralId)
        try? data.write(to: fileURL, options: .atomic)
        if !isLocalImagePath(imagePath) {
            try? imagePath.write(to: diskMetaURL(mineralId: mineralId), atomically: true, encoding: .utf8)
        }
    }

    private static func isLocalImagePath(_ path: String) -> Bool {
        path.hasPrefix("/") && FileManager.default.fileExists(atPath: path)
    }
}
