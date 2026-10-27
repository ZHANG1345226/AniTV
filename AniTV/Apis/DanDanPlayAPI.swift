//
//  DanDanPlayAPI.swift
//  AniTV
//
//  Created by Codex on 2026/7/26.
//

import Foundation
import CryptoKit

enum DanDanPlayError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
}

class DanDanPlayAPI {
    static let shared = DanDanPlayAPI()
    private let baseURL = "https://api.dandanplay.net"

    private init() {}

    private func generateHeaders(for path: String) -> [String: String] {
        let appId = AppConfig.danDanPlayAppId
        let appSecret = AppConfig.danDanPlayAppSecret
        let timestamp = String(Int(Date().timeIntervalSince1970))

        let dataString = appId + timestamp + path + appSecret
        let data = dataString.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let hashData = Data(hash)
        let signature = hashData.base64EncodedString()

        return [
            "X-AppId": appId,
            "X-Timestamp": timestamp,
            "X-Signature": signature,
            "Accept": "application/json"
        ]
    }

    func getBangumiDetails(bgmId: Int, targetSort: Double?) async throws -> DanDanPlayBangumi {
        try await getBangumiDetails(bgmId: bgmId, targetSorts: targetSort.map { [$0] } ?? [])
    }

    func getBangumiDetails(bgmId: Int, targetSorts: [Double] = []) async throws -> DanDanPlayBangumi {
        let cache = DanDanPlayCacheManager.shared
        let sortStrings = targetSorts.map { String(Int($0)) }
        
        // 1. Check local cache first
        if let cachedBangumi = cache.getCachedBangumi(bgmId: bgmId) {
            if !sortStrings.isEmpty {
                let hasEpisode = cachedBangumi.episodes.contains { ep in
                    sortStrings.contains { s in
                        ep.episodeNumber == s ||
                        ep.episodeTitle == s ||
                        ep.episodeTitle.contains("第\(s)话") ||
                        ep.episodeTitle.contains("第\(s)集")
                    }
                }
                if hasEpisode {
                    print("[DanDanPlayCache] Hit bangumi cache for bgmId \(bgmId) with episode \(sortStrings)")
                    return cachedBangumi
                } else {
                    print("[DanDanPlayCache] Hit bangumi cache for bgmId \(bgmId), but episodes \(sortStrings) missing")
                }
            } else {
                print("[DanDanPlayCache] Hit bangumi cache for bgmId \(bgmId)")
                return cachedBangumi
            }
        }
        
        // 2. Cache missing or episode missing: check 2-hour throttling
        if cache.isBangumiFetchThrottled(bgmId: bgmId) {
            print("[DanDanPlayCache] Fetch throttled for bgmId \(bgmId) (last requested within 2 hours)")
            if let cachedBangumi = cache.getCachedBangumi(bgmId: bgmId) {
                return cachedBangumi
            }
            throw DanDanPlayError.apiError("Fetch throttled (requested within 2 hours)")
        }
        
        // 3. Request remote API
        let path = "/api/v2/bangumi/bgmtv/\(bgmId)"
        guard let url = URL(string: baseURL + path) else {
            throw DanDanPlayError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = generateHeaders(for: path)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                cache.recordBangumiFetchTime(bgmId: bgmId)
                throw DanDanPlayError.invalidResponse
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(DanDanPlayBangumiDetailsResponse.self, from: data)

            if let errorMessage = result.errorMessage, result.success == false {
                cache.recordBangumiFetchTime(bgmId: bgmId)
                throw DanDanPlayError.apiError(errorMessage)
            }

            guard let bangumi = result.bangumi else {
                cache.recordBangumiFetchTime(bgmId: bgmId)
                throw DanDanPlayError.invalidResponse
            }

            cache.saveBangumi(bangumi, bgmId: bgmId)
            return bangumi
        } catch {
            cache.recordBangumiFetchTime(bgmId: bgmId)
            throw error
        }
    }

    func getComments(episodeId: Int, airDateString: String? = nil) async throws -> [DanDanPlayComment] {
        let cache = DanDanPlayCacheManager.shared
        
        if let cachedComments = cache.getCachedComments(episodeId: episodeId, airDateString: airDateString) {
            return cachedComments
        }
        
        let path = "/api/v2/comment/\(episodeId)"
        guard var urlComponents = URLComponents(string: baseURL + path) else {
            throw DanDanPlayError.invalidURL
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "withRelated", value: "true"),
            URLQueryItem(name: "chConvert", value: "1")
        ]

        guard let url = urlComponents.url else {
            throw DanDanPlayError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = generateHeaders(for: path)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DanDanPlayError.invalidResponse
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(DanDanPlayCommentResponse.self, from: data)

        cache.saveComments(result.comments, episodeId: episodeId, airDateString: airDateString)
        return result.comments
    }
}
