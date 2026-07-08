import Foundation

struct MineralTypesResponse: Decodable {
    let status: Bool
    let message: String?
    let result: MineralTypesResult?

    enum CodingKeys: String, CodingKey {
        case status, success, message, result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if APIJSONDecoder.decodeBool(from: container, forKey: .status) {
            status = true
        } else {
            status = APIJSONDecoder.decodeBool(from: container, forKey: .success)
        }

        if let nested = try? container.decode(MineralTypesResult.self, forKey: .result) {
            result = nested
        } else if let types = try? container.decode([MineralType].self, forKey: .result) {
            result = MineralTypesResult(mineralTypes: types, total: types.count, page: 1, limit: types.count)
        } else {
            result = nil
        }
    }
}

struct MineralTypesResult: Decodable {
    let mineralTypes: [MineralType]
    let total: Int
    let page: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case mineralTypes, types, total, page, limit
    }

    init(mineralTypes: [MineralType], total: Int, page: Int, limit: Int) {
        self.mineralTypes = mineralTypes
        self.total = total
        self.page = page
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let types = try container.decodeIfPresent([MineralType].self, forKey: .mineralTypes) {
            mineralTypes = types
        } else {
            mineralTypes = try container.decodeIfPresent([MineralType].self, forKey: .types) ?? []
        }
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? mineralTypes.count
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? mineralTypes.count
    }
}

struct MineralType: Codable {
    let id: String
    let name: String
    let color: String
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, color, isActive, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try APIJSONDecoder.decodeStringID(from: container, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#F4A300"
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
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct MineralsListResponse: Decodable {
    let status: Bool
    let message: String?
    let result: MineralsListResult?
}

struct MineralsListResult: Decodable {
    let minerals: [MineralsListItem]
    let total: Int
    let page: Int
    let limit: Int
}

struct MineralsListItem: Codable {
    let id: String
    let mineralTypeId: MineralTypeRef
    let userId: String?
    let latitude: Double
    let longitude: Double
    let treasureType: String
    let image: String?
    let sizeCubicMeters: Double
    let depthCm: Double?
    let addedBy: AddedByRef?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case mineralTypeId
        case userId = "user_id"
        case latitude, longitude, treasureType, image, sizeCubicMeters, depthCm, addedBy, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try APIJSONDecoder.decodeStringID(from: container, forKey: .id)
        mineralTypeId = try container.decode(MineralTypeRef.self, forKey: .mineralTypeId)
        if let value = try? container.decode(String.self, forKey: .userId) {
            userId = value
        } else if let value = try? APIJSONDecoder.decodeStringID(from: container, forKey: .userId) {
            userId = value
        } else {
            userId = nil
        }
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        treasureType = try container.decodeIfPresent(String.self, forKey: .treasureType) ?? "natural"
        image = try container.decodeIfPresent(String.self, forKey: .image)
        sizeCubicMeters = try container.decodeIfPresent(Double.self, forKey: .sizeCubicMeters) ?? 0
        depthCm = try container.decodeIfPresent(Double.self, forKey: .depthCm)
        addedBy = try container.decodeIfPresent(AddedByRef.self, forKey: .addedBy)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var ownerUserId: String? {
        let trimmedUserId = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedUserId.isEmpty { return trimmedUserId }
        let trimmedAddedById = addedBy?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedAddedById.isEmpty ? nil : trimmedAddedById
    }

    func isOwnedByCurrentUser(currentUserId: String?) -> Bool {
        guard let currentUserId = currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !currentUserId.isEmpty,
              let ownerUserId else { return false }
        return ownerUserId.caseInsensitiveCompare(currentUserId) == .orderedSame
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mineralTypeId, forKey: .mineralTypeId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(treasureType, forKey: .treasureType)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(sizeCubicMeters, forKey: .sizeCubicMeters)
        try container.encodeIfPresent(depthCm, forKey: .depthCm)
        try container.encodeIfPresent(addedBy, forKey: .addedBy)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct MineralTypeRef: Codable {
    let id: String
    let name: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, color
    }

    init(id: String, name: String = "", color: String = "#F4A300") {
        self.id = id
        self.name = name
        self.color = color
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let stringId = try? singleValue.decode(String.self) {
            id = stringId
            name = ""
            color = "#F4A300"
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try APIJSONDecoder.decodeStringID(from: container, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#F4A300"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
    }
}

struct AddedByRef: Codable {
    let id: String
    let displayName: String
    let phone: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case displayName, phone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try APIJSONDecoder.decodeStringID(from: container, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(phone, forKey: .phone)
    }
}

struct MineralDiscoveryResponse: Decodable {
    let status: Bool
    let message: String?
    let result: MineralDiscoveryResult?
}

struct MineralDiscoveryResult: Decodable {
    let results: [MineralDiscoveryItem]?
    let synced: [String]?
    let deleted: [String]?

    var items: [MineralDiscoveryItem] { results ?? [] }
}

struct MineralDiscoveryItem: Decodable {
    let id: String
    let mineralTypeId: String
    let latitude: Double?
    let longitude: Double?
    let treasureType: String
    let image: String?
    let sizeCubicMeters: Double?
    let depthCm: Double?
    let userId: String?
    let addedBy: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case mineralTypeId, latitude, longitude, treasureType, image, sizeCubicMeters, depthCm
        case userId = "user_id"
        case addedBy, createdAt, updatedAt
    }
}

struct BulkMineralSyncRequest: Encodable {
    let created: [BulkMineralCreateItem]
    let updated: [BulkMineralUpdateItem]
    let deleted: [BulkMineralDeleteItem]
}

struct BulkMineralCreateItem: Encodable {
    let localId: String
    let mineralTypeId: String
    let latitude: Double
    let longitude: Double
    let treasureType: String
    let sizeCubicMeters: Double
    let depthCm: Double
    let addedBy: String
    let image: String
}

struct BulkMineralUpdateItem: Encodable {
    let id: String
    let localId: String?
    let mineralTypeId: String
    let latitude: Double
    let longitude: Double
    let treasureType: String
    let sizeCubicMeters: Double
    let depthCm: Double
    let addedBy: String
    let image: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case localId, mineralTypeId, latitude, longitude, treasureType, sizeCubicMeters, depthCm, addedBy, image
    }
}

struct BulkMineralDeleteItem: Encodable {
    let id: String
    let localId: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case localId
    }
}

struct PendingMineralSync: Codable {
    enum Action: String, Codable { case create, update, delete }

    let localId: String
    let serverId: String?
    let action: Action
    let mineralTypeId: String
    let latitude: Double
    let longitude: Double
    let treasureType: String
    let sizeCubicMeters: Double
    let depthCm: Double
    let addedBy: String
    let imagePath: String?
    let createdAt: Date
}
