//
//  HomeContentService.swift
//  AniTV
//
//  Created by Codex on 2026/5/4.
//

import Foundation
import SQLiteData

struct HomePosterItem: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let subtitle: String
    let posterURL: URL?
    let progressText: String?

    init(
        id: Int,
        title: String,
        subtitle: String = "",
        posterURL: URL?,
        progressText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.progressText = progressText
    }
}

struct HomeContentService: Sendable {
    private let bgmRepository = BangumiRepository()

    func cachedCollections(
        bgmUserID: Int,
        collectionType: SubjectCollectionType,
        database: any DatabaseWriter
    ) async throws -> [HomePosterItem] {
        let collections = try await AniTVDatabase.cachedUserCollections(
            bgmUserID: bgmUserID,
            collectionType: collectionType,
            in: database
        )
        return collections.compactMap(makePosterItem(from:))
    }

    func refreshCollections(
        profile: UserProfile,
        collectionType: SubjectCollectionType,
        limit: Int = 24,
        offset: Int = 0,
        database: any DatabaseWriter
    ) async throws -> [HomePosterItem] {
        guard profile.isAuthenticated,
              let bgmUserID = profile.effectiveBgmUserID else {
            return []
        }

        let response = try await bgmRepository.fetchUserCollections(
            userID: bgmUserID,
            subjectType: 2,
            collectionType: collectionType,
            limit: limit,
            offset: offset
        )
        let collections = response.data.filter { $0.type == collectionType.rawValue }

        if offset == 0 {
            try await AniTVDatabase.replaceCachedUserCollections(
                collections,
                bgmUserID: bgmUserID,
                collectionType: collectionType,
                in: database
            )
        }

        return collections.compactMap(makePosterItem(from:))
    }

    func cachedContinueWatching(
        bgmUserID: Int,
        database: any DatabaseWriter
    ) async throws -> [HomePosterItem] {
        try await cachedCollections(
            bgmUserID: bgmUserID,
            collectionType: .watching,
            database: database
        )
    }

    func refreshContinueWatching(
        profile: UserProfile,
        limit: Int = 24,
        offset: Int = 0,
        database: any DatabaseWriter
    ) async throws -> [HomePosterItem] {
        try await refreshCollections(
            profile: profile,
            collectionType: .watching,
            limit: limit,
            offset: offset,
            database: database
        )
    }

    func fetchTrendingPosterItems(
        limit: Int,
        offset: Int
    ) async throws -> [HomePosterItem] {
        let response = try await bgmRepository.fetchPrivateTrendingSubjects(
            type: 2,
            limit: limit,
            offset: offset
        )

        return response.data.map { entry in
            let subject = entry.subject
            let title = subject.nameCN.isEmpty ? subject.name : subject.nameCN
            return HomePosterItem(
                id: subject.id,
                title: title,
                subtitle: "评分 \(String(format: "%.1f", subject.rating.score))",
                posterURL: URL(string: subject.images.large.isEmpty ? subject.images.common : subject.images.large)
            )
        }
    }

    private func makePosterItem(from collection: UserSubjectCollectionDTO) -> HomePosterItem? {
        guard let subject = collection.subject else { return nil }
        let title = subject.nameCN.isEmpty ? subject.name : subject.nameCN
        let poster = subject.images.large.isEmpty ? subject.images.common : subject.images.large
        return HomePosterItem(
            id: subject.id,
            title: title,
            subtitle: subject.shortSummary,
            posterURL: URL(string: poster),
            progressText: collection.epStatus > 0 ? "看到第 \(collection.epStatus) 集" : nil
        )
    }
}
