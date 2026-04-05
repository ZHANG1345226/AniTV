//
//  TMDBBackdropCache.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import SQLiteData

@Table("tmdb_backdrop_cache")
nonisolated struct TMDBBackdropCache: Equatable, Identifiable {
    @Column(primaryKey: true)
    var tmdbID: String

    @Column("image_url")
    var imageURL: String

    @Column("updated_at")
    var updatedAt: Int

    var id: String { tmdbID }
}
