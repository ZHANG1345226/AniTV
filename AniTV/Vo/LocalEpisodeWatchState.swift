//
//  LocalEpisodeWatchState.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import SQLiteData

@Table("local_episode_watch_state")
nonisolated struct LocalEpisodeWatchState: Equatable, Identifiable {
    let id: Int

    @Column("bgm_user_id")
    var bgmUserID: Int

    @Column("episode_id")
    var episodeID: Int

    var type: Int

    @Column("updated_at")
    var updatedAt: Int

    @Column("playhead_seconds")
    var playheadSeconds: Int

    @Column("created_at")
    var createdAt: Date

    @Column("local_updated_at")
    var localUpdatedAt: Date
}
