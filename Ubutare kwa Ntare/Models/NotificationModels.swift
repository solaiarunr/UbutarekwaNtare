import Foundation

struct NotificationsResponse: Decodable {
    let status: Bool
    let message: String?
    let result: [AppNotification]?
}

struct AppNotification: Codable {
    let id: String
    let userId: String?
    let title: String?
    let body: String?
    let messageType: String?
    let mineralId: MineralsListItem?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, title, body, messageType, mineralId, createdAt, updatedAt
    }
}
