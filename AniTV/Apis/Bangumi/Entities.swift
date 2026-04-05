//
//  Entities.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// MARK: - Root Response
struct BgmResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let total: Int
    
    enum CodingKeys: String, CodingKey {
        case data, total
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([T].self, forKey: .data)
        self.total = try container.decode(Int.self, forKey: .total)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(total, forKey: .total)
    }
}

// MARK: - Trending Item
struct TrendingSubjectDTO: Codable, Identifiable, Sendable {
    let count: Int
    let subject: SlimSubjectDTO
    
    var id: Int { subject.id }
    
    enum CodingKeys: String, CodingKey {
        case count, subject
    }
    
    // 🔥 强制修复：手动实现 nonisolated 初始化
    // 这行代码告诉编译器：此初始化方法可以在后台线程安全运行
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.count = try container.decode(Int.self, forKey: .count)
        self.subject = try container.decode(SlimSubjectDTO.self, forKey: .subject)
    }
    
    // 对应的 Encode 方法（为了满足 Codable）
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        try container.encode(subject, forKey: .subject)
    }
}

// MARK: - Subject Info
struct SlimSubjectDTO: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCN: String
    let type: Int
    let info: String
    let locked: Bool
    let nsfw: Bool
    let rating: SubjectRating
    let images: SubjectImages
    
    enum CodingKeys: String, CodingKey {
        case id, name, nameCN, type, info, locked, nsfw, rating, images
    }
    
    // 🔥 强制修复：手动实现 nonisolated 初始化
    // 如果 DTO 嵌套层级深，底层的这个 nonisolated 至关重要
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        // 注意：如果 JSON 可能缺省 nameCN，这里可以用 decodeIfPresent，或者给默认值
        self.nameCN = try container.decode(String.self, forKey: .nameCN)
        self.type = try container.decode(Int.self, forKey: .type)
        self.info = try container.decode(String.self, forKey: .info)
        self.locked = try container.decode(Bool.self, forKey: .locked)
        self.nsfw = try container.decode(Bool.self, forKey: .nsfw)
        self.rating = try container.decode(SubjectRating.self, forKey: .rating)
        self.images = try container.decode(SubjectImages.self, forKey: .images)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(nameCN, forKey: .nameCN)
        try container.encode(type, forKey: .type)
        try container.encode(info, forKey: .info)
        try container.encode(locked, forKey: .locked)
        try container.encode(nsfw, forKey: .nsfw)
        try container.encode(rating, forKey: .rating)
        try container.encode(images, forKey: .images)
    }
}

// MARK: - Rating
struct SubjectRating: Codable, Sendable {
    let rank: Int
    let count: [Int]
    let score: Double
    let total: Int
    
    // 如果这里也报错，也可以加上 nonisolated init，通常上面两层够了
}

// MARK: - Images
struct SubjectImages: Codable, Sendable {
    let large: String
    let common: String
    let medium: String
    let small: String
    let grid: String
}

// MARK: - Subject Detail DTO (/p1/subjects/{subjectID})
struct SubjectDetailDTO: Codable, Identifiable, Sendable {
    let id: Int
    let airtime: SubjectAirtimeDTO
    let collection: SubjectCollectionDTO
    let eps: Int
    let images: SubjectImages?
    let info: String
    let infobox: [InfoboxItemDTO]
    let interest: SubjectInterestDTO?
    let locked: Bool
    let metaTags: [String]
    let name: String
    let nameCN: String
    let nsfw: Bool
    let platform: SubjectPlatformDTO
    let rating: SubjectRating
    let redirect: Int
    let series: Bool
    let seriesEntry: Int
    let summary: String
    let tags: [SubjectTagDTO]
    let type: Int
    let volumes: Int

    enum CodingKeys: String, CodingKey {
        case id
        case airtime
        case collection
        case eps
        case images
        case info
        case infobox
        case interest
        case locked
        case metaTags
        case name
        case nameCN
        case nsfw
        case platform
        case rating
        case redirect
        case series
        case seriesEntry
        case summary
        case tags
        case type
        case volumes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.airtime = try container.decode(SubjectAirtimeDTO.self, forKey: .airtime)
        self.collection = try container.decode(SubjectCollectionDTO.self, forKey: .collection)
        self.eps = try container.decode(Int.self, forKey: .eps)
        self.images = try container.decodeIfPresent(SubjectImages.self, forKey: .images)
        self.info = try container.decode(String.self, forKey: .info)
        self.infobox = try container.decode([InfoboxItemDTO].self, forKey: .infobox)
        self.interest = try container.decodeIfPresent(SubjectInterestDTO.self, forKey: .interest)
        self.locked = try container.decode(Bool.self, forKey: .locked)
        self.metaTags = try container.decode([String].self, forKey: .metaTags)
        self.name = try container.decode(String.self, forKey: .name)
        self.nameCN = try container.decode(String.self, forKey: .nameCN)
        self.nsfw = try container.decode(Bool.self, forKey: .nsfw)
        self.platform = try container.decode(SubjectPlatformDTO.self, forKey: .platform)
        self.rating = try container.decode(SubjectRating.self, forKey: .rating)
        self.redirect = try container.decode(Int.self, forKey: .redirect)
        self.series = try container.decode(Bool.self, forKey: .series)
        self.seriesEntry = try container.decode(Int.self, forKey: .seriesEntry)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.tags = try container.decode([SubjectTagDTO].self, forKey: .tags)
        self.type = try container.decode(Int.self, forKey: .type)
        self.volumes = try container.decode(Int.self, forKey: .volumes)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(airtime, forKey: .airtime)
        try container.encode(collection, forKey: .collection)
        try container.encode(eps, forKey: .eps)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encode(info, forKey: .info)
        try container.encode(infobox, forKey: .infobox)
        try container.encodeIfPresent(interest, forKey: .interest)
        try container.encode(locked, forKey: .locked)
        try container.encode(metaTags, forKey: .metaTags)
        try container.encode(name, forKey: .name)
        try container.encode(nameCN, forKey: .nameCN)
        try container.encode(nsfw, forKey: .nsfw)
        try container.encode(platform, forKey: .platform)
        try container.encode(rating, forKey: .rating)
        try container.encode(redirect, forKey: .redirect)
        try container.encode(series, forKey: .series)
        try container.encode(seriesEntry, forKey: .seriesEntry)
        try container.encode(summary, forKey: .summary)
        try container.encode(tags, forKey: .tags)
        try container.encode(type, forKey: .type)
        try container.encode(volumes, forKey: .volumes)
    }
}

struct SubjectAirtimeDTO: Codable, Sendable {
    let date: String
    let month: Int
    let weekday: Int
    let year: Int
}

// API schema for SubjectCollection is object and fields are dynamic.
typealias SubjectCollectionDTO = [String: Int]

struct SubjectInterestDTO: Codable, Sendable {
    let comment: String
    let epStatus: Int
    let id: Int
    let `private`: Bool
    let rate: Int
    let tags: [String]
    let type: Int
    let updatedAt: Int
    let volStatus: Int
}

struct SubjectPlatformDTO: Codable, Sendable {
    let alias: String
    let enableHeader: Bool?
    let id: Int
    let order: Int?
    let searchString: String?
    let sortKeys: [String]?
    let type: String
    let typeCN: String
    let wikiTpl: String?
}

struct SubjectTagDTO: Codable, Sendable {
    let count: Int
    let name: String
}

struct InfoboxItemDTO: Codable, Sendable {
    let key: String
    let values: [InfoboxValueDTO]
}

struct InfoboxValueDTO: Codable, Sendable {
    let k: String?
    let v: String
}


struct BgmEpisodeInfo: Codable, Sendable {
    let id: Int
    let subjectId: Int
    let type: Int
    let ep: Double
    let sort: Double
    let name: String
    let nameCN: String
    let duration: String
    let durationSeconds: Int
    let airdate: String
    let comment: Int
    let desc: String
    let disc: Int

    enum CodingKeys: String, CodingKey {
        case id, type, ep, sort, name, duration, airdate, comment, desc, disc
        case nameCN = "name_cn"
        case subjectId = "subject_id"
        case durationSeconds = "duration_seconds"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.subjectId = try container.decode(Int.self, forKey: .subjectId)
        self.type = try container.decode(Int.self, forKey: .type)
        self.ep = try container.decode(Double.self, forKey: .ep)
        self.sort = try container.decode(Double.self, forKey: .sort)
        self.name = try container.decode(String.self, forKey: .name)
        self.nameCN = try container.decode(String.self, forKey: .nameCN)
        self.duration = try container.decode(String.self, forKey: .duration)
        self.durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        self.airdate = try container.decode(String.self, forKey: .airdate)
        self.comment = try container.decode(Int.self, forKey: .comment)
        self.desc = try container.decode(String.self, forKey: .desc)
        self.disc = try container.decode(Int.self, forKey: .disc)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subjectId, forKey: .subjectId)
        try container.encode(type, forKey: .type)
        try container.encode(ep, forKey: .ep)
        try container.encode(sort, forKey: .sort)
        try container.encode(name, forKey: .name)
        try container.encode(nameCN, forKey: .nameCN)
        try container.encode(duration, forKey: .duration)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(airdate, forKey: .airdate)
        try container.encode(comment, forKey: .comment)
        try container.encode(desc, forKey: .desc)
        try container.encode(disc, forKey: .disc)
    }

    init(id: Int, subjectId: Int, type: Int, ep: Double, sort: Double, name: String, nameCN: String, duration: String, durationSeconds: Int, airdate: String, comment: Int, desc: String, disc: Int) {
        self.id = id
        self.subjectId = subjectId
        self.type = type
        self.ep = ep
        self.sort = sort
        self.name = name
        self.nameCN = nameCN
        self.duration = duration
        self.durationSeconds = durationSeconds
        self.airdate = airdate
        self.comment = comment
        self.desc = desc
        self.disc = disc
    }
}
