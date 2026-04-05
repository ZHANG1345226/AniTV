//
//  AniTVDatabase.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import SQLiteData

enum AniTVDatabase {
    static let systemSettingsSchema = """
    CREATE TABLE "system_settings" (
      "key" TEXT PRIMARY KEY NOT NULL,
      "value" TEXT NOT NULL,
      "value_type" TEXT NOT NULL DEFAULT 'string',
      "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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

        try migrator.migrate(database)
        return database
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
}
