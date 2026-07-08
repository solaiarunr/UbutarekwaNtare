import Foundation

private struct MongoObjectID: Decodable {
    let oid: String

    enum CodingKeys: String, CodingKey {
        case oid = "$oid"
    }
}

enum APIJSONDecoder {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func decodeBool<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decode(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "success"
        }
        return false
    }

    static func decodeStringID<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }
        if var nested = try? container.nestedUnkeyedContainer(forKey: key), let value = try? nested.decode(String.self) {
            return value
        }
        if let mongoID = try? container.decode(MongoObjectID.self, forKey: key) {
            return mongoID.oid
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected a string identifier"
        )
    }
}
