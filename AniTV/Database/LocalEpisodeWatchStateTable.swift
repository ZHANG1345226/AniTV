//
//  AniTVDatabase+LocalEpisodeWatchState.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    static let localEpisodeWatchStateSchema = """
    CREATE TABLE "local_episode_watch_state" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "bgm_user_id" INTEGER NOT NULL,
      "episode_id" INTEGER NOT NULL,
      "type" INTEGER NOT NULL DEFAULT 0,
      "updated_at" INTEGER NOT NULL DEFAULT 0,
      "playhead_seconds" INTEGER NOT NULL DEFAULT 0,
      "created_at" TEXT NOT NULL,
      "local_updated_at" TEXT NOT NULL
    ) STRICT
    """

    static func registerLocalEpisodeWatchStateMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create local_episode_watch_state table") { db in
            try #sql(
                """
                CREATE TABLE "local_episode_watch_state" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "bgm_user_id" INTEGER NOT NULL,
                  "episode_id" INTEGER NOT NULL,
                  "type" INTEGER NOT NULL DEFAULT 0,
                  "updated_at" INTEGER NOT NULL DEFAULT 0,
                  "playhead_seconds" INTEGER NOT NULL DEFAULT 0,
                  "created_at" TEXT NOT NULL,
                  "local_updated_at" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Create local_episode_watch_state unique index") { db in
            try #sql(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS "local_episode_watch_state_identity"
                ON "local_episode_watch_state" ("bgm_user_id", "episode_id")
                """
            )
            .execute(db)
        }
    }

    static func upsertLocalEpisodeWatchState(
        bgmUserID: Int,
        episodeID: Int,
        type: Int,
        updatedAt: Int,
        playheadSeconds: Int,
        in database: any DatabaseWriter
    ) async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO "local_episode_watch_state" (
                  "bgm_user_id",
                  "episode_id",
                  "type",
                  "updated_at",
                  "playhead_seconds",
                  "created_at",
                  "local_updated_at"
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT("bgm_user_id", "episode_id") DO UPDATE SET
                  "type" = excluded."type",
                  "updated_at" = excluded."updated_at",
                  "playhead_seconds" = excluded."playhead_seconds",
                  "local_updated_at" = excluded."local_updated_at"
                """,
                arguments: [
                    bgmUserID,
                    episodeID,
                    type,
                    updatedAt,
                    playheadSeconds,
                    now,
                    now
                ]
            )
        }
    }

    static func localEpisodeWatchState(
        bgmUserID: Int,
        episodeID: Int,
        in database: any DatabaseWriter
    ) async throws -> LocalEpisodeWatchState? {
        try await database.read { db in
            try #sql(
                """
                SELECT *
                FROM "local_episode_watch_state"
                WHERE "bgm_user_id" = \(bind: bgmUserID)
                  AND "episode_id" = \(bind: episodeID)
                """,
                as: LocalEpisodeWatchState.self
            )
            .fetchOne(db)
        }
    }

    static func localEpisodeWatchStates(
        bgmUserID: Int,
        episodeIDs: [Int],
        in database: any DatabaseWriter
    ) async throws -> [LocalEpisodeWatchState] {
        let uniqueEpisodeIDs = Array(Set(episodeIDs)).sorted()
        guard !uniqueEpisodeIDs.isEmpty else { return [] }

        return try await database.read { db in
            let placeholders = uniqueEpisodeIDs.map { _ in "?" }.joined(separator: ", ")
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM "local_episode_watch_state"
                WHERE "bgm_user_id" = ?
                  AND "episode_id" IN (\(placeholders))
                """,
                arguments: StatementArguments([bgmUserID] + uniqueEpisodeIDs)
            )

            return rows.map { row in
                LocalEpisodeWatchState(
                    id: row["id"],
                    bgmUserID: row["bgm_user_id"],
                    episodeID: row["episode_id"],
                    type: row["type"],
                    updatedAt: row["updated_at"],
                    playheadSeconds: row["playhead_seconds"],
                    createdAt: row["created_at"],
                    localUpdatedAt: row["local_updated_at"]
                )
            }
        }
    }
}
