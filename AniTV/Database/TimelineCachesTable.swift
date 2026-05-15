//
//  AniTVDatabase+TimelineCaches.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    static let timelineBangumiSubjectCacheSchema = """
    CREATE TABLE "timeline_bangumi_subject_cache" (
      "bangumi_id" TEXT PRIMARY KEY NOT NULL,
      "name" TEXT NOT NULL DEFAULT '',
      "name_cn" TEXT NOT NULL DEFAULT '',
      "images_json" TEXT NOT NULL DEFAULT '{}',
      "is_complete" INTEGER NOT NULL DEFAULT 0,
      "updated_at" INTEGER NOT NULL
    ) STRICT
    """

    static let timelineBangumiEpisodeCacheSchema = """
    CREATE TABLE "timeline_bangumi_episode_cache" (
      "episode_id" INTEGER PRIMARY KEY NOT NULL,
      "bangumi_id" TEXT NOT NULL,
      "airdate" TEXT NOT NULL DEFAULT '',
      "name" TEXT NOT NULL DEFAULT '',
      "name_cn" TEXT NOT NULL DEFAULT '',
      "sort" REAL NOT NULL DEFAULT 0,
      "expires_at" INTEGER,
      "cached_at" INTEGER NOT NULL
    ) STRICT
    """

    static func registerTimelineBangumiSubjectCacheMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create timeline_bangumi_subject_cache table") { db in
            try #sql(
                """
                CREATE TABLE "timeline_bangumi_subject_cache" (
                  "bangumi_id" TEXT PRIMARY KEY NOT NULL,
                  "name" TEXT NOT NULL DEFAULT '',
                  "name_cn" TEXT NOT NULL DEFAULT '',
                  "images_json" TEXT NOT NULL DEFAULT '{}',
                  "is_complete" INTEGER NOT NULL DEFAULT 0,
                  "updated_at" INTEGER NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
    }

    static func registerTimelineBangumiEpisodeCacheMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create timeline_bangumi_episode_cache table") { db in
            try #sql(
                """
                CREATE TABLE "timeline_bangumi_episode_cache" (
                  "episode_id" INTEGER PRIMARY KEY NOT NULL,
                  "bangumi_id" TEXT NOT NULL,
                  "airdate" TEXT NOT NULL DEFAULT '',
                  "name" TEXT NOT NULL DEFAULT '',
                  "name_cn" TEXT NOT NULL DEFAULT '',
                  "sort" REAL NOT NULL DEFAULT 0,
                  "expires_at" INTEGER,
                  "cached_at" INTEGER NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Create timeline_bangumi_episode_cache index") { db in
            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "timeline_bangumi_episode_cache_subject_id"
                ON "timeline_bangumi_episode_cache" ("bangumi_id")
                """
            )
            .execute(db)
        }
    }

    static func fetchAllTimelineBangumiSubjectCaches(
        in database: any DatabaseWriter
    ) async throws -> [TimelineBangumiSubjectCacheRow] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT
                  "bangumi_id",
                  "name",
                  "name_cn",
                  "images_json",
                  "is_complete",
                  "updated_at"
                FROM "timeline_bangumi_subject_cache"
                """
            )
            .map { row in
                TimelineBangumiSubjectCacheRow(
                    bangumiID: row["bangumi_id"],
                    name: row["name"],
                    nameCN: row["name_cn"],
                    imagesJSON: row["images_json"],
                    isComplete: (row["is_complete"] as Int64) != 0,
                    updatedAt: row["updated_at"]
                )
            }
        }
    }

    static func fetchAllTimelineBangumiEpisodeCaches(
        in database: any DatabaseWriter
    ) async throws -> [TimelineBangumiEpisodeCacheRow] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT
                  "episode_id",
                  "bangumi_id",
                  "airdate",
                  "name",
                  "name_cn",
                  "sort",
                  "expires_at",
                  "cached_at"
                FROM "timeline_bangumi_episode_cache"
                """
            )
            .map { row in
                TimelineBangumiEpisodeCacheRow(
                    episodeID: row["episode_id"],
                    bangumiID: row["bangumi_id"],
                    airdate: row["airdate"],
                    name: row["name"],
                    nameCN: row["name_cn"],
                    sort: row["sort"],
                    expiresAt: row["expires_at"],
                    cachedAt: row["cached_at"]
                )
            }
        }
    }

    static func upsertTimelineBangumiSubjectCaches(
        _ rows: [TimelineBangumiSubjectCacheRow],
        in database: any DatabaseWriter
    ) async throws {
        guard !rows.isEmpty else { return }

        try await database.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO "timeline_bangumi_subject_cache" (
                      "bangumi_id",
                      "name",
                      "name_cn",
                      "images_json",
                      "is_complete",
                      "updated_at"
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT("bangumi_id") DO UPDATE SET
                      "name" = excluded."name",
                      "name_cn" = excluded."name_cn",
                      "images_json" = excluded."images_json",
                      "is_complete" = excluded."is_complete",
                      "updated_at" = excluded."updated_at"
                    """,
                    arguments: [
                        row.bangumiID,
                        row.name,
                        row.nameCN,
                        row.imagesJSON,
                        row.isComplete ? 1 : 0,
                        row.updatedAt
                    ]
                )
            }
        }
    }

    static func upsertTimelineBangumiEpisodeCaches(
        _ rows: [TimelineBangumiEpisodeCacheRow],
        in database: any DatabaseWriter
    ) async throws {
        guard !rows.isEmpty else { return }

        try await database.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO "timeline_bangumi_episode_cache" (
                      "episode_id",
                      "bangumi_id",
                      "airdate",
                      "name",
                      "name_cn",
                      "sort",
                      "expires_at",
                      "cached_at"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT("episode_id") DO UPDATE SET
                      "bangumi_id" = excluded."bangumi_id",
                      "airdate" = excluded."airdate",
                      "name" = excluded."name",
                      "name_cn" = excluded."name_cn",
                      "sort" = excluded."sort",
                      "expires_at" = excluded."expires_at",
                      "cached_at" = excluded."cached_at"
                    """,
                    arguments: [
                        row.episodeID,
                        row.bangumiID,
                        row.airdate,
                        row.name,
                        row.nameCN,
                        row.sort,
                        row.expiresAt,
                        row.cachedAt
                    ]
                )
            }
        }
    }
}
