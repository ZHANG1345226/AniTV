//
//  AppConfig.swift
//  AniTV
//
//  Created by Codex on 2026/5/15.
//

import Foundation

enum AppConfig {
    static let bangumiOAuthClientID = string(for: "BangumiOAuthClientID")
    static let bangumiOAuthClientSecret = string(for: "BangumiOAuthClientSecret")
    static let tmdbAPIKey = string(for: "TMDBApiKey")
    static let danDanPlayAppId = string(for: "DanDanPlayAppId")
    static let danDanPlayAppSecret = string(for: "DanDanPlayAppSecret")

    private static let secrets: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            print("[AppConfig] Failed to load Secret.plist")
            return nil
        }
        return plist
    }()

    private static func string(for key: String) -> String {
        guard let value = secrets?[key] as? String else {
            print("[AppConfig] Missing \(key) in Secrets.plist")
            return ""
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            print("[AppConfig] Empty \(key) in Secrets.plist")
            return ""
        }

        return trimmedValue
    }
}
