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

    func getBangumiDetails(bgmId: Int) async throws -> DanDanPlayBangumi {
        let path = "/api/v2/bangumi/bgmtv/\(bgmId)"
        guard let url = URL(string: baseURL + path) else {
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
        let result = try decoder.decode(DanDanPlayBangumiDetailsResponse.self, from: data)

        if let errorMessage = result.errorMessage, result.success == false {
            throw DanDanPlayError.apiError(errorMessage)
        }

        guard let bangumi = result.bangumi else {
            throw DanDanPlayError.invalidResponse
        }

        return bangumi
    }

    func getComments(episodeId: Int) async throws -> [DanDanPlayComment] {
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
        request.allHTTPHeaderFields = generateHeaders(for: path) // path doesn't include query string according to docs

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DanDanPlayError.invalidResponse
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(DanDanPlayCommentResponse.self, from: data)

        return result.comments
    }
}
