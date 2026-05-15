//
//  BangumiDataRecord.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import SQLiteData

@Table("bangumi_data")
nonisolated struct BangumiDataRecord: Equatable, Identifiable {
    let id: Int

    @Column("bangumi_id")
    var bangumiID: String

    var title: String

    @Column("title_translate")
    var titleTranslate: String

    var type: String
    var lang: String
    var begin: String
    var broadcast: String
    var end: String
    var sites: String
}
