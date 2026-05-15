//
//  CachedUserCollectionsTable.swift
//  AniTV
//
//  Created by Codex on 2026/5/4.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    static func registerCachedUserCollectionsMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create cached_user_collections table") { db in
            try #sql(
                """
                CREATE TABLE "cached_user_collections" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "bgm_user_id" INTEGER NOT NULL,
                  "subject_id" INTEGER NOT NULL,
                  "collection_type" INTEGER NOT NULL,
                  "ep_status" INTEGER NOT NULL DEFAULT 0,
                  "updated_at" TEXT NOT NULL,
                  "subject_json" TEXT NOT NULL,
                  "cached_at" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Create cached_user_collections indexes") { db in
            try #sql(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS "cached_user_collections_identity"
                ON "cached_user_collections" ("bgm_user_id", "subject_id")
                """
            )
            .execute(db)

            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "cached_user_collections_lookup"
                ON "cached_user_collections" ("bgm_user_id", "collection_type", "cached_at" DESC)
                """
            )
            .execute(db)
        }
    }

    static func cachedUserCollections(
        bgmUserID: Int,
        collectionType: SubjectCollectionType,
        in database: any DatabaseWriter
    ) async throws -> [UserSubjectCollectionDTO] {
        let rows: [Row] = try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT
                  "subject_id",
                  "collection_type",
                  "ep_status",
                  "updated_at",
                  "subject_json"
                FROM "cached_user_collections"
                WHERE "bgm_user_id" = ?
                  AND "collection_type" = ?
                ORDER BY "cached_at" DESC
                """,
                arguments: StatementArguments([
                    bgmUserID,
                    collectionType.rawValue
                ])
            )
        }

        let decoder = JSONDecoder()
        return try rows.compactMap { row in
            let subjectJSON: String = row["subject_json"]
            guard let subjectData = subjectJSON.data(using: .utf8) else { return nil }
            let subject = try decoder.decode(BgmCollectionSubjectDTO.self, from: subjectData)
            return UserSubjectCollectionDTO(
                subjectID: row["subject_id"],
                subjectType: 2,
                rate: 0,
                type: row["collection_type"],
                comment: nil,
                tags: [],
                epStatus: row["ep_status"],
                volStatus: 0,
                updatedAt: row["updated_at"],
                isPrivate: false,
                subject: subject
            )
        }
    }

    static func replaceCachedUserCollections(
        _ collections: [UserSubjectCollectionDTO],
        bgmUserID: Int,
        collectionType: SubjectCollectionType,
        in database: any DatabaseWriter
    ) async throws {
        let now = Date()
        let encoder = JSONEncoder()

        try await database.write { db in
            try db.execute(
                sql: """
                DELETE FROM "cached_user_collections"
                WHERE "bgm_user_id" = ?
                  AND "collection_type" = ?
                """,
                arguments: [
                    bgmUserID,
                    collectionType.rawValue
                ]
            )

            for collection in collections {
                guard let subject = collection.subject else { continue }
                let subjectData = try encoder.encode(subject)
                guard let subjectJSON = String(data: subjectData, encoding: .utf8) else { continue }

                try db.execute(
                    sql: """
                    INSERT INTO "cached_user_collections" (
                      "bgm_user_id",
                      "subject_id",
                      "collection_type",
                      "ep_status",
                      "updated_at",
                      "subject_json",
                      "cached_at"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        bgmUserID,
                        collection.subjectID,
                        collection.type,
                        collection.epStatus,
                        collection.updatedAt,
                        subjectJSON,
                        now
                    ]
                )
            }
        }
    }

    static func cachedContinueWatchingCollections(
        bgmUserID: Int,
        in database: any DatabaseWriter
    ) async throws -> [UserSubjectCollectionDTO] {
        try await cachedUserCollections(
            bgmUserID: bgmUserID,
            collectionType: .watching,
            in: database
        )
    }

    static func replaceCachedContinueWatchingCollections(
        _ collections: [UserSubjectCollectionDTO],
        bgmUserID: Int,
        in database: any DatabaseWriter
    ) async throws {
        try await replaceCachedUserCollections(
            collections,
            bgmUserID: bgmUserID,
            collectionType: .watching,
            in: database
        )
    }
}
