//
//  AniTVDatabase+TMDBBackdropCache.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    static let tmdbBackdropCacheSchema = """
    CREATE TABLE "tmdb_backdrop_cache" (
      "tmdb_id" TEXT PRIMARY KEY NOT NULL,
      "image_url" TEXT NOT NULL,
      "updated_at" INTEGER NOT NULL
    ) STRICT
    """

    static func registerTMDBBackdropCacheMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create tmdb_backdrop_cache table") { db in
            try #sql(
                """
                CREATE TABLE "tmdb_backdrop_cache" (
                  "tmdb_id" TEXT PRIMARY KEY NOT NULL,
                  "image_url" TEXT NOT NULL,
                  "updated_at" INTEGER NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
    }

    static func cachedTMDBBackdropURL(
        tmdbID: String,
        maxAge: TimeInterval,
        in database: any DatabaseWriter
    ) async throws -> String? {
        let minUpdatedAt = Int(Date().timeIntervalSince1970 - maxAge)
        return try await database.read { db in
            try #sql(
                """
                SELECT "image_url"
                FROM "tmdb_backdrop_cache"
                WHERE "tmdb_id" = \(bind: tmdbID)
                  AND "updated_at" >= \(bind: minUpdatedAt)
                """,
                as: String.self
            )
            .fetchOne(db)
        }
    }

    static func upsertTMDBBackdropCache(
        tmdbID: String,
        imageURL: String,
        in database: any DatabaseWriter
    ) async throws {
        let now = Int(Date().timeIntervalSince1970)
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO "tmdb_backdrop_cache" (
                  "tmdb_id",
                  "image_url",
                  "updated_at"
                ) VALUES (?, ?, ?)
                ON CONFLICT("tmdb_id") DO UPDATE SET
                  "image_url" = excluded."image_url",
                  "updated_at" = excluded."updated_at"
                """,
                arguments: [tmdbID, imageURL, now]
            )
        }
    }
}
