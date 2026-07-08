import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Your account is inactive"
        case .serverError(let message): return message
        case .networkError: return "Network error. Please check your connection and try again."
        case .decodingError(let message): return message
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        decoder = APIJSONDecoder.makeDecoder()
        encoder = JSONEncoder()
    }

    // MARK: - Auth

    func login(phone: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: AppConstants.baseURL + "api/auth/login") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(LoginRequest(phone: phone, password: password))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if let loginResponse = try? decoder.decode(LoginResponse.self, from: data) {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            return loginResponse
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        if let statusResponse = try? decoder.decode(StatusMessageResponse.self, from: data),
           let message = statusResponse.message, !message.isEmpty {
            throw APIError.serverError(message)
        }

        #if DEBUG
        print("Login decode failed. Status: \(http.statusCode)")
        print("Body: \(String(data: data, encoding: .utf8) ?? "<empty>")")
        #endif

        throw APIError.decodingError("Unable to read login response. Please try again.")
    }

    // MARK: - Users

    func createUser(token: String, request: CreateUserRequest) async throws -> LoginResponse {
        try await post("api/users/createuser", token: token, body: request)
    }

    func listUsers(token: String) async throws -> ListUsersResponse {
        try await get("api/users/listusers", token: token)
    }

    func getSettings(token: String) async throws -> SettingsResponse {
        try await get("api/users/getsettings", token: token)
    }

    func changePassword(token: String, userId: String, request: ChangePasswordRequest) async throws -> StatusMessageResponse {
        try await put("api/users/changepassword/\(userId)", token: token, body: request)
    }

    func updateUserActive(token: String, userId: String, isActive: Bool) async throws -> GetUserResponse {
        try await put("api/users/updateuser/\(userId)", token: token, body: ActiveStatusRequest(isActive: isActive))
    }

    func registerUserDevice(token: String, request: RegisterUserDeviceRequest) async throws -> StatusMessageResponse {
        try await post("api/users/registeruserdevice", token: token, body: request)
    }

    // MARK: - Minerals

    func getMineralTypes(token: String) async throws -> MineralTypesResponse {
        try await get("api/minerals/mineral-types", token: token)
    }

    func getMinerals(token: String, latitude: Double, longitude: Double, mineralTypeId: String? = nil, page: Int, limit: Int) async throws -> MineralsListResponse {
        var query = "latitude=\(latitude)&longitude=\(longitude)&page=\(page)&limit=\(limit)"
        if let mineralTypeId, !mineralTypeId.isEmpty {
            query += "&mineralTypeId=\(mineralTypeId)"
        }
        return try await get("api/minerals?\(query)", token: token)
    }

    func createMineral(
        token: String,
        mineralTypeId: String,
        latitude: Double,
        longitude: Double,
        treasureType: String,
        sizeCubicMeters: Double,
        depthCm: Double,
        imageData: Data?
    ) async throws -> MineralDiscoveryResponse {
        var fields: [String: String] = [
            "mineralTypeId": mineralTypeId,
            "latitude": String(latitude),
            "longitude": String(longitude),
            "treasureType": treasureType,
            "sizeCubicMeters": String(sizeCubicMeters),
            "depthCm": String(depthCm)
        ]
        var files: [(name: String, filename: String, mimeType: String, data: Data)] = []
        if let imageData {
            files.append((name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: imageData))
        }
        return try await multipart("api/minerals", token: token, fields: fields, files: files)
    }

    func updateMineral(
        token: String,
        id: String,
        mineralTypeId: String,
        latitude: Double,
        longitude: Double,
        treasureType: String,
        sizeCubicMeters: Double,
        depthCm: Double,
        imageData: Data?
    ) async throws -> MineralDiscoveryResponse {
        var fields: [String: String] = [
            "mineralTypeId": mineralTypeId,
            "latitude": String(latitude),
            "longitude": String(longitude),
            "treasureType": treasureType,
            "sizeCubicMeters": String(sizeCubicMeters),
            "depthCm": String(depthCm)
        ]
        var files: [(name: String, filename: String, mimeType: String, data: Data)] = []
        if let imageData {
            files.append((name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: imageData))
        }
        return try await multipart("api/minerals/\(id)", token: token, method: "PUT", fields: fields, files: files)
    }

    func deleteMineral(token: String, id: String) async throws -> StatusMessageResponse {
        try await delete("api/minerals/\(id)", token: token)
    }

    func bulkMineralSync(token: String, request: BulkMineralSyncRequest) async throws -> MineralDiscoveryResponse {
        try await post("api/minerals/bulk-mineral-sync", token: token, body: request)
    }

    // MARK: - Notifications

    func getNotifications(token: String) async throws -> NotificationsResponse {
        try await get("api/notifications", token: token)
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        try await request(path: path, method: "GET", token: token, bodyData: nil)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, token: String? = nil, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await request(path: path, method: "POST", token: token, bodyData: data)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, token: String? = nil, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await request(path: path, method: "PUT", token: token, bodyData: data)
    }

    private func delete<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        try await request(path: path, method: "DELETE", token: token, bodyData: nil)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        token: String? = nil,
        bodyData: Data?
    ) async throws -> T {
        guard let url = URL(string: AppConstants.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData
        return try await perform(request)
    }

    private func multipart<T: Decodable>(
        _ path: String,
        token: String,
        method: String = "POST",
        fields: [String: String],
        files: [(name: String, filename: String, mimeType: String, data: Data)]
    ) async throws -> T {
        guard let url = URL(string: AppConstants.baseURL + path) else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(StatusMessageResponse.self, from: data))?.message
                ?? String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.serverError(message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            print("API decode error for \(request.url?.absoluteString ?? ""): \(error)")
            print("Response body: \(body)")
            #endif
            throw APIError.decodingError("Unable to read server response. Please try again.")
        }
    }
}
