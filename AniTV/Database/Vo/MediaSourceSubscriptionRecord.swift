//
//  MediaSourceSubscriptionRecord.swift
//  AniTV
//
//  Created by Codex on 2026/5/15.
//

import Foundation
import SQLiteData

@Table("media_source_subscriptions")
nonisolated struct MediaSourceSubscriptionRecord: Equatable, Identifiable {
    let id: Int
    var url: String

    @Column("last_fetched_at")
    var lastFetchedAtTimestamp: Int?

    @Column("created_at")
    var createdAt: Date

    @Column("updated_at")
    var updatedAt: Date

    var lastFetchedAt: Date? {
        guard let lastFetchedAtTimestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastFetchedAtTimestamp))
    }
}
