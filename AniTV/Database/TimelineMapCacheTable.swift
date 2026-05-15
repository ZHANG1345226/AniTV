//
//  AniTVDatabase+TimelineMapCache.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    static func registerTimelineMapCacheMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create timeline_map_cache table") { db in
            try #sql(
                """
                CREATE TABLE "timeline_map_cache" (
                  "cache_key" TEXT PRIMARY KEY NOT NULL,
                  "payload" TEXT NOT NULL,
                  "updated_at" INTEGER NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
    }

    static func cachedTimelineMap(
        cacheKey: String,
        maxAge: TimeInterval,
        in database: any DatabaseWriter
    ) async throws -> TimelineDayMap? {
        let minUpdatedAt = Int(Date().timeIntervalSince1970 - maxAge)
        let payload: String? = try await database.read { db in
            try #sql(
                """
                SELECT "payload"
                FROM "timeline_map_cache"
                WHERE "cache_key" = \(bind: cacheKey)
                  AND "updated_at" >= \(bind: minUpdatedAt)
                """,
                as: String.self
            )
            .fetchOne(db)
        }

        guard let payload else { return nil }
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(TimelineDayMap.self, from: data)
    }

    static func upsertTimelineMapCache(
        cacheKey: String,
        map: TimelineDayMap,
        in database: any DatabaseWriter
    ) async throws {
        let payloadData = try JSONEncoder().encode(map)
        guard let payload = String(data: payloadData, encoding: .utf8) else { return }

        let now = Int(Date().timeIntervalSince1970)
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO "timeline_map_cache" (
                  "cache_key",
                  "payload",
                  "updated_at"
                ) VALUES (?, ?, ?)
                ON CONFLICT("cache_key") DO UPDATE SET
                  "payload" = excluded."payload",
                  "updated_at" = excluded."updated_at"
                """,
                arguments: [cacheKey, payload, now]
            )
        }
    }
}
