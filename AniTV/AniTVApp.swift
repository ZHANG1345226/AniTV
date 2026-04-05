//
//  AniTVApp.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import SwiftUI
import SwiftData
import SQLiteData

@main
struct AniTVApp: App {
    let appDatabase: DatabaseQueue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        do {
            let database = try AniTVDatabase.makeDefaultDatabase()
            self.appDatabase = database

            prepareDependencies {
                $0.defaultDatabase = database
            }
        } catch {
            fatalError("Could not create database: \(error)")
        }
    }

    var body: some Scene {

        WindowGroup {
            AppBootstrapView(database: appDatabase)
        }
        .modelContainer(sharedModelContainer)
    }
}
