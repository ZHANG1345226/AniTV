//
//  AniTVDatabase+SystemSettings.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    nonisolated static let playbackCompletionThresholdSettingKey = "player.playback_completion_threshold"
    nonisolated static let defaultPlaybackCompletionThreshold = 0.9
    nonisolated static let bangumiOAuthRedirectURISettingKey = "bangumi_oauth_redirect_uri"
    nonisolated static let bangumiOAuthRefreshBlockedSettingKey = "bangumi_oauth_refresh_blocked"

    nonisolated static let systemSettingsSchema = """
    CREATE TABLE "system_settings" (
      "key" TEXT PRIMARY KEY NOT NULL,
      "value" TEXT NOT NULL,
      "value_type" TEXT NOT NULL DEFAULT 'string',
      "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT
    """

    nonisolated static func registerSystemSettingsMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create system_settings table") { db in
            try #sql(
                """
                CREATE TABLE "system_settings" (
                  "key" TEXT PRIMARY KEY NOT NULL,
                  "value" TEXT NOT NULL,
                  "value_type" TEXT NOT NULL DEFAULT 'string',
                  "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Seed playback completion threshold setting") { db in
            try upsertSystemSetting(
                key: playbackCompletionThresholdSettingKey,
                value: String(defaultPlaybackCompletionThreshold),
                valueType: "double",
                in: db
            )
        }
    }

    nonisolated static func systemSettingValue(
        forKey key: String,
        in database: any DatabaseWriter
    ) async throws -> String? {
        try await database.read { db in
            try #sql(
                """
                SELECT "value"
                FROM "system_settings"
                WHERE "key" = \(bind: key)
                LIMIT 1
                """,
                as: String.self
            )
            .fetchOne(db)
        }
    }

    nonisolated static func upsertSystemSetting(
        key: String,
        value: String,
        valueType: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO "system_settings" ("key", "value", "value_type", "created_at", "updated_at")
            VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT("key") DO UPDATE SET
              "value" = excluded."value",
              "value_type" = excluded."value_type",
              "updated_at" = CURRENT_TIMESTAMP
            """,
            arguments: [key, value, valueType]
        )
    }

    nonisolated static func playbackCompletionThreshold(
        in database: any DatabaseWriter
    ) async throws -> Double {
        let value = try await systemSettingValue(
            forKey: playbackCompletionThresholdSettingKey,
            in: database
        )
        guard let value, let threshold = Double(value), threshold > 0, threshold <= 1 else {
            return defaultPlaybackCompletionThreshold
        }
        return threshold
    }

    nonisolated static func bangumiOAuthRedirectURI(
        in database: any DatabaseWriter
    ) async throws -> String? {
        let value = try await systemSettingValue(
            forKey: bangumiOAuthRedirectURISettingKey,
            in: database
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty else { return nil }
        return value
    }

    nonisolated static func setBangumiOAuthRedirectURI(
        _ redirectURI: String,
        in database: any DatabaseWriter
    ) async throws {
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRedirectURI.isEmpty else { return }

        try await database.write { db in
            try upsertSystemSetting(
                key: bangumiOAuthRedirectURISettingKey,
                value: normalizedRedirectURI,
                valueType: "string",
                in: db
            )
        }
    }

    nonisolated static func isBangumiOAuthRefreshBlocked(
        in database: any DatabaseWriter
    ) async throws -> Bool {
        let value = try await systemSettingValue(
            forKey: bangumiOAuthRefreshBlockedSettingKey,
            in: database
        )
        return value == "1"
    }

    nonisolated static func setBangumiOAuthRefreshBlocked(
        _ isBlocked: Bool,
        in database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try upsertSystemSetting(
                key: bangumiOAuthRefreshBlockedSettingKey,
                value: isBlocked ? "1" : "0",
                valueType: "boolean",
                in: db
            )
        }
    }
}
