//
//  Entities.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// MARK: - Root Response
nonisolated
struct TrendingResponse: Codable, Sendable {
    let data: [TrendingSubjectDTO]
    let total: Int
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
    func encode(to encoder: Encoder) throws {
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
    
    func encode(to encoder: Encoder) throws {
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
