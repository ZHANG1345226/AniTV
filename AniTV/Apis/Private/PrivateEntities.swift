//
//  PrivateEntities.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// MARK: - API Response Root
nonisolated
struct PrivateTrendingResponse: Codable {
    let data: [AnimeSubject]
}

// MARK: - Anime Subject Item
struct AnimeSubject: Codable, Identifiable, Hashable {
    let id: Int
    let title: String // 日文原名
    let info: String
    let score: Double
    let titleTranslate: TitleTranslate
    let type: String // "tv", "web" 等
    let lang: String
    let begin: String // ISO8601 字符串，例如 "2026-01-16T14:00:00.000Z"
    let broadcast: String
    let end: String
    let backdrop: URL?
    
    // MARK: - Computed Properties for UI
    
    /// 智能获取显示标题：优先显示中文，没有中文显示日文
    var displayName: String {
        var result = title
        // 这里只是简单的逻辑，实际可以根据 Locale.current.identifier 判断是简中还是繁中
        if !titleTranslate.zhHans.isEmpty {
            result = titleTranslate.zhHans
        }else if !titleTranslate.zhHant.isEmpty {
            result =  titleTranslate.zhHant
        }
        
        if result.count >= 18{
            result = result.prefix(16) + "..."
        }
        return result
    }
    
    /// 将 ISO8601 字符串转为 Date 对象
    var startDate: Date? {
        guard !begin.isEmpty else {
            return inferFromSerieInfo(info: info).firstAiredAt
        }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: begin) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: begin) {
            return date
        }
        return inferFromSerieInfo(info: info).firstAiredAt
    }

    var endDate: Date? {
        guard !end.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: end) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: end)
    }
    
    /// 格式化后的评分字符串 (保留1位小数)
    var scoreString: String {
        return String(format: "%.1f", score)
    }
    
    var isMovie: Bool {
        if type == "movie"{
            return true
        }
        return inferEpsodeCount(info: info) == 1
    }
    
    var displayOriginalTitle: Bool{
        return displayName != title
    }
    
    static func == (lhs: AnimeSubject, rhs: AnimeSubject) -> Bool {
            lhs.id == rhs.id
        }
        
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Translations
struct TitleTranslate: Codable {
    let en: String
    let zhHans: String
    let zhHant: String
    
    // 使用 CodingKeys 处理 JSON 中的连字符 key
    enum CodingKeys: String, CodingKey {
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
    }
}
