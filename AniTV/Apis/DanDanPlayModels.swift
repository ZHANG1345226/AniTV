//
//  DanDanPlayModels.swift
//  AniTV
//
//  Created by Codex on 2026/7/26.
//

import Foundation

// MARK: - API Responses

struct DanDanPlayBangumiDetailsResponse: Codable {
    let errorCode: Int?
    let success: Bool?
    let errorMessage: String?
    let bangumi: DanDanPlayBangumi?
}

struct DanDanPlayBangumi: Codable {
    let bangumiId: String?
    let animeId: Int?
    let animeTitle: String
    let episodes: [DanDanPlayEpisode]
}

struct DanDanPlayEpisode: Codable {
    let episodeId: Int
    let episodeTitle: String
    let episodeNumber: String?
}

struct DanDanPlayCommentResponse: Codable {
    let count: Int?
    let comments: [DanDanPlayComment]
}

struct DanDanPlayComment: Codable {
    let cid: Int
    let p: String
    let m: String
}
