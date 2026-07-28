//
//  BangumiRepository.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation
import SQLiteData

// 定义一个专门的 Repository 来管理 Bangumi 的数据获取
struct BangumiRepository {
    private struct CurrentBangumiCredentials {
        let userID: Int
        let accessToken: String
    }

    private struct BatchEpisodeCollectionUpdateRequest: Encodable {
        let episodeID: [Int]
        let type: Int

        enum CodingKeys: String, CodingKey {
            case episodeID = "episode_id"
            case type
        }
    }

    private struct UserSubjectCollectionModifyPayload: Encodable {
        let type: Int?
    }

    private struct UserEpisodeCollectionModifyPayload: Encodable {
        let type: Int
    }

    private enum EpisodeCollectionType {
        static let none = 0
        static let watched = 2
    }

    private let client = NetworkClient.shared
    @Dependency(\.defaultDatabase) private var database
    
    /// 获取热门条目
    func fetchTrendingSubjects(
        type: Int = 2, // 2 = 动画
        limit: Int = 12,
        offset: Int = 0
    ) async throws -> BgmPagedResponse<TrendingSubjectDTO> {
        try await fetchPrivateTrendingSubjects(type: type, limit: limit, offset: offset)
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

    func fetchUserCollections(
        userID: Int? = nil,
        subjectType: Int = 2,
        collectionType: SubjectCollectionType = .watching,
        limit: Int = 24,
        offset: Int = 0
    ) async throws -> UserCollectionsResponseDTO {
        let credentials = try await currentBangumiCredentials()
        let resolvedUserID = try userIDPathComponent(userID ?? credentials.userID)

        var components = URLComponents(
            url: BangumiAPI.pub
                .build("v0/users")
                .appendingPathComponent(resolvedUserID)
                .appendingPathComponent("collections"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "subject_type", value: String(subjectType)),
            URLQueryItem(name: "type", value: String(collectionType.rawValue)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        return try await client.request(
            UserCollectionsResponseDTO.self,
            method: "GET",
            url: url,
            headers: authHeaders(accessToken: credentials.accessToken)
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

    func fetchUserEpisodeCollections(
        subjectID: Int,
        userID: Int? = nil
    ) async throws -> [BgmUserEpisodeCollectionDTO] {
        let credentials = try await currentBangumiCredentials()

        let url = BangumiAPI.pub
            .build("v0/users")
            .appendingPathComponent("-")
            .appendingPathComponent("collections")
            .appendingPathComponent(String(subjectID))
            .appendingPathComponent("episodes")

        let pageSize = 1000
        var offset = 0
        var collections: [BgmUserEpisodeCollectionDTO] = []
        var total = Int.max

        repeat {
            let response = try await client.request(
                BgmPagedResponse<BgmUserEpisodeCollectionDTO>.self,
                method: "GET",
                url: url,
                queryItems: [
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset))
                ],
                headers: authHeaders(accessToken: credentials.accessToken)
            )
            collections.append(contentsOf: response.data)
            total = response.total
            offset += response.data.count

            guard !response.data.isEmpty else { break }
        } while collections.count < total

        return collections
    }

    private func fetchAllEpisodes(subjectID: Int) async throws -> [BgmEpisodeInfo] {
        let pageSize = 1000
        var offset = 0
        var episodes: [BgmEpisodeInfo] = []
        var total = Int.max

        repeat {
            let response = try await getEpisodes(limit: pageSize, offset: offset, id: subjectID)
            episodes.append(contentsOf: response.data)
            total = response.total
            offset += response.data.count

            guard !response.data.isEmpty else { break }
        } while episodes.count < total

        return episodes
    }

    private func markSubjectCollectedIfAllEpisodesWatched(
        subjectID: Int,
        userID: Int? = nil
    ) async throws {
        let episodes = try await fetchAllEpisodes(subjectID: subjectID)
        let episodeIDs = Set(episodes.map(\.id))
        guard !episodeIDs.isEmpty else { return }

        let remoteCollections = try await fetchUserEpisodeCollections(subjectID: subjectID, userID: userID)
        let watchedEpisodeIDs = Set(
            remoteCollections
                .filter { $0.type == EpisodeCollectionType.watched }
                .map { $0.episode.id }
        )

        guard episodeIDs.isSubset(of: watchedEpisodeIDs) else { return }

        try await setSubjectCollectionType(
            subjectID: subjectID,
            type: SubjectCollectionType.collected.rawValue,
            userID: userID
        )
    }

    func currentUserCollection(
        subjectID: Int,
        userID: Int? = nil
    ) async throws -> UserSubjectCollectionDTO? {
        let credentials = try await currentBangumiCredentials()
        let resolvedUserID = try userIDPathComponent(userID ?? credentials.userID)
        let url = BangumiAPI.pub
            .build("v0/users")
            .appendingPathComponent(resolvedUserID)
            .appendingPathComponent("collections")
            .appendingPathComponent(String(subjectID))

        let response = try await client.requestResponse(
            method: "GET",
            url: url,
            headers: authHeaders(accessToken: credentials.accessToken),
            acceptableStatusCodes: Set(NetworkClient.successStatusCodes).union([404])
        )
        guard response.response.statusCode != 404 else { return nil }

        return try JSONDecoder().decode(UserSubjectCollectionDTO.self, from: response.data)
    }

    func ensureSubjectCollectionWatchingIfNeeded(
        subjectID: Int,
        userID: Int? = nil
    ) async throws {
        let credentials = try await currentBangumiCredentials()
        let resolvedUserID = try userIDPathComponent(userID ?? credentials.userID)
        let currentCollection = try await currentUserCollection(
            subjectID: subjectID,
            userID: userID
        )
        guard currentCollection == nil else { return }

        let url = BangumiAPI.pub
            .build("v0/users")
            .appendingPathComponent(resolvedUserID)
            .appendingPathComponent("collections")
            .appendingPathComponent(String(subjectID))

        try await client.requestVoid(
            method: "POST",
            url: url,
            headers: jsonAuthHeaders(accessToken: credentials.accessToken),
            body: try JSONEncoder().encode(
                UserSubjectCollectionModifyPayload(type: SubjectCollectionType.watching.rawValue)
            )
        )
    }

    func setSubjectCollectionType(
        subjectID: Int,
        type: Int,
        userID: Int? = nil
    ) async throws {
        let credentials = try await currentBangumiCredentials()
        let url = BangumiAPI.pub
            .build("v0/users")
            .appendingPathComponent("-")
            .appendingPathComponent("collections")
            .appendingPathComponent(String(subjectID))

        let currentCollection = try await currentUserCollection(
            subjectID: subjectID,
            userID: userID
        )
        let body = try JSONEncoder().encode(UserSubjectCollectionModifyPayload(type: type))
        if currentCollection == nil {
            try await client.requestVoid(
                method: "POST",
                url: url,
                headers: jsonAuthHeaders(accessToken: credentials.accessToken),
                body: body
            )
        } else {
            try await client.requestVoid(
                method: "PATCH",
                url: url,
                headers: jsonAuthHeaders(accessToken: credentials.accessToken),
                body: body
            )
        }
    }

    func markEpisodesWatched(
        subjectID: Int,
        episodeIDs: [Int],
        userID: Int? = nil
    ) async throws {
        let uniqueEpisodeIDs = Array(Set(episodeIDs)).sorted()
        guard !uniqueEpisodeIDs.isEmpty else { return }

        let remoteCollections = try await fetchUserEpisodeCollections(subjectID: subjectID, userID: userID)
        let watchedEpisodeIDs = Set(
            remoteCollections
                .filter { $0.type == EpisodeCollectionType.watched }
                .map { $0.episode.id }
        )
        let episodeIDsToMarkWatched = uniqueEpisodeIDs.filter { !watchedEpisodeIDs.contains($0) }

        if !episodeIDsToMarkWatched.isEmpty {
            let credentials = try await currentBangumiCredentials()
            let url = BangumiAPI.pub
                .build("v0/users")
                .appendingPathComponent("-")
                .appendingPathComponent("collections")
                .appendingPathComponent(String(subjectID))
                .appendingPathComponent("episodes")

            try await client.requestVoid(
                method: "PATCH",
                url: url,
                headers: jsonAuthHeaders(accessToken: credentials.accessToken),
                body: try JSONEncoder().encode(
                    BatchEpisodeCollectionUpdateRequest(
                        episodeID: episodeIDsToMarkWatched,
                        type: EpisodeCollectionType.watched
                    )
                )
            )
        }

        try await markSubjectCollectedIfAllEpisodesWatched(subjectID: subjectID, userID: userID)
    }

    func setEpisodeCollectionType(
        episodeID: Int,
        type: Int,
        userID: Int? = nil
    ) async throws {
        let credentials = try await currentBangumiCredentials()
        let url = BangumiAPI.pub
            .build("v0/users")
            .appendingPathComponent("-")
            .appendingPathComponent("collections")
            .appendingPathComponent("-")
            .appendingPathComponent("episodes")
            .appendingPathComponent(String(episodeID))

        try await client.requestVoid(
            method: "PUT",
            url: url,
            headers: jsonAuthHeaders(accessToken: credentials.accessToken),
            body: try JSONEncoder().encode(
                UserEpisodeCollectionModifyPayload(type: type)
            )
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

        let url = BangumiAPI.pub.build("v0/graphql")
        let decoded = try await client.request(
            BangumiGraphQLResponse<[String: BangumiGraphQLSubjectNode?]>.self,
            method: "POST",
            url: url,
            headers: jsonHeaders(),
            body: try JSONEncoder().encode(
                BangumiGraphQLRequest(query: makeSubjectImagesQuery(subjectIDs: subjectIDs))
            )
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

    func fetchTimelineSubjectDetails(subjectIDs: [Int]) async throws -> [Int: BangumiGraphQLTimelineSubjectNode] {
        let uniqueSubjectIDs = Array(Set(subjectIDs)).sorted()
        guard !uniqueSubjectIDs.isEmpty else { return [:] }

        var subjectsByID: [Int: BangumiGraphQLTimelineSubjectNode] = [:]
        for batch in uniqueSubjectIDs.chunked(into: 40) {
            let query = makeTimelineSubjectDetailsQuery(subjectIDs: batch)
            let variables = Dictionary(
                uniqueKeysWithValues: batch.enumerated().map { index, subjectID in
                    ("id\(index)", subjectID)
                }
            )

            let url = BangumiAPI.pub.build("v0/graphql")
            let decoded = try await client.request(
                BangumiGraphQLResponse<[String: BangumiGraphQLTimelineSubjectNode?]>.self,
                method: "POST",
                url: url,
                headers: jsonHeaders(),
                body: try JSONEncoder().encode(
                    BangumiGraphQLRequest(query: query, variables: variables)
                )
            )

            if let errors = decoded.errors, !errors.isEmpty, decoded.data == nil {
                throw ChiiError(message: errors.map { $0.message }.joined(separator: "\n"))
            }

            if let data = decoded.data {
                for node in data.values {
                    guard let node else { continue }
                    subjectsByID[node.id] = node
                }
            }
        }

        return subjectsByID
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

        let data = try await client.get(
            url: url,
            headers: ["Accept": "text/html,application/xhtml+xml"]
        )

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

    private func makeTimelineSubjectDetailsQuery(subjectIDs: [Int]) -> String {
        let variableDefinitions = subjectIDs.enumerated().map { index, _ in
            "$id\(index): Int!"
        }
        .joined(separator: ", ")

        let subjectSelections = subjectIDs.enumerated().map { index, _ in
            "s\(index): subject(id: $id\(index)) { ...SubjectFragment }"
        }
        .joined(separator: "\n")

        return """
        fragment Ep on Episode {
          id
          airdate
          name
          name_cn
          sort
        }

        fragment SubjectFragment on Subject {
          id
          images {
            common
            grid
            large
            medium
            small
          }
          name
          name_cn
          episodes: episodes(limit: 100) { ...Ep }
        }

        query TimelineSubjectDetails(\(variableDefinitions)) {
        \(subjectSelections)
        }
        """
    }

    private func authHeaders(accessToken: String) -> [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    private func jsonHeaders() -> [String: String] {
        ["Content-Type": "application/json"]
    }

    private func jsonAuthHeaders(accessToken: String) -> [String: String] {
        authHeaders(accessToken: accessToken).merging(jsonHeaders()) { _, new in new }
    }

    private func currentBangumiCredentials() async throws -> CurrentBangumiCredentials {
        guard let profile = try await AniTVDatabase.currentUserProfile(in: database),
              profile.isAuthenticated,
              let userID = profile.effectiveBgmUserID,
              let accessToken = profile.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            throw ChiiError.requireLogin
        }

        return CurrentBangumiCredentials(userID: userID, accessToken: accessToken)
    }

    private func userIDPathComponent(_ userID: Int) throws -> String {
        guard userID > 0 else { throw NetworkError.invalidURL }
        return String(userID)
    }

}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }

        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }

        return result
    }
}
