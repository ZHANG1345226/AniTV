//
//  CollectionView.swift
//  AniTV
//
//  Created by Codex on 2026/5/6.
//

import SwiftUI
import Kingfisher
import SQLiteData
import Combine

private enum CollectionTab: Int, CaseIterable, Identifiable, Hashable {
    static let allCases: [CollectionTab] = [
        .collected,
        .watching,
        .wish,
        .onHold,
        .dropped
    ]

    case watching = 3
    case collected = 2
    case wish = 1
    case onHold = 4
    case dropped = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .watching:
            return "在看"
        case .collected:
            return "看过"
        case .wish:
            return "想看"
        case .onHold:
            return "搁置"
        case .dropped:
            return "抛弃"
        }
    }

    var collectionType: SubjectCollectionType {
        switch self {
        case .watching:
            return .watching
        case .collected:
            return .collected
        case .wish:
            return .wish
        case .onHold:
            return .onHold
        case .dropped:
            return .dropped
        }
    }

    var systemImage: String {
        switch self {
        case .watching:
            return "play.circle"
        case .collected:
            return "checkmark.circle"
        case .wish:
            return "bookmark.circle"
        case .onHold:
            return "pause.circle"
        case .dropped:
            return "xmark.circle"
        }
    }

    var emptyDescription: String {
        switch self {
        case .watching:
            return "还没有标记为在看的条目。"
        case .collected:
            return "还没有标记为看过的条目。"
        case .wish:
            return "还没有加入想看的条目。"
        case .onHold:
            return "还没有搁置中的条目。"
        case .dropped:
            return "还没有抛弃的条目。"
        }
    }
}

private struct CollectionPageState {
    var items: [HomePosterItem] = []
    var isLoadingInitial = false
    var isLoadingMore = false
    var hasLoaded = false
    var canLoadMore = true
    var offset = 0
}

@MainActor
private final class CollectionContentStore: ObservableObject {
    @Published var selectedTab: CollectionTab = .watching
    @Published private var pageStates: [CollectionTab: CollectionPageState] = [:]

    private let service = HomeContentService()
    private let pageSize = 24
    private var profile: UserProfile?

    func items(for tab: CollectionTab) -> [HomePosterItem] {
        state(for: tab).items
    }

    func isLoadingInitial(for tab: CollectionTab) -> Bool {
        state(for: tab).isLoadingInitial
    }

    func isLoadingMore(for tab: CollectionTab) -> Bool {
        state(for: tab).isLoadingMore
    }

    func loadIfNeeded(for tab: CollectionTab, database: any DatabaseWriter) async {
        selectedTab = tab
        await ensureProfileLoaded(database: database)

        let currentState = state(for: tab)
        guard !currentState.hasLoaded, !currentState.isLoadingInitial else { return }

        await loadPage(for: tab, reset: true, database: database)
    }

    func loadMoreIfNeeded(for tab: CollectionTab, currentItem: HomePosterItem, database: any DatabaseWriter) async {
        let currentState = state(for: tab)
        guard currentItem.id == currentState.items.last?.id else { return }
        guard currentState.hasLoaded, currentState.canLoadMore else { return }
        guard !currentState.isLoadingInitial, !currentState.isLoadingMore else { return }

        await loadPage(for: tab, reset: false, database: database)
    }

    private func ensureProfileLoaded(database: any DatabaseWriter) async {
        guard profile == nil else { return }

        do {
            profile = try await AniTVDatabase.currentUserProfile(in: database)
        } catch {
            print("[CollectionContentStore] Failed to load current profile: \(error)")
            profile = nil
        }
    }

    private func loadPage(for tab: CollectionTab, reset: Bool, database: any DatabaseWriter) async {
        guard let profile else {
            updateState(for: tab) { state in
                state = CollectionPageState()
                state.hasLoaded = true
                state.canLoadMore = false
            }
            return
        }

        guard profile.isAuthenticated,
              let bgmUserID = profile.effectiveBgmUserID else {
            updateState(for: tab) { state in
                state = CollectionPageState()
                state.hasLoaded = true
                state.canLoadMore = false
            }
            return
        }

        let offset = reset ? 0 : state(for: tab).offset

        if reset {
            updateState(for: tab) { state in
                state.isLoadingInitial = true
                state.isLoadingMore = false
            }

            do {
                let cachedItems = try await service.cachedCollections(
                    bgmUserID: bgmUserID,
                    collectionType: tab.collectionType,
                    database: database
                )
                if !cachedItems.isEmpty {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        updateState(for: tab) { state in
                            state.items = cachedItems
                        }
                    }
                }
            } catch {
                print("[CollectionContentStore] Failed to load cached \(tab.title) collections: \(error)")
            }
        } else {
            updateState(for: tab) { state in
                state.isLoadingMore = true
            }
        }

        do {
            let remoteItems = try await service.refreshCollections(
                profile: profile,
                collectionType: tab.collectionType,
                limit: pageSize,
                offset: offset,
                database: database
            )

            withAnimation(.easeInOut(duration: 0.26)) {
                updateState(for: tab) { state in
                    if reset {
                        state.items = remoteItems
                    } else {
                        appendUniqueItems(remoteItems, to: &state.items)
                    }
                    state.offset = reset ? remoteItems.count : state.items.count
                    state.canLoadMore = remoteItems.count == pageSize
                    state.hasLoaded = true
                    state.isLoadingInitial = false
                    state.isLoadingMore = false
                }
            }
        } catch {
            print("[CollectionContentStore] Failed to refresh \(tab.title) collections: \(error)")
            updateState(for: tab) { state in
                state.hasLoaded = true
                state.isLoadingInitial = false
                state.isLoadingMore = false
            }
        }
    }

    private func appendUniqueItems(_ newItems: [HomePosterItem], to items: inout [HomePosterItem]) {
        var existingIDs = Set(items.map(\.id))
        for item in newItems where existingIDs.insert(item.id).inserted {
            items.append(item)
        }
    }

    private func state(for tab: CollectionTab) -> CollectionPageState {
        pageStates[tab] ?? CollectionPageState()
    }

    private func updateState(for tab: CollectionTab, _ mutate: (inout CollectionPageState) -> Void) {
        var current = state(for: tab)
        mutate(&current)
        pageStates[tab] = current
    }
}

struct CollectionView: View {
    let openAnimeDetail: (Int) -> Void

    @Dependency(\.defaultDatabase) private var database
    @StateObject private var store = CollectionContentStore()

    var body: some View {
        TabView(selection: $store.selectedTab) {
            ForEach(CollectionTab.allCases) { tab in
                CollectionTabPageView(
                    tab: tab,
                    store: store,
                    database: database,
                    openAnimeDetail: openAnimeDetail
                )
                .tag(tab)
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct CollectionTabPageView: View {
    let tab: CollectionTab
    @ObservedObject var store: CollectionContentStore
    let database: any DatabaseWriter
    let openAnimeDetail: (Int) -> Void

    private let columns = [
        GridItem(.fixed(258), spacing: 36),
        GridItem(.fixed(258), spacing: 36),
        GridItem(.fixed(258), spacing: 36),
        GridItem(.fixed(258), spacing: 36),
        GridItem(.fixed(258), spacing: 36),
        GridItem(.fixed(258), spacing: 36)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("收藏")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 52)

                if store.isLoadingInitial(for: tab) && store.items(for: tab).isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
                        ForEach(0..<8, id: \.self) { _ in
                            CollectionPosterSkeletonCard()
                        }
                    }
                    .padding(.horizontal, 80)
                } else if store.items(for: tab).isEmpty {
                    ContentUnavailableView(
                        tab.title,
                        systemImage: tab.systemImage,
                        description: Text(tab.emptyDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
                        ForEach(store.items(for: tab)) { item in
                            CollectionPosterCard(item: item) {
                                openAnimeDetail(item.id)
                            }
                            .id(item.id)
                            .onAppear {
                                Task {
                                    await store.loadMoreIfNeeded(
                                        for: tab,
                                        currentItem: item,
                                        database: database
                                    )
                                }
                            }
                        }

                        if store.isLoadingMore(for: tab) {
                            CollectionPosterSkeletonCard()
                        }
                    }
                    .padding(.horizontal, 80)
                }
            }
            .padding(.bottom, 80)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await store.loadIfNeeded(for: tab, database: database)
        }
    }
}

private struct CollectionPosterCard: View {
    let item: HomePosterItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                KFImage(item.posterURL)
                    .resizable()
                    .placeholder {
                        CollectionPosterLoadingSurface()
                    }
                    .fade(duration: 0.2)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 258, height: 366)
                    .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let progressText = item.progressText {
                        Text(progressText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    } else if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 258, alignment: .leading)
                .background(Color.white.opacity(0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.card)
        .frame(width: 258)
    }
}

private struct CollectionPosterSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollectionPosterLoadingSurface()
                .frame(width: 258, height: 366)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .frame(width: 180, height: 18)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .frame(width: 110, height: 14)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: 258, alignment: .leading)
            .background(Color.white.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .redacted(reason: .placeholder)
    }
}

private struct CollectionPosterLoadingSurface: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white.opacity(pulse ? 0.18 : 0.08)

            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.24))
        }
        .animation(
            .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear {
            pulse = true
        }
    }
}

#Preview {
    CollectionView(openAnimeDetail: { _ in })
}
