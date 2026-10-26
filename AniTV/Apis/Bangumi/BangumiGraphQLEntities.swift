//
//  BangumiGraphQLEntities.swift
//  AniTV
//
//  Created by Codex on 2026/4/8.
//

import Foundation

struct BangumiGraphQLRequest: Encodable, Sendable {
    let query: String
    let variables: [String: Int]?

    init(query: String, variables: [String: Int]? = nil) {
        self.query = query
        self.variables = variables
    }
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

struct BangumiGraphQLTimelineEpisodeNode: Decodable, Sendable {
    let id: Int
    let airdate: String
    let name: String
    let nameCN: String
    let sort: Double

    enum CodingKeys: String, CodingKey {
        case id
        case airdate
        case name
        case nameCN = "name_cn"
        case sort
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.airdate = try container.decode(String.self, forKey: .airdate)
        self.name = try container.decode(String.self, forKey: .name)
        self.nameCN = try container.decode(String.self, forKey: .nameCN)
        self.sort = try container.decode(Double.self, forKey: .sort)
    }
}

struct BangumiGraphQLTimelineSubjectNode: Decodable, Sendable {
    let id: Int
    let images: SubjectImages
    let name: String
    let nameCN: String
    let episodes: [BangumiGraphQLTimelineEpisodeNode]

    enum CodingKeys: String, CodingKey {
        case id
        case images
        case name
        case nameCN = "name_cn"
        case episodes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.images = try container.decode(SubjectImages.self, forKey: .images)
        self.name = try container.decode(String.self, forKey: .name)
        self.nameCN = try container.decode(String.self, forKey: .nameCN)
        self.episodes = try container.decode([BangumiGraphQLTimelineEpisodeNode].self, forKey: .episodes)
    }
}

struct BangumiGraphQLHeroEpisodeNode: Decodable, Sendable {
    let id: Int
    let airdate: String
    let description: String
    let name: String
    let nameCN: String
    let sort: Double
    let type: Int

    enum CodingKeys: String, CodingKey {
        case id
        case airdate
        case description
        case name
        case nameCN = "name_cn"
        case sort
        case type
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.airdate = try container.decodeIfPresent(String.self, forKey: .airdate) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.nameCN = try container.decodeIfPresent(String.self, forKey: .nameCN) ?? ""
        self.sort = try container.decodeIfPresent(Double.self, forKey: .sort) ?? 0
        self.type = try container.decodeIfPresent(Int.self, forKey: .type) ?? 0
    }
}

struct BangumiGraphQLHeroSubjectNode: Decodable, Sendable {
    let id: Int
    let name: String
    let nameCN: String
    let summary: String
    let episodes: [BangumiGraphQLHeroEpisodeNode]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameCN = "name_cn"
        case summary
        case episodes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.nameCN = try container.decodeIfPresent(String.self, forKey: .nameCN) ?? ""
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.episodes = try container.decodeIfPresent([BangumiGraphQLHeroEpisodeNode].self, forKey: .episodes) ?? []
    }
}
