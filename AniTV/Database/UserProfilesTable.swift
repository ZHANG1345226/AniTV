//
//  AniTVDatabase+UserProfiles.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    private enum StorageError: Error {
        case insertedProfileMissing
        case updatedProfileMissing
    }

    static let userProfilesSchema = """
    CREATE TABLE "user_profiles" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "bgm_user_id" INTEGER,
      "username" TEXT,
      "nickname" TEXT,
      "avatar" TEXT,
      "access_token" TEXT,
      "refresh_token" TEXT,
      "token_type" TEXT,
      "last_used_at" TEXT NOT NULL,
      "expires_at" TEXT NOT NULL,
      "created_at" TEXT NOT NULL,
      "updated_at" TEXT NOT NULL
    ) STRICT
    """

    static func registerUserProfilesMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create user_profiles table") { db in
            try #sql(
                """
                CREATE TABLE "user_profiles" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "bgm_user_id" INTEGER,
                  "username" TEXT,
                  "nickname" TEXT,
                  "avatar" TEXT,
                  "access_token" TEXT,
                  "refresh_token" TEXT,
                  "token_type" TEXT,
                  "last_used_at" TEXT NOT NULL,
                  "expires_at" TEXT NOT NULL,
                  "created_at" TEXT NOT NULL,
                  "updated_at" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Create user_profiles indexes") { db in
            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "user_profiles_last_used_at"
                ON "user_profiles" ("last_used_at" DESC)
                """
            )
            .execute(db)
            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "user_profiles_bgm_user_id"
                ON "user_profiles" ("bgm_user_id")
                """
            )
            .execute(db)
        }
    }

    static func currentUserProfile(in database: any DatabaseWriter) async throws -> UserProfile? {
        try await database.read { db in
            try #sql(
                """
                SELECT *
                FROM "user_profiles"
                ORDER BY "last_used_at" DESC
                LIMIT 1
                """,
                as: UserProfile.self
            )
            .fetchOne(db)
        }
    }

    static func logoutCurrentUser(in database: any DatabaseWriter) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM user_profiles")
        }
        _ = try await insertGuestUserProfile(in: database)
    }

    static func insertGuestUserProfile(in database: any DatabaseWriter) async throws -> UserProfile {
        let now = Date()
        let guestExpiry = Date(timeIntervalSince1970: 0)
        return try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO "user_profiles" (
                  "bgm_user_id",
                  "username",
                  "nickname",
                  "avatar",
                  "access_token",
                  "refresh_token",
                  "token_type",
                  "last_used_at",
                  "expires_at",
                  "created_at",
                  "updated_at"
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    nil as Int?,
                    nil as String?,
                    nil as String?,
                    nil as String?,
                    nil as String?,
                    nil as String?,
                    nil as String?,
                    now,
                    guestExpiry,
                    now,
                    now
                ]
            )

            guard let profile = try #sql(
                """
                SELECT *
                FROM "user_profiles"
                WHERE "id" = last_insert_rowid()
                """,
                as: UserProfile.self
            )
            .fetchOne(db) else {
                throw StorageError.insertedProfileMissing
            }

            return profile
        }
    }

    static func upsertCurrentUserProfile(
        bgmUserID: Int,
        username: String,
        nickname: String,
        avatar: String?,
        accessToken: String,
        refreshToken: String?,
        tokenType: String?,
        expiresAt: Date,
        in database: any DatabaseWriter
    ) async throws -> UserProfile {
        let now = Date()
        return try await database.write { db in
            if let current = try #sql(
                """
                SELECT *
                FROM "user_profiles"
                ORDER BY "last_used_at" DESC
                LIMIT 1
                """,
                as: UserProfile.self
            )
            .fetchOne(db) {
                try db.execute(
                    sql: """
                    UPDATE "user_profiles"
                    SET
                      "bgm_user_id" = ?,
                      "username" = ?,
                      "nickname" = ?,
                      "avatar" = ?,
                      "access_token" = ?,
                      "refresh_token" = ?,
                      "token_type" = ?,
                      "last_used_at" = ?,
                      "expires_at" = ?,
                      "updated_at" = ?
                    WHERE "id" = ?
                    """,
                    arguments: [
                        bgmUserID,
                        username,
                        nickname,
                        avatar,
                        accessToken,
                        refreshToken,
                        tokenType,
                        now,
                        expiresAt,
                        now,
                        current.id
                    ]
                )

                guard let updated = try #sql(
                    """
                    SELECT *
                    FROM "user_profiles"
                    WHERE "id" = \(bind: current.id)
                    """,
                    as: UserProfile.self
                )
                .fetchOne(db) else {
                    throw StorageError.updatedProfileMissing
                }

                return updated
            }

            try db.execute(
                sql: """
                INSERT INTO "user_profiles" (
                  "bgm_user_id",
                  "username",
                  "nickname",
                  "avatar",
                  "access_token",
                  "refresh_token",
                  "token_type",
                  "last_used_at",
                  "expires_at",
                  "created_at",
                  "updated_at"
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    bgmUserID,
                    username,
                    nickname,
                    avatar,
                    accessToken,
                    refreshToken,
                    tokenType,
                    now,
                    expiresAt,
                    now,
                    now
                ]
            )

            guard let inserted = try #sql(
                """
                SELECT *
                FROM "user_profiles"
                WHERE "id" = last_insert_rowid()
                """,
                as: UserProfile.self
            )
            .fetchOne(db) else {
                throw StorageError.insertedProfileMissing
            }

            return inserted
        }
    }
}
