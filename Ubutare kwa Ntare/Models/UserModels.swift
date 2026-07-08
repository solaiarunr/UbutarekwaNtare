import Foundation

struct SettingsResponse: Decodable {
    let status: Bool
    let message: String?
    let result: AppSettings?
}

struct AppSettings: Codable {
    let id: String
    let siteName: String?
    let oneSignalAppId: String?
    let oneSignalRestApiKey: String?
    let oneSignalRestApiUrl: String?
    let footerText: String?
    let siteLogo: String?
    let roles: [RoleSetting]
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case siteName = "site_name"
        case oneSignalAppId = "onesignal_app_id"
        case oneSignalRestApiKey = "onesignal_rest_api_key"
        case oneSignalRestApiUrl = "onesignal_rest_api_url"
        case footerText = "footer_text"
        case siteLogo = "site_logo"
        case roles, createdAt, updatedAt
    }
}

struct RoleSetting: Codable {
    let key: String
    let label: String
}

struct CreateUserRequest: Encodable {
    let phone: String
    let password: String
    let confirmPassword: String
    let role: String
    let displayName: String
}

struct ListUsersResponse: Decodable {
    let status: Bool
    let message: String?
    let result: ListUsersResult?
}

struct ListUsersResult: Decodable {
    let users: [AuthUser]
    let total: Int
    let page: Int
    let limit: Int
}

struct GetUserResponse: Decodable {
    let status: Bool
    let message: String?
    let result: AuthUser?
}

struct UpdateUserRequest: Encodable {
    let displayName: String?
    let phone: String?
    let role: String?
}

struct ActiveStatusRequest: Encodable {
    let isActive: Bool?
}
