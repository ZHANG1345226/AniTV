//
//  BangumiGraphQLEntities.swift
//  AniTV
//
//  Created by Codex on 2026/4/8.
//

import Foundation

struct BangumiGraphQLRequest: Encodable, Sendable {
    let query: String
}

struct BangumiGraphQLResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T?
    let errors: [BangumiGraphQLError]?

    enum CodingKeys: String, CodingKey {
        case data, errors
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decodeIfPresent(T.self, forKey: .data)
        self.errors = try container.decodeIfPresent([BangumiGraphQLError].self, forKey: .errors)
    }
}

struct BangumiGraphQLError: Decodable, Sendable {
    let message: String

    enum CodingKeys: String, CodingKey {
        case message
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)
    }
}

struct BangumiGraphQLSubjectNode: Decodable, Sendable {
    let id: Int
    let images: BangumiGraphQLSubjectImages

    enum CodingKeys: String, CodingKey {
        case id, images
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.images = try container.decode(BangumiGraphQLSubjectImages.self, forKey: .images)
    }
}

struct BangumiGraphQLSubjectImages: Decodable, Sendable {
    let large: String

    enum CodingKeys: String, CodingKey {
        case large
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.large = try container.decode(String.self, forKey: .large)
    }
}
