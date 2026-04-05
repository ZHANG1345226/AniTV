//
//  BgmDataPayload.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation

struct BgmDataSite: Codable, Equatable {
    let site: String
    let id: String?
}

struct BgmDataItem: Codable, Equatable {
    let title: String
    let titleTranslate: [String: [String]]
    let type: String
    let lang: String
    let begin: String
    let broadcast: String?
    let end: String?
    let sites: [BgmDataSite]

    var bangumiID: String? {
        sites.first { $0.site == "bangumi" && !($0.id?.isEmpty ?? true) }?.id
    }
}

struct BgmDataResponse: Codable, Equatable {
    let items: [BgmDataItem]
}
