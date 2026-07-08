import Foundation

struct LoginRequest: Encodable {
    let phone: String
    let password: String
}

struct LoginResponse: Decodable {
    let status: Bool
    let message: String?
    let result: LoginResult?

    enum CodingKeys: String, CodingKey {
        case status, success, message, result, token, accessToken, user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        if let nestedResult = try container.decodeIfPresent(LoginResult.self, forKey: .result) {
            result = nestedResult
        } else if let token = try container.decodeIfPresent(String.self, forKey: .token),
                  let user = try container.decodeIfPresent(AuthUser.self, forKey: .user) {
            result = LoginResult(token: token, user: user)
        } else if let token = try container.decodeIfPresent(String.self, forKey: .accessToken),
                  let user = try container.decodeIfPresent(AuthUser.self, forKey: .user) {
            result = LoginResult(token: token, user: user)
        } else {
            result = nil
        }

        if APIJSONDecoder.decodeBool(from: container, forKey: .status) {
            status = true
        } else {
            status = APIJSONDecoder.decodeBool(from: container, forKey: .success)
        }
    }
}

struct LoginResult: Decodable {
    let token: String
    let user: AuthUser

    init(token: String, user: AuthUser) {
        self.token = token
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case token, accessToken, user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .token), !token.isEmpty {
            self.token = token
        } else if let token = try container.decodeIfPresent(String.self, forKey: .accessToken), !token.isEmpty {
            self.token = token
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.token,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing auth token in login response")
            )
        }

        if let nestedUser = try container.decodeIfPresent(AuthUser.self, forKey: .user) {
            user = nestedUser
        } else {
            user = try AuthUser(from: decoder)
        }
    }
}

struct AuthUser: Codable {
    let id: String
    let phone: String
    let displayName: String
    let role: String
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case phone, displayName, name, role, isActive, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try APIJSONDecoder.decodeStringID(from: container, forKey: .id)
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        let decodedDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        displayName = decodedDisplayName ?? decodedName ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        createdAt = try? container.decode(String.self, forKey: .createdAt)
        updatedAt = try? container.decode(String.self, forKey: .updatedAt)
        if container.contains(.isActive) {
            isActive = APIJSONDecoder.decodeBool(from: container, forKey: .isActive)
        } else {
            isActive = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(phone, forKey: .phone)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(role, forKey: .role)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct ChangePasswordRequest: Encodable {
    let password: String
    let confirmPassword: String
}

struct StatusMessageResponse: Decodable {
    let status: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        status = APIJSONDecoder.decodeBool(from: container, forKey: .status)
    }
}

struct RegisterUserDeviceRequest: Encodable {
    let deviceId: String
    let deviceType: Int
    let deviceToken: String
}
