//
//  MediaSourcesTable.swift
//  AniTV
//
//  Created by Codex on 2026/5/15.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    nonisolated private static let mediaSourceRefreshMaxAge: TimeInterval = 24 * 60 * 60

    static func registerMediaSourceMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create media_source_subscriptions table") { db in
            try #sql(
                """
                CREATE TABLE "media_source_subscriptions" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "url" TEXT NOT NULL,
                  "last_fetched_at" INTEGER,
                  "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Create media_source_subscriptions unique index") { db in
            try #sql(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS "media_source_subscriptions_url"
                ON "media_source_subscriptions" ("url")
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Create media_sources table") { db in
            try #sql(
                """
                CREATE TABLE "media_sources" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "factory_id" TEXT NOT NULL,
                  "version" INTEGER NOT NULL,
                  "arguments" TEXT NOT NULL,
                  "name" TEXT NOT NULL DEFAULT '',
                  "description" TEXT NOT NULL DEFAULT '',
                  "icon_url" TEXT NOT NULL DEFAULT '',
                  "subscription_id" INTEGER NOT NULL,
                  "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY("subscription_id") REFERENCES "media_source_subscriptions"("id") ON DELETE CASCADE
                ) STRICT
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Create media_sources subscription index") { db in
            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "media_sources_subscription_id"
                ON "media_sources" ("subscription_id")
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Seed default media source subscription") { db in
            try db.execute(
                sql: """
                INSERT INTO "media_source_subscriptions" ("url", "created_at", "updated_at")
                VALUES (?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                ON CONFLICT("url") DO UPDATE SET
                  "updated_at" = CURRENT_TIMESTAMP
                """,
                arguments: [MediaSourceConfigLoader.defaultSubscriptionURL.absoluteString]
            )
        }
    }

    static func isMediaSourceEmpty(in database: any DatabaseWriter) async throws -> Bool {
        try await database.read { db in
            let count = try #sql(
                """
                SELECT COUNT(*) FROM "media_sources"
                """,
                as: Int.self
            )
            .fetchOne(db) ?? 0
            return count == 0
        }
    }

    static func shouldRefreshMediaSources(
        in database: any DatabaseWriter,
        maxAge: TimeInterval = mediaSourceRefreshMaxAge,
        now: Date = Date()
    ) async throws -> Bool {
        if try await isMediaSourceEmpty(in: database) {
            print("[AniTVDatabase] media_sources table is empty, refresh required")
            return true
        }

        guard let subscription = try await defaultMediaSourceSubscription(in: database) else {
            print("[AniTVDatabase] Default media source subscription missing, refresh required")
            return true
        }

        guard let lastFetchedAt = subscription.lastFetchedAt else {
            print("[AniTVDatabase] Missing media source refresh timestamp, refresh required")
            return true
        }

        let age = now.timeIntervalSince(lastFetchedAt)
        let shouldRefresh = age >= maxAge
        // print("[AniTVDatabase] media sources last refreshed at \(lastFetchedAt), age: \(age)s, should refresh: \(shouldRefresh)")
        return shouldRefresh
    }

    static func refreshMediaSourcesIfNeeded(in database: DatabaseQueue) async throws -> Bool {
        guard let subscription = try await defaultMediaSourceSubscription(in: database) else {
            throw MediaSourceConfigLoaderError.invalidResponse
        }

        let response = try await MediaSourceConfigLoader.downloadResponse(from: URL(string: subscription.url)!)
        print("[AniTVDatabase] Downloaded \(response.exportedMediaSourceDataList.mediaSources.count) media sources from \(subscription.url)")
        try await replaceMediaSources(
            response.exportedMediaSourceDataList.mediaSources,
            subscriptionID: subscription.id,
            fetchedAt: Date(),
            in: database
        )
        return true
    }

    static func fetchMediaSourceConfigs(
        in database: any DatabaseWriter
    ) async throws -> [MediaSourceConfig] {
        let rows: [(Int, String, String)] = try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT "id", "factory_id", "arguments"
                FROM "media_sources"
                ORDER BY "id" ASC
                """
            ).map { row in
                (
                    row["id"] as Int,
                    row["factory_id"] as String,
                    row["arguments"] as String
                )
            }
        }

        return rows.compactMap { id, factoryID, argumentsJSONString in
            guard factoryID == SelectorMediaSourceCodec.factoryId.value else {
                print("[AniTVDatabase] Skipping unsupported media source factory '\(factoryID)' for row \(id)")
                return nil
            }

            guard let data = argumentsJSONString.data(using: .utf8) else {
                print("[AniTVDatabase] Failed to convert media source arguments to Data for row \(id)")
                return nil
            }

            do {
                let arguments = try JSONDecoder().decode(SelectorMediaSourceArguments.self, from: data)
                return MediaSourceConfig(serializedArguments: data, arguments: arguments)
            } catch {
                print("[AniTVDatabase] Failed to decode media source arguments for row \(id): \(error)")
                return nil
            }
        }
    }

    private static func defaultMediaSourceSubscription(
        in database: any DatabaseWriter
    ) async throws -> MediaSourceSubscriptionRecord? {
        try await database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                  "id",
                  "url",
                  "last_fetched_at",
                  "created_at",
                  "updated_at"
                FROM "media_source_subscriptions"
                WHERE "url" = ?
                LIMIT 1
                """,
                arguments: [MediaSourceConfigLoader.defaultSubscriptionURL.absoluteString]
            )

            guard let row else { return nil }
            return MediaSourceSubscriptionRecord(
                id: row["id"],
                url: row["url"],
                lastFetchedAtTimestamp: row["last_fetched_at"],
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    private static func replaceMediaSources(
        _ sources: [ExportedMediaSource],
        subscriptionID: Int,
        fetchedAt: Date,
        in database: DatabaseQueue
    ) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                DELETE FROM "media_sources"
                WHERE "subscription_id" = ?
                """,
                arguments: [subscriptionID]
            )

            for source in sources {
                let argumentsJSONString = try MediaSourceConfigLoader.makeArgumentsJSONString(from: source.arguments)
                try db.execute(
                    sql: """
                    INSERT INTO "media_sources" (
                      "factory_id",
                      "version",
                      "arguments",
                      "name",
                      "description",
                      "icon_url",
                      "subscription_id",
                      "created_at",
                      "updated_at"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """,
                    arguments: [
                        source.factoryId,
                        source.version,
                        argumentsJSONString,
                        source.arguments.name,
                        source.arguments.description,
                        source.arguments.iconUrl,
                        subscriptionID
                    ]
                )
            }

            try db.execute(
                sql: """
                UPDATE "media_source_subscriptions"
                SET "last_fetched_at" = ?,
                    "updated_at" = CURRENT_TIMESTAMP
                WHERE "id" = ?
                """,
                arguments: [Int(fetchedAt.timeIntervalSince1970), subscriptionID]
            )
        }
    }
}
