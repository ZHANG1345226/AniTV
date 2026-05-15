//
//  HomeView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import SwiftUI
import Combine
import Kingfisher
import SQLiteData

@MainActor
final class HomeContentStore: ObservableObject {
    @Published var continueWatchingItems: [HomePosterItem] = []
    @Published var isLoadingContinueWatching = false
    @Published var isLoadingMoreContinueWatching = false
    @Published var trendingItems: [HomePosterItem] = []
    @Published var isLoadingTrending = true
    @Published var isLoadingMoreTrending = false

    private let service = HomeContentService()
    private var hasLoaded = false
    private var profile: UserProfile?
    private var continueWatchingOffset = 0
    private var canLoadMoreContinueWatching = true
    private let continueWatchingPageSize = 12
    private var trendingOffset = 0
    private var canLoadMoreTrending = true
    private let trendingPageSize = 12

    var shouldShowContinueWatching: Bool {
        isLoadingContinueWatching || !continueWatchingItems.isEmpty
    }

    func loadIfNeeded(database: any DatabaseWriter) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        print("[HomeContentStore] Start loading home content")
        await load(database: database)
    }

    func load(database: any DatabaseWriter) async {
        do {
            profile = try await AniTVDatabase.currentUserProfile(in: database)
        } catch {
            print("[HomeContentStore] Failed to load current profile: \(error)")
            profile = nil
        }

        await loadInitialTrending()
        await loadContinueWatching(database: database)
    }

    func loadMoreTrendingIfNeeded(currentItem: HomePosterItem) async {
        guard currentItem.id == trendingItems.last?.id else { return }
        guard canLoadMoreTrending, !isLoadingTrending, !isLoadingMoreTrending else { return }

        isLoadingMoreTrending = true
        defer { isLoadingMoreTrending = false }

        do {
            let newItems = try await service.fetchTrendingPosterItems(
                limit: trendingPageSize,
                offset: trendingOffset
            )
            canLoadMoreTrending = newItems.count == trendingPageSize
            trendingOffset += newItems.count

            withAnimation(.easeInOut(duration: 0.25)) {
                appendUniqueTrendingItems(newItems)
            }
        } catch {
            print("[HomeContentStore] Failed to load more trending subjects: \(error)")
        }
    }

    func loadMoreContinueWatchingIfNeeded(currentItem: HomePosterItem, database: any DatabaseWriter) async {
        guard currentItem.id == continueWatchingItems.last?.id else { return }
        guard canLoadMoreContinueWatching, !isLoadingContinueWatching, !isLoadingMoreContinueWatching else { return }
        guard let profile, profile.isAuthenticated else { return }

        isLoadingMoreContinueWatching = true
        defer { isLoadingMoreContinueWatching = false }

        do {
            let newItems = try await service.refreshContinueWatching(
                profile: profile,
                limit: continueWatchingPageSize,
                offset: continueWatchingOffset,
                database: database
            )
            canLoadMoreContinueWatching = newItems.count == continueWatchingPageSize
            continueWatchingOffset += newItems.count

            withAnimation(.easeInOut(duration: 0.25)) {
                appendUniqueContinueWatchingItems(newItems)
            }
        } catch {
            print("[HomeContentStore] Failed to load more continue watching subjects: \(error)")
        }
    }

    func refreshContinueWatching(database: any DatabaseWriter) async {
        do {
            profile = try await AniTVDatabase.currentUserProfile(in: database)
        } catch {
            print("[HomeContentStore] Failed to reload current profile: \(error)")
            profile = nil
        }

        guard let profile,
              profile.isAuthenticated,
              let bgmUserID = profile.effectiveBgmUserID else {
            continueWatchingItems = []
            isLoadingContinueWatching = false
            isLoadingMoreContinueWatching = false
            continueWatchingOffset = 0
            canLoadMoreContinueWatching = false
            return
        }

        isLoadingContinueWatching = true
        isLoadingMoreContinueWatching = false
        continueWatchingOffset = 0
        canLoadMoreContinueWatching = true
        print("[HomeContentStore] Refreshing continue watching for bgm user \(bgmUserID)")

        do {
            let remoteItems = try await service.refreshContinueWatching(
                profile: profile,
                limit: continueWatchingPageSize,
                offset: continueWatchingOffset,
                database: database
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                continueWatchingItems = remoteItems
                continueWatchingOffset = remoteItems.count
                canLoadMoreContinueWatching = remoteItems.count == continueWatchingPageSize
                isLoadingContinueWatching = false
            }
        } catch {
            print("[HomeContentStore] Failed to refresh continue watching: \(error)")
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoadingContinueWatching = false
                canLoadMoreContinueWatching = false
            }
        }
    }

    private func loadContinueWatching(database: any DatabaseWriter) async {
        guard let profile,
              profile.isAuthenticated,
              let bgmUserID = profile.effectiveBgmUserID else {
            print("[credentials] \(profile?.refreshToken), \(profile?.expiresAt)")
            print("[HomeContentStore] Skip continue watching for guest profile")
            continueWatchingItems = []
            isLoadingContinueWatching = false
            isLoadingMoreContinueWatching = false
            continueWatchingOffset = 0
            canLoadMoreContinueWatching = false
            return
        }

        isLoadingContinueWatching = true
        continueWatchingOffset = 0
        canLoadMoreContinueWatching = true
        print("[HomeContentStore] Loading continue watching for bgm user \(bgmUserID)")

        do {
            let cachedItems = try await service.cachedContinueWatching(
                bgmUserID: bgmUserID,
                database: database
            )
            if !cachedItems.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    continueWatchingItems = cachedItems
                }
            }
        } catch {
            print("[HomeContentStore] Failed to load cached collections: \(error)")
        }

        do {
            let remoteItems = try await service.refreshContinueWatching(
                profile: profile,
                limit: continueWatchingPageSize,
                offset: continueWatchingOffset,
                database: database
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                continueWatchingItems = remoteItems
                continueWatchingOffset = remoteItems.count
                canLoadMoreContinueWatching = remoteItems.count == continueWatchingPageSize
                isLoadingContinueWatching = false
            }
        } catch {
            print("[HomeContentStore] Failed to refresh collections: \(error)")
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoadingContinueWatching = false
                canLoadMoreContinueWatching = false
            }
        }
    }

    private func loadInitialTrending() async {
        isLoadingTrending = true
        trendingOffset = 0
        canLoadMoreTrending = true
        print("[HomeContentStore] Loading trending subjects")

        do {
            let items = try await service.fetchTrendingPosterItems(
                limit: trendingPageSize,
                offset: trendingOffset
            )
            print("[HomeContentStore] Loaded \(items.count) trending subjects")
            canLoadMoreTrending = items.count == trendingPageSize
            trendingOffset = items.count

            withAnimation(.easeInOut(duration: 0.25)) {
                trendingItems = items
                isLoadingTrending = false
            }
        } catch {
            print("[HomeContentStore] Failed to load trending subjects: \(error)")
            isLoadingTrending = false
            canLoadMoreTrending = false
        }
    }

    private func appendUniqueTrendingItems(_ newItems: [HomePosterItem]) {
        var existingIDs = Set(trendingItems.map(\.id))
        for item in newItems where existingIDs.insert(item.id).inserted {
            trendingItems.append(item)
        }
    }

    private func appendUniqueContinueWatchingItems(_ newItems: [HomePosterItem]) {
        var existingIDs = Set(continueWatchingItems.map(\.id))
        for item in newItems where existingIDs.insert(item.id).inserted {
            continueWatchingItems.append(item)
        }
    }
}

struct HomeView: View {
    let openAnimeDetail: (Int) -> Void
    let focusRestoreToken: Int
    let continueWatchingRefreshToken: Int
    @Binding private var lastFocusedPosterID: Int?
    @Binding private var pendingRestorePosterID: Int?

    private enum ScrollTarget {
        case heroTop
    }

    init(
        openAnimeDetail: @escaping (Int) -> Void,
        focusRestoreToken: Int = 0,
        continueWatchingRefreshToken: Int = 0,
        lastFocusedPosterID: Binding<Int?> = .constant(nil),
        pendingRestorePosterID: Binding<Int?> = .constant(nil)
    ) {
        self.openAnimeDetail = openAnimeDetail
        self.focusRestoreToken = focusRestoreToken
        self.continueWatchingRefreshToken = continueWatchingRefreshToken
        _lastFocusedPosterID = lastFocusedPosterID
        _pendingRestorePosterID = pendingRestorePosterID
    }

    @Environment(\.resetFocus) private var resetFocus
    @Dependency(\.defaultDatabase) private var database
    @StateObject private var store = HomeContentStore()
    @ObservedObject private var heroStore = HeroCarouselStore.shared
    @State private var loadTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @State private var didResetInitialScroll = false
    @State private var shouldPreferHeroDefaultFocus = false
    @State private var heroDefaultFocusTask: Task<Void, Never>?
    @State private var preferredHeroFocusTarget: HeroActionButtonFocus = .play
    @FocusState private var focusedPosterID: Int?
    @Namespace private var heroFocusScope
    @Namespace private var posterFocusScope

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                let heroOffset = heroVerticalOffset(
                    scrollOffset: scrollOffset,
                    heroHeight: proxy.size.height
                )

                HeroCarouselView(openAnimeDetail: openAnimeDetail)
                    .ignoresSafeArea()
                    .offset(y: heroOffset)

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.12),
                        .black.opacity(0.32),
                        .black.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .offset(y: heroOffset)

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .bottomLeading) {
                                Color.clear

                                if let item = heroStore.currentItem {
                                    HomeHeroOverlayView(
                                        item: item,
                                        itemCount: heroStore.items.count,
                                        selection: heroStore.selection,
                                        openAnimeDetail: openAnimeDetail,
                                        onMoveToPrevious: {
                                            heroStore.moveSelection(by: -1)
                                        },
                                        onMoveToNext: {
                                            heroStore.moveSelection(by: 1)
                                        },
                                        defaultFocusScope: heroFocusScope,
                                        preferredFocusTarget: preferredHeroFocusTarget,
                                        onActionFocused: rememberHeroActionFocused,
                                        prefersDefaultFocus: shouldPreferHeroDefaultFocus
                                    )
                                    .frame(maxWidth: proxy.size.width * 0.58, alignment: .leading)
                                    .padding(.leading, 80)
//                                    .padding(.bottom, 260)
                                    .focusScope(heroFocusScope)
                                    .focusSection()
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                                }


                            }
                            .frame(height: max(540, proxy.size.height * 0.70))
                            .frame(maxWidth: .infinity)
                            .id(ScrollTarget.heroTop)
                            if heroStore.items.count > 1 {
                                CustomIndexBar(
                                    numberOfPages: heroStore.items.count,
                                    currentPage: heroStore.selection,
                                    duration: 10
                                )
                                .frame(maxWidth: .infinity, alignment: .center)
//                                    .padding(.bottom, -10)
                                .allowsHitTesting(false)
                            }

                            if store.shouldShowContinueWatching {
                                HomePosterShelfView(
                                    title: "继续观看",
                                    items: store.continueWatchingItems,
                                    isLoading: store.isLoadingContinueWatching,
                                    availableWidth: proxy.size.width,
                                    openAnimeDetail: openAnimeDetail,
                                    focusedPosterID: $focusedPosterID,
                                    focusScope: posterFocusScope,
                                    pendingRestorePosterID: pendingRestorePosterID,
                                    onPosterFocused: rememberFocusedPoster,
                                    onItemAppear: { item in
                                        Task {
                                            await store.loadMoreContinueWatchingIfNeeded(
                                                currentItem: item,
                                                database: database
                                            )
                                        }
                                    },
                                    showsLoadingTail: store.isLoadingMoreContinueWatching
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            HomePosterShelfView(
                                title: "热门条目",
                                items: store.trendingItems,
                                isLoading: store.isLoadingTrending,
                                availableWidth: proxy.size.width,
                                openAnimeDetail: openAnimeDetail,
                                focusedPosterID: $focusedPosterID,
                                focusScope: posterFocusScope,
                                pendingRestorePosterID: pendingRestorePosterID,
                                onPosterFocused: rememberFocusedPoster,
                                onItemAppear: { item in
                                    Task {
                                        await store.loadMoreTrendingIfNeeded(currentItem: item)
                                    }
                                },
                                showsLoadingTail: store.isLoadingMoreTrending
                            )
                            .padding(.top, store.shouldShowContinueWatching ? 10 : 0)
                        }
                        .frame(width: proxy.size.width, alignment: .leading)
                        .padding(.bottom, 80)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusScope(posterFocusScope)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        // Use the raw vertical content offset so the hero starts fully visible
                        // even when SwiftUI restores scroll insets during app relaunch.
                        max(0, geometry.contentOffset.y)
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .background(alignment: .bottom) {
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.18),
                                .black.opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.48)
                        .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
                    .onAppear {
                        resetInitialScrollPosition(using: scrollProxy)
                    }
                    .onChange(of: heroStore.isLoading) { _, isLoading in
                        guard !isLoading else { return }
                        resetInitialScrollPosition(using: scrollProxy, force: true)
                    }
                    .onChange(of: store.isLoadingTrending) { _, isLoading in
                        guard !isLoading else { return }
                        resetInitialScrollPosition(using: scrollProxy, force: true)
                    }
                    .onChange(of: pendingRestorePosterID) { _, newValue in
                        guard let newValue else { return }
                        Task { @MainActor in
                            await restorePendingPosterFocus(newValue, using: scrollProxy)
                        }
                    }
                    .onChange(of: focusRestoreToken) { _, _ in
                        Task { @MainActor in
                            await restoreHomeFocus(using: scrollProxy)
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .onAppear {
            guard loadTask == nil else { return }
            loadTask = Task {
                await store.loadIfNeeded(database: database)
                await MainActor.run {
                    loadTask = nil
                }
            }
        }
        .onChange(of: continueWatchingRefreshToken) { _, _ in
            Task {
                await store.refreshContinueWatching(database: database)
            }
        }
    }

    private func heroVerticalOffset(scrollOffset: CGFloat, heroHeight: CGFloat) -> CGFloat {
        let firstStageDistance = heroHeight * 0.24
        let secondStageDistance = heroHeight * 0.16
        let firstStageTarget = heroHeight * 0.9

        if scrollOffset <= firstStageDistance {
            let progress = firstStageDistance == 0 ? 0 : scrollOffset / firstStageDistance
            return -firstStageTarget * progress
        }

        let remaining = min(scrollOffset - firstStageDistance, secondStageDistance)
        let secondProgress = secondStageDistance == 0 ? 0 : remaining / secondStageDistance
        let secondStageTarget = heroHeight - firstStageTarget
        return -(firstStageTarget + secondStageTarget * secondProgress)
    }

    private func resetInitialScrollPosition(using proxy: ScrollViewProxy, force: Bool = false) {
        guard pendingRestorePosterID == nil else { return }
        guard force || !didResetInitialScroll else { return }
        didResetInitialScroll = true
        scrollOffset = 0

        Task { @MainActor in
            await Task.yield()
            jumpToHeroTop(using: proxy)

            try? await Task.sleep(nanoseconds: 120_000_000)
            jumpToHeroTop(using: proxy)
        }
    }

    private func jumpToHeroTop(using proxy: ScrollViewProxy) {
        guard pendingRestorePosterID == nil else { return }
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(ScrollTarget.heroTop, anchor: .top)
            scrollOffset = 0
        }
        resetHeroFocus()
    }

    private func resetHeroFocus() {
        guard pendingRestorePosterID == nil else { return }
        heroDefaultFocusTask?.cancel()
        heroDefaultFocusTask = Task { @MainActor in
            focusedPosterID = nil
            shouldPreferHeroDefaultFocus = true
            await Task.yield()
            guard !Task.isCancelled else { return }
            resetFocus(in: heroFocusScope)
            await Task.yield()
            guard !Task.isCancelled else { return }
            shouldPreferHeroDefaultFocus = false
            heroDefaultFocusTask = nil
        }
    }

    private func rememberHeroActionFocused(_ target: HeroActionButtonFocus) {
        guard pendingRestorePosterID == nil else { return }
        preferredHeroFocusTarget = target
        lastFocusedPosterID = nil
    }

    private func rememberFocusedPoster(_ posterID: Int) {
        if pendingRestorePosterID == posterID {
            lastFocusedPosterID = posterID
            pendingRestorePosterID = nil
            return
        }

        guard pendingRestorePosterID == nil else { return }
        lastFocusedPosterID = posterID
    }

    private func restoreHomeFocus(using proxy: ScrollViewProxy) async {
        await Task.yield()
        if let posterID = pendingRestorePosterID {
            await restorePendingPosterFocus(posterID, using: proxy)
        } else {
            jumpToHeroTop(using: proxy)
        }
    }

    private func restorePendingPosterFocus(_ posterID: Int, using proxy: ScrollViewProxy) async {
        heroDefaultFocusTask?.cancel()
        shouldPreferHeroDefaultFocus = false
        focusedPosterID = nil
        await Task.yield()
        guard pendingRestorePosterID == posterID else { return }

        scrollToPoster(posterID, using: proxy)
        try? await Task.sleep(for: .milliseconds(300))
        guard pendingRestorePosterID == posterID else { return }

        focusedPosterID = posterID
        await Task.yield()
        guard pendingRestorePosterID == posterID else { return }

        resetFocus(in: posterFocusScope)
        lastFocusedPosterID = posterID
    }

    private func scrollToPoster(_ posterID: Int, using proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(posterID, anchor: .center)
        }
    }
}

private struct HomeDebugStatusView: View {
    @ObservedObject var store: HomeContentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home Debug")
                .font(.headline.weight(.bold))
            Text("continue: \(store.continueWatchingItems.count)  loading: \(store.isLoadingContinueWatching)")
                .font(.caption.monospaced())
            Text("trending: \(store.trendingItems.count)  loading: \(store.isLoadingTrending)  more: \(store.isLoadingMoreTrending)")
                .font(.caption.monospaced())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 80)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct HomeHeroOverlayView: View {
    let item: AnimeSubject
    let itemCount: Int
    let selection: Int
    let openAnimeDetail: (Int) -> Void
    let onMoveToPrevious: () -> Void
    let onMoveToNext: () -> Void
    let defaultFocusScope: Namespace.ID
    let preferredFocusTarget: HeroActionButtonFocus
    let onActionFocused: (HeroActionButtonFocus) -> Void
    let prefersDefaultFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NewArrivalPill(text: "Sunday")

            VStack(alignment: .leading, spacing: 14) {
                Text(item.titleTranslate.zhHans.isEmpty ? item.title : item.titleTranslate.zhHans)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                HStack(spacing: 14) {
                    Text(String(format: "%.1f", item.score))
                    Text(item.type.uppercased())

                    if !item.begin.isEmpty {
                        Text(item.begin)
                    }
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

                Text(item.info)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(3)
                    .frame(maxWidth: 760, alignment: .leading)
            }

            ActionButtonsView(
                anime: item,
                openAnimeDetail: openAnimeDetail,
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext,
                defaultFocusScope: defaultFocusScope,
                preferredFocusTarget: preferredFocusTarget,
                onActionFocused: onActionFocused,
                prefersDefaultFocus: prefersDefaultFocus
            )
            .padding(.leading, -16)
        }
    }
}

private struct HomePosterShelfView: View {
    let title: String
    let items: [HomePosterItem]
    let isLoading: Bool
    let availableWidth: CGFloat
    let openAnimeDetail: (Int) -> Void
    let focusedPosterID: FocusState<Int?>.Binding
    let focusScope: Namespace.ID
    let pendingRestorePosterID: Int?
    let onPosterFocused: (Int) -> Void
    var onItemAppear: ((HomePosterItem) -> Void)?
    var showsLoadingTail = false

    var body: some View {
        if title == "热门条目" {
            HomePosterGridSection(
                title: title,
                items: items,
                isLoading: isLoading,
                availableWidth: availableWidth,
                openAnimeDetail: openAnimeDetail,
                focusedPosterID: focusedPosterID,
                focusScope: focusScope,
                pendingRestorePosterID: pendingRestorePosterID,
                onPosterFocused: onPosterFocused,
                onItemAppear: onItemAppear,
                showsLoadingTail: showsLoadingTail
            )
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 40) {
                        if isLoading && items.isEmpty {
                            ForEach(0..<7, id: \.self) { _ in
                                HomePosterSkeletonCard()
                            }
                        } else {
                            ForEach(items) { item in
                                HomePosterCard(
                                    item: item,
                                    focusedPosterID: focusedPosterID,
                                    focusScope: focusScope,
                                    shouldPreferFocus: pendingRestorePosterID == item.id,
                                    onFocused: onPosterFocused
                                ) {
                                    openAnimeDetail(item.id)
                                }
                                .id(item.id)
                                .onAppear {
                                    onItemAppear?(item)
                                }
                            }
                        }

                        if showsLoadingTail {
                            HomePosterSkeletonCard()
                        }
                    }
                    .padding(.leading, 80)
                    .padding(.trailing, 80)
                    .padding(.bottom, 54)
                    .padding(.top, 54)
                }
                .frame(height: 460)
            }
            .padding(.top, 20)
            .focusSection()
        }
    }
}

private struct HomePosterGridSection: View {
    let title: String
    let items: [HomePosterItem]
    let isLoading: Bool
    let availableWidth: CGFloat
    let openAnimeDetail: (Int) -> Void
    let focusedPosterID: FocusState<Int?>.Binding
    let focusScope: Namespace.ID
    let pendingRestorePosterID: Int?
    let onPosterFocused: (Int) -> Void
    var onItemAppear: ((HomePosterItem) -> Void)?
    var showsLoadingTail = false

    private let columnCount = 6
    private let posterWidth: CGFloat = 258
    private let horizontalPadding: CGFloat = 80
    private let minimumColumnSpacing: CGFloat = 36
    private let rowSpacing: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 10)

            LazyVStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(alignment: .top, spacing: columnSpacing(for: availableWidth)) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            gridCell(at: row * columnCount + column)
                        }
                    }
                    .frame(width: contentWidth(for: availableWidth), alignment: .leading)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(width: availableWidth, alignment: .leading)
        .padding(.top, 50)
        .focusSection()
    }

    private var cellCount: Int {
        if isLoading && items.isEmpty {
            return 8
        }

        return items.count + (showsLoadingTail ? 1 : 0)
    }

    private var rowCount: Int {
        guard cellCount > 0 else { return 0 }
        return Int(ceil(Double(cellCount) / Double(columnCount)))
    }

    @ViewBuilder
    private func gridCell(at index: Int) -> some View {
        if isLoading && items.isEmpty {
            if index < cellCount {
                HomePosterSkeletonCard()
            }
        } else if items.indices.contains(index) {
            let item = items[index]
            HomePosterCard(
                item: item,
                focusedPosterID: focusedPosterID,
                focusScope: focusScope,
                shouldPreferFocus: pendingRestorePosterID == item.id,
                onFocused: onPosterFocused
            ) {
                openAnimeDetail(item.id)
            }
            .id(item.id)
            .onAppear {
                onItemAppear?(item)
            }
        } else if showsLoadingTail && index == items.count {
            HomePosterSkeletonCard()
        }
    }

    private func contentWidth(for width: CGFloat) -> CGFloat {
        max(0, width - horizontalPadding * 2)
    }

    private func columnSpacing(for width: CGFloat) -> CGFloat {
        let contentWidth = contentWidth(for: width)
        let posterTotalWidth = CGFloat(columnCount) * posterWidth
        let spacingSlotCount = max(columnCount - 1, 1)

        guard contentWidth > posterTotalWidth else {
            return minimumColumnSpacing
        }

        return max(
            minimumColumnSpacing,
            (contentWidth - posterTotalWidth) / CGFloat(spacingSlotCount)
        )
    }
}

private struct HomePosterCard: View {
    let item: HomePosterItem
    let focusedPosterID: FocusState<Int?>.Binding
    let focusScope: Namespace.ID
    let shouldPreferFocus: Bool
    let onFocused: (Int) -> Void
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: {
            onFocused(item.id)
            action()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                KFImage(item.posterURL)
                    .resizable()
                    .placeholder {
                        HomePosterLoadingSurface()
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
        .focused(focusedPosterID, equals: item.id)
        .prefersDefaultFocus(shouldPreferFocus, in: focusScope)
        .frame(width: 258)
        .onChange(of: isFocused) { _, newValue in
            guard newValue else { return }
            onFocused(item.id)
        }
    }
}

private struct HomePosterSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomePosterLoadingSurface()
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

private struct HomePosterLoadingSurface: View {
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
    HomeView(openAnimeDetail: { _ in })
}
