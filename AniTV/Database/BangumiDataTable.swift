//
//  AniTVDatabase+BangumiData.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import GRDB
import SQLiteData

extension AniTVDatabase {
    nonisolated private static let bangumiDataURLs = [
        URL(string: "https://cdn.jsdelivr.net/npm/bangumi-data@0.3/dist/data.json")!,
        URL(string: "https://unpkg.com/bangumi-data@0.3/dist/data.json")!
    ]
    nonisolated private static let bangumiDataVersionSettingKey = "bangumi_data_version"
    nonisolated private static let bangumiDataUpdatedAtSettingKey = "bangumi_data_updated_at"

    struct BangumiDataRelease: Sendable {
        let version: String
        let url: URL
    }

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

    static func registerBangumiDataMigrations(in migrator: inout DatabaseMigrator) {
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
    }

    static func isBangumiDataEmpty(in database: any DatabaseWriter) async throws -> Bool {
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

    struct BangumiDateInfo: Sendable {
        let begin: String
        let broadcast: String
        let end: String
    }

    static func fetchBangumiDataDateMap(
        for bangumiIDs: [String],
        in database: any DatabaseWriter
    ) async throws -> [String: BangumiDateInfo] {
        guard !bangumiIDs.isEmpty else { return [:] }
        return try await database.read { db in
            let placeholders = bangumiIDs.map { _ in "?" }.joined(separator: ",")
            let arguments = StatementArguments(bangumiIDs)
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT "bangumi_id", "begin", "broadcast", "end"
                FROM "bangumi_data"
                WHERE "bangumi_id" IN (\(placeholders))
                """,
                arguments: arguments
            )
            var map: [String: BangumiDateInfo] = [:]
            for row in rows {
                let id: String = row["bangumi_id"]
                let begin: String = row["begin"] ?? ""
                let broadcast: String = row["broadcast"] ?? ""
                let end: String = row["end"] ?? ""
                map[id] = BangumiDateInfo(begin: begin, broadcast: broadcast, end: end)
            }
            return map
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

    static func storedBangumiDataUpdatedAt(in database: any DatabaseWriter) async throws -> Date? {
        guard let value = try await systemSettingValue(forKey: bangumiDataUpdatedAtSettingKey, in: database),
              let timestamp = TimeInterval(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func shouldRefreshBangumiData(
        in database: any DatabaseWriter,
        maxAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date()
    ) async throws -> Bool {
        if try await isBangumiDataEmpty(in: database) {
            print("[AniTVDatabase] bangumi_data table is empty, refresh required")
            return true
        }

        guard let updatedAt = try await storedBangumiDataUpdatedAt(in: database) else {
            print("[AniTVDatabase] Missing bangumi-data refresh timestamp, refresh required")
            return true
        }

        let age = now.timeIntervalSince(updatedAt)
        let shouldRefresh = age >= maxAge
//        print("[AniTVDatabase] bangumi-data last refreshed at \(updatedAt), age: \(age)s, should refresh: \(shouldRefresh)")
        return shouldRefresh
    }

    static func shouldUpdateBangumiData(
        to release: BangumiDataRelease,
        in database: any DatabaseWriter
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

    static func markBangumiDataRefreshed(
        at date: Date = Date(),
        in database: any DatabaseWriter
    ) async throws {
        let updatedAt = String(Int(date.timeIntervalSince1970))
        try await database.write { db in
            try upsertSystemSetting(
                key: bangumiDataUpdatedAtSettingKey,
                value: updatedAt,
                valueType: "timestamp",
                in: db
            )
        }
    }

    static func refreshBangumiDataIfNeeded(in database: DatabaseQueue) async throws -> Bool {
        let release = try await resolveBangumiDataRelease()
        print("[AniTVDatabase] Latest bangumi-data version: \(release.version)")

        if try await shouldUpdateBangumiData(to: release, in: database) {
            print("[AniTVDatabase] Starting bangumi-data download from \(release.url.absoluteString)")
            let items = try await downloadBangumiData(from: release.url)
            try await replaceBangumiData(items, version: release.version, in: database)
            return true
        }

        try await markBangumiDataRefreshed(in: database)
        print("[AniTVDatabase] bangumi-data is already up to date, refreshed timestamp")
        return false
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
                return "Received an invalid response while downloading bangumi-data."
            case .versionNotFound:
                return "Could not determine the bangumi-data release version."
            case .encodingFailed:
                return "Failed to encode bangumi-data for storage."
            case .downloadFailed(let error):
                return "Failed to download bangumi-data: \(error?.localizedDescription ?? "unknown error")"
            }
        }
    }
}
