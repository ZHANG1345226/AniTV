//
//  BangumiRepository.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// 定义一个专门的 Repository 来管理 Bangumi 的数据获取
struct BangumiRepository {
    
    private let client = NetworkClient.shared
    
    /// 获取热门条目
    func fetchTrendingSubjects(
        type: Int = 2, // 2 = 动画
        limit: Int = 12,
        offset: Int = 0
    ) async throws -> BgmPagedResponse<TrendingSubjectDTO> {
        try await fetchBrowserTrendingSubjects(type: type, limit: limit, offset: offset)
    }

    /// 获取 next.bgm.tv 的热门条目，保留作为备用实现
    func fetchPrivateTrendingSubjects(
        type: Int = 2,
        limit: Int = 12,
        offset: Int = 0
    ) async throws -> BgmPagedResponse<TrendingSubjectDTO> {
        let queryItems = [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        return try await client.request(
            url: BangumiAPI.priv.build("p1/trending/subjects"),
            queryItems: queryItems
        )
    }
    
    func getEpisodes(
        type: Int = 0,
        limit: Int = 100,
        offset: Int = 0,
        id: Int
    ) async throws -> BgmPagedResponse<BgmEpisodeInfo> {
        let queryItems = [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "subject_id", value: String(id))
        ]
        
        return try await client.request(
            url: BangumiAPI.pub.build("v0/episodes"),
            queryItems: queryItems
        )
    }

    /// 获取条目
    /// GET /p1/subjects/{subjectID}
    func getSubject(subjectID: Int) async throws -> SubjectDetailDTO {
        try await client.request(
            url: BangumiAPI.priv.build("p1/subjects/\(subjectID)"),
            queryItems: []
        )
    }

    func fetchLargeImages(subjectIDs: [Int]) async throws -> [Int: String] {
        guard !subjectIDs.isEmpty else { return [:] }

        var request = URLRequest(url: BangumiAPI.pub.build("v0/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            BangumiGraphQLRequest(query: makeSubjectImagesQuery(subjectIDs: subjectIDs))
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.badServerResponse(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(
            BangumiGraphQLResponse<[String: BangumiGraphQLSubjectNode?]>.self,
            from: data
        )

        if let errors = decoded.errors, !errors.isEmpty, decoded.data == nil {
            throw ChiiError(message: errors.map(\.message).joined(separator: "\n"))
        }

        var imagesBySubjectID: [Int: String] = [:]
        if let data = decoded.data {
            for node in data.values {
                guard let node, !node.images.large.isEmpty else { continue }
                imagesBySubjectID[node.id] = node.images.large
            }
        }

        return imagesBySubjectID
    }

    private func fetchBrowserTrendingSubjects(
        type: Int,
        limit: Int,
        offset: Int
    ) async throws -> BgmPagedResponse<TrendingSubjectDTO> {
        let pageSize = 24
        let page = max(offset / pageSize + 1, 1)
        let localOffset = max(offset % pageSize, 0)
        let mediaPath = try browserMediaPath(for: type)

        var components = URLComponents(url: BangumiAPI.web.build("\(mediaPath)/browser/"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "trends"),
            URLQueryItem(name: "page", value: String(page))
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.badServerResponse(statusCode: httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ChiiError(message: "Failed to decode Bangumi browser HTML as UTF-8")
        }

        let parsed = try BangumiBrowserTrendingParser.parse(html: html, subjectType: type)
        let sliced = Array(parsed.data.dropFirst(localOffset).prefix(limit))
        return BgmPagedResponse(data: sliced, total: parsed.total)
    }

    private func browserMediaPath(for type: Int) throws -> String {
        switch type {
        case 1:
            return "book"
        case 2:
            return "anime"
        case 3:
            return "music"
        case 4:
            return "game"
        case 6:
            return "real"
        default:
            throw ChiiError(message: "Unsupported Bangumi browser subject type: \(type)")
        }
    }

    private func makeSubjectImagesQuery(subjectIDs: [Int]) -> String {
        let subjectSelections = subjectIDs.map { subjectID in
            "subject_\(subjectID): subject(id: \(subjectID)) { ...SubjectFragment }"
        }
        .joined(separator: "\n")

        return """
        fragment SubjectFragment on Subject {
          id
          images { large }
        }

        query TrendingSubjectImages {
        \(subjectSelections)
        }
        """
    }
}
