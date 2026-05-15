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

    private static func string(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            print("[AppConfig] Missing \(key) in Info.plist")
            return ""
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            print("[AppConfig] Empty \(key) in Info.plist")
            return ""
        }

        return trimmedValue
    }
}
