//
//  AppRouter.swift
//  AniTV
//
//  Created by Codex on 2026/5/16.
//

import Foundation
import Combine
import SwiftUI

enum AppRoute: Hashable {
    case animeDetail(Int)
    case episodePlayer(EpisodePlayerRoute)
}

struct EpisodePlayerRoute: Hashable {
    let episodes: [BgmEpisodeInfo]
    let initialEpisodeID: Int
    let sessionTitle: String
    let initialPlaybackPositionSeconds: Int?
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedCategory: NavigationCategory = .home
    @Published var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @Published var path: [AppRoute] = []
    @Published var playerDismissRefreshToken = 0

    func showAnimeDetail(_ bgmId: Int) {
        path.append(.animeDetail(bgmId))
    }

    func showEpisodePlayer(
        episodes: [BgmEpisodeInfo],
        episodeID: Int,
        sessionTitle: String,
        initialPlaybackPositionSeconds: Int?
    ) {
        let route = EpisodePlayerRoute(
            episodes: episodes,
            initialEpisodeID: episodeID,
            sessionTitle: sessionTitle,
            initialPlaybackPositionSeconds: initialPlaybackPositionSeconds
        )
        path.append(.episodePlayer(route))
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func notifyPlayerDismissed() {
        playerDismissRefreshToken += 1
    }
}
