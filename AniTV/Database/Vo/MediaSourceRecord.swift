//
//  MediaSourceRecord.swift
//  AniTV
//
//  Created by Codex on 2026/5/15.
//

import Foundation
import SQLiteData

@Table("media_sources")
nonisolated struct MediaSourceRecord: Equatable, Identifiable {
    let id: Int

    @Column("factory_id")
    var factoryID: String

    var version: Int
    var arguments: String
    var name: String
    var description: String

    @Column("icon_url")
    var iconURL: String

    @Column("subscription_id")
    var subscriptionID: Int

    @Column("created_at")
    var createdAt: Date

    @Column("updated_at")
    var updatedAt: Date
}
