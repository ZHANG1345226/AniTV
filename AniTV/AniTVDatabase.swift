//
//  AniTVDatabase.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import SQLiteData

enum AniTVDatabase {
    private static let bangumiDataURLs = [
        URL(string: "https://cdn.jsdelivr.net/npm/bangumi-data@0.3/dist/data.json")!,
        URL(string: "https://unpkg.com/bangumi-data@0.3/dist/data.json")!
    ]

    static let systemSettingsSchema = """
    CREATE TABLE "system_settings" (
      "key" TEXT PRIMARY KEY NOT NULL,
      "value" TEXT NOT NULL,
      "value_type" TEXT NOT NULL DEFAULT 'string',
      "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT
    """

    static let bangumiDataSchema = """
    CREATE TABLE "bangumi_data" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "bangumi_id" TEXT NOT NULL,
      "title" TEXT NOT NULL,
      "title_translate" TEXT NOT NULL DEFAULT '{}',
      "type" TEXT NOT NULL DEFAULT '',
      "lang" TEXT NOT NULL DEFAULT '',
      "begin" TEXT NOT NULL DEFAULT '',
      "broadcast" TEXT NOT NULL DEFAULT '',
      "end" TEXT NOT NULL DEFAULT '',
      "sites" TEXT NOT NULL DEFAULT '[]'
    ) STRICT
    """

    static let tmdbBackdropCacheSchema = """
    CREATE TABLE "tmdb_backdrop_cache" (
      "tmdb_id" TEXT PRIMARY KEY NOT NULL,
      "image_url" TEXT NOT NULL,
      "updated_at" INTEGER NOT NULL
    ) STRICT
    """

    static func makeDefaultDatabase() throws -> DatabaseQueue {
        let databaseURL = try databaseURL()
        let database = try DatabaseQueue(path: databaseURL.path)

        var migrator = DatabaseMigrator()
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
        migrator.registerMigration("Create bangumi_data table") { db in
            try #sql(
                """
                CREATE TABLE "bangumi_data" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "bangumi_id" TEXT NOT NULL,
                  "title" TEXT NOT NULL,
                  "title_translate" TEXT NOT NULL DEFAULT '{}',
                  "type" TEXT NOT NULL DEFAULT '',
                  "lang" TEXT NOT NULL DEFAULT '',
                  "begin" TEXT NOT NULL DEFAULT '',
                  "broadcast" TEXT NOT NULL DEFAULT '',
                  "end" TEXT NOT NULL DEFAULT '',
                  "sites" TEXT NOT NULL DEFAULT '[]'
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Create bangumi_data unique index") { db in
            try #sql(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS "bangumi_data_identity"
                ON "bangumi_data" ("bangumi_id")
                """
            )
            .execute(db)
        }
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
        try migrator.migrate(database)
        return database
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
                arguments: [
                    tmdbID,
                    imageURL,
                    now
                ]
            )
        }
    }

    static func isBangumiDataEmpty(in database: DatabaseQueue) async throws -> Bool {
        try await database.read { db in
            let count = try #sql(
                """
                SELECT COUNT(*) FROM "bangumi_data"
                """,
                as: Int.self
            )
            .fetchOne(db) ?? 0
            return count == 0
        }
    }

    static func tmdbIDForBangumiID(
        _ bangumiID: String,
        in database: any DatabaseWriter
    ) async throws -> String? {
        try await database.read { db in
            try #sql(
                """
                SELECT json_extract(site.value, '$.id')
                FROM "bangumi_data"
                JOIN json_each("bangumi_data"."sites") AS site
                WHERE "bangumi_data"."bangumi_id" = \(bind: bangumiID)
                  AND json_extract(site.value, '$.site') = 'tmdb'
                LIMIT 1
                """,
                as: String.self
            )
            .fetchOne(db)
        }
    }

    static func downloadBangumiData() async throws -> [BgmDataItem] {
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            return configuration
        }())

        var lastError: Error?

        for url in bangumiDataURLs {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw BootstrapError.invalidResponse
                }

                return try JSONDecoder().decode(BgmDataResponse.self, from: data).items
            } catch {
                lastError = error
            }
        }

        throw BootstrapError.downloadFailed(lastError)
    }

    static func replaceBangumiData(_ items: [BgmDataItem], in database: DatabaseQueue) async throws {
        let encoder = JSONEncoder()
        let updatedAt = String(Int(Date().timeIntervalSince1970))
        let validItems = items.compactMap { item -> (BgmDataItem, String)? in
            guard let bangumiID = item.bangumiID else { return nil }
            return (item, bangumiID)
        }

        try await database.write { db in
            for (item, bangumiID) in validItems {
                let titleTranslateData = try encoder.encode(item.titleTranslate)
                let sitesData = try encoder.encode(item.sites)

                guard let titleTranslateJSONString = String(data: titleTranslateData, encoding: .utf8),
                      let sitesJSONString = String(data: sitesData, encoding: .utf8) else {
                    throw BootstrapError.encodingFailed
                }

                try db.execute(
                    sql: """
                    INSERT INTO "bangumi_data" (
                      "bangumi_id",
                      "title",
                      "title_translate",
                      "type",
                      "lang",
                      "begin",
                      "broadcast",
                      "end",
                      "sites"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT("bangumi_id") DO UPDATE SET
                      "title" = excluded."title",
                      "title_translate" = excluded."title_translate",
                      "type" = excluded."type",
                      "lang" = excluded."lang",
                      "begin" = excluded."begin",
                      "broadcast" = excluded."broadcast",
                      "end" = excluded."end",
                      "sites" = excluded."sites"
                    """,
                    arguments: [
                        bangumiID,
                        item.title,
                        titleTranslateJSONString,
                        item.type,
                        item.lang,
                        item.begin,
                        item.broadcast ?? "",
                        item.end ?? "",
                        sitesJSONString
                    ]
                )
            }

            try db.execute(
                sql: """
                INSERT INTO "system_settings" ("key", "value", "value_type", "created_at", "updated_at")
                VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                ON CONFLICT("key") DO UPDATE SET
                  "value" = excluded."value",
                  "value_type" = excluded."value_type",
                  "updated_at" = CURRENT_TIMESTAMP
                """,
                arguments: [
                    "bangumi_data_updated_at",
                    updatedAt,
                    "timestamp"
                ]
            )
        }
    }

    private static func databaseURL() throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("AniTV", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("AniTV.sqlite")
    }

    static func logBootstrapError(_ error: Error) {
        let prefix = "[AniTVDatabase]"

        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("\(prefix) DecodingError.typeMismatch: \(type)")
                print("\(prefix) codingPath: \(formatCodingPath(context.codingPath))")
                print("\(prefix) debugDescription: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("\(prefix) DecodingError.valueNotFound: \(type)")
                print("\(prefix) codingPath: \(formatCodingPath(context.codingPath))")
                print("\(prefix) debugDescription: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                print("\(prefix) DecodingError.keyNotFound: \(key.stringValue)")
                print("\(prefix) codingPath: \(formatCodingPath(context.codingPath))")
                print("\(prefix) debugDescription: \(context.debugDescription)")
            case .dataCorrupted(let context):
                print("\(prefix) DecodingError.dataCorrupted")
                print("\(prefix) codingPath: \(formatCodingPath(context.codingPath))")
                print("\(prefix) debugDescription: \(context.debugDescription)")
            @unknown default:
                print("\(prefix) Unknown decoding error: \(decodingError)")
            }
        } else {
            print("\(prefix) Bootstrap error: \(error)")
        }
    }

    private static func formatCodingPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath
            .map { key in
                if let intValue = key.intValue {
                    return "[\(intValue)]"
                }
                return key.stringValue
            }
            .joined(separator: ".")
    }

    enum BootstrapError: LocalizedError {
        case invalidResponse
        case encodingFailed
        case downloadFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Bangumi 数据下载失败，请稍后重试。"
            case .encodingFailed:
                return "Bangumi 数据编码失败。"
            case .downloadFailed(let error):
                return "Bangumi 数据下载失败。\(error?.localizedDescription ?? "请检查网络连接后重试。")"
            }
        }
    }
}
