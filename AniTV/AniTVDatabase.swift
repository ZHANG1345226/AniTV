//
//  AniTVDatabase.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import GRDB
import SQLiteData

enum AniTVDatabase {
    private static let bangumiDataURLs = [
        URL(string: "https://cdn.jsdelivr.net/npm/bangumi-data@0.3/dist/data.json")!,
        URL(string: "https://unpkg.com/bangumi-data@0.3/dist/data.json")!
    ]
    private static let bangumiDataVersionSettingKey = "bangumi_data_version"
    private static let bangumiDataUpdatedAtSettingKey = "bangumi_data_updated_at"

    struct BangumiDataRelease: Sendable {
        let version: String
        let url: URL
    }

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

    static func fetchAllBangumiDataRows(
        in database: any DatabaseWriter
    ) async throws -> [TimelineBangumiDataRow] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT
                  "bangumi_id",
                  "title",
                  "title_translate",
                  "type",
                  "lang",
                  "begin",
                  "broadcast",
                  "end",
                  "sites"
                FROM "bangumi_data"
                """
            )
            .map { row in
                TimelineBangumiDataRow(
                    bangumiID: row["bangumi_id"],
                    title: row["title"],
                    titleTranslate: row["title_translate"],
                    type: row["type"],
                    lang: row["lang"],
                    begin: row["begin"],
                    broadcast: row["broadcast"],
                    end: row["end"],
                    sites: row["sites"]
                )
            }
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
                arguments: [
                    cacheKey,
                    payload,
                    now
                ]
            )
        }
    }

    static func downloadBangumiData() async throws -> [BgmDataItem] {
        let release = try await resolveBangumiDataRelease()
        return try await downloadBangumiData(from: release.url)
    }

    static func resolveBangumiDataRelease() async throws -> BangumiDataRelease {
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            return configuration
        }())

        var lastError: Error?

        for url in bangumiDataURLs {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"

                let (_, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      200..<400 ~= httpResponse.statusCode else {
                    throw BootstrapError.invalidResponse
                }

                if let release = bangumiDataRelease(from: httpResponse, fallbackURL: url) {
                    print("[AniTVDatabase] Resolved bangumi-data version \(release.version) from \(url.absoluteString)")
                    print("[AniTVDatabase] Versioned bangumi-data URL: \(release.url.absoluteString)")
                    return release
                }

                throw BootstrapError.versionNotFound
            } catch {
                lastError = error
            }
        }

        throw BootstrapError.downloadFailed(lastError)
    }

    static func downloadBangumiData(from url: URL) async throws -> [BgmDataItem] {
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            return configuration
        }())

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw BootstrapError.invalidResponse
        }

        return try JSONDecoder().decode(BgmDataResponse.self, from: data).items
    }

    static func storedBangumiDataVersion(in database: any DatabaseWriter) async throws -> String? {
        try await systemSettingValue(forKey: bangumiDataVersionSettingKey, in: database)
    }

    static func shouldUpdateBangumiData(
        to release: BangumiDataRelease,
        in database: DatabaseQueue
    ) async throws -> Bool {
        if try await isBangumiDataEmpty(in: database) {
            print("[AniTVDatabase] bangumi_data table is empty, update required for version \(release.version)")
            return true
        }

        let localVersion = try await storedBangumiDataVersion(in: database)
        let shouldUpdate = localVersion != release.version
        print("[AniTVDatabase] Local bangumi-data version: \(localVersion ?? "<none>"), remote version: \(release.version), should update: \(shouldUpdate)")
        return shouldUpdate
    }

    static func replaceBangumiData(
        _ items: [BgmDataItem],
        version: String,
        in database: DatabaseQueue
    ) async throws {
        let encoder = JSONEncoder()
        let updatedAt = String(Int(Date().timeIntervalSince1970))
        let allValidItems = items.compactMap { item -> (BgmDataItem, String)? in
            guard let bangumiID = item.bangumiID else { return nil }
            return (item, bangumiID)
        }
        var deduplicatedItemsByID: [String: BgmDataItem] = [:]
        for (item, bangumiID) in allValidItems {
            deduplicatedItemsByID[bangumiID] = item
        }
        let validItems = deduplicatedItemsByID
            .map { ($0.value, $0.key) }
            .sorted { $0.1 < $1.1 }
        let duplicateCount = allValidItems.count - validItems.count

        print("[AniTVDatabase] Importing \(validItems.count) bangumi-data rows for version \(version)")
        if duplicateCount > 0 {
            print("[AniTVDatabase] Deduplicated \(duplicateCount) duplicate bangumi-data rows before import")
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

            try upsertSystemSetting(
                key: bangumiDataUpdatedAtSettingKey,
                value: updatedAt,
                valueType: "timestamp",
                in: db
            )
            try upsertSystemSetting(
                key: bangumiDataVersionSettingKey,
                value: version,
                valueType: "string",
                in: db
            )
        }

        print("[AniTVDatabase] Finished importing bangumi-data version \(version)")
    }

    private static func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let libraryURL = try fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let preferredDirectory = libraryURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("AniTV", isDirectory: true)

        do {
            try fileManager.createDirectory(at: preferredDirectory, withIntermediateDirectories: true)
            return preferredDirectory.appendingPathComponent("AniTV.sqlite")
        } catch {
            // Device fallback: some environments may reject creating Application Support.
            let cachesURL = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fallbackDirectory = cachesURL.appendingPathComponent("AniTV", isDirectory: true)
            try fileManager.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
            return fallbackDirectory.appendingPathComponent("AniTV.sqlite")
        }
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

    private static func bangumiDataRelease(
        from response: HTTPURLResponse,
        fallbackURL: URL
    ) -> BangumiDataRelease? {
        if let locationValue = response.value(forHTTPHeaderField: "Location"),
           let version = extractBangumiDataVersion(from: locationValue),
           let locationURL = URL(string: locationValue, relativeTo: fallbackURL)?.absoluteURL,
           let versionedURL = makeVersionedBangumiDataURL(from: locationURL, version: version) {
            return BangumiDataRelease(version: version, url: versionedURL)
        }

        if let version = response.value(forHTTPHeaderField: "x-jsd-version"),
           let versionedURL = makeVersionedBangumiDataURL(from: fallbackURL, version: version) {
            return BangumiDataRelease(version: version, url: versionedURL)
        }

        if let responseURL = response.url,
           let version = extractBangumiDataVersion(from: responseURL.absoluteString),
           let versionedURL = makeVersionedBangumiDataURL(from: responseURL, version: version) {
            return BangumiDataRelease(version: version, url: versionedURL)
        }

        return nil
    }

    private static func extractBangumiDataVersion(from string: String) -> String? {
        let pattern = #"bangumi-data@([^/]+)/dist/data\.json"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ),
              match.numberOfRanges > 1,
              let versionRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[versionRange])
    }

    private static func makeVersionedBangumiDataURL(from url: URL, version: String) -> URL? {
        let absoluteString = url.absoluteString
        guard let range = absoluteString.range(
            of: #"bangumi-data@[^/]+/dist/data\.json"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let replaced = absoluteString.replacingCharacters(
            in: range,
            with: "bangumi-data@\(version)/dist/data.json"
        )
        return URL(string: replaced)
    }

    private static func systemSettingValue(
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

    private static func upsertSystemSetting(
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
            arguments: [
                key,
                value,
                valueType
            ]
        )
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
        case versionNotFound
        case encodingFailed
        case downloadFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Bangumi 数据下载失败，请稍后重试。"
            case .versionNotFound:
                return "未能解析 Bangumi 数据版本信息。"
            case .encodingFailed:
                return "Bangumi 数据编码失败。"
            case .downloadFailed(let error):
                return "Bangumi 数据下载失败。\(error?.localizedDescription ?? "请检查网络连接后重试。")"
            }
        }
    }
}
