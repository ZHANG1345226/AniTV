//
//  HeroCarouselView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import SwiftUI
import Combine
import Kingfisher
import SQLiteData

@MainActor
final class HeroCarouselStore: ObservableObject {
    static let shared = HeroCarouselStore()

    @Published var items: [AnimeSubject] = []
    @Published var selection = 0
    @Published var isLoading = true
    @Published var exceptionMessage = ""
    @Published var transitionDirection = 1
    @Published var watchingStatusBySubjectID: [Int: Int] = [:]
    @Published var currentProfile: UserProfile?
    @Published var heroDetailsBySubjectID: [Int: BangumiGraphQLHeroSubjectNode] = [:]
    private var rememberedEpStatusBySubjectID: [Int: Int] = [:]

    private var hasLoaded = false
    private let trendingService = TrendingService()
    private let bgmRepository = BangumiRepository()

    private init() {}

    var currentItem: AnimeSubject? {
        guard items.indices.contains(selection) else { return nil }
        return items[selection]
    }

    var insertionEdge: Edge {
        transitionDirection >= 0 ? .trailing : .leading
    }

    var removalEdge: Edge {
        transitionDirection >= 0 ? .leading : .trailing
    }

    func loadIfNeeded(database: any DatabaseWriter) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load(database: database)
    }

    func load(database: any DatabaseWriter) async {
        isLoading = true
        exceptionMessage = ""

        do {
            async let trendingTask = trendingService.fetchTrendingSubjectsWithBackdrop(database: database)
            async let profileTask = AniTVDatabase.currentUserProfile(in: database)

            let (response, profile) = try await (trendingTask, profileTask)
            self.currentProfile = profile

            let bangumiIDs = response.map { String($0.subject.id) }
            let subjectIDs = response.map { $0.subject.id }
            async let dateMapTask = AniTVDatabase.fetchBangumiDataDateMap(for: bangumiIDs, in: database)
            async let detailsTask = bgmRepository.fetchHeroSubjectDetails(subjectIDs: subjectIDs)

            let (dateMapResult, detailsResult) = await (
                (try? await dateMapTask) ?? [:],
                (try? await detailsTask) ?? [:]
            )
            let dateMap = dateMapResult
            self.heroDetailsBySubjectID = detailsResult

            var mappedItems: [AnimeSubject] = []
            mappedItems.reserveCapacity(response.count)

            for entry in response {
                let subject = entry.subject.subject
                let backdropURL = URL(string: entry.backdropImage)
                let dateInfo = dateMap[String(subject.id)]

                let anime = AnimeSubject(
                    id: subject.id,
                    title: subject.name,
                    info: subject.info,
                    score: subject.rating.score,
                    titleTranslate: TitleTranslate(
                        en: "",
                        zhHans: subject.nameCN,
                        zhHant: ""
                    ),
                    type: mapSubjectType(subject.type),
                    lang: "",
                    begin: dateInfo?.begin ?? "",
                    broadcast: dateInfo?.broadcast ?? "",
                    end: dateInfo?.end ?? "",
                    backdrop: backdropURL
                )
                mappedItems.append(anime)
            }

            if let profile, profile.isAuthenticated, let bgmUserID = profile.effectiveBgmUserID {
                do {
                    let collections = try await bgmRepository.fetchUserCollections(
                        userID: bgmUserID,
                        subjectType: 2,
                        collectionType: .watching,
                        limit: 50,
                        offset: 0
                    )
                    self.watchingStatusBySubjectID = Dictionary(
                        collections.data.map { ($0.subjectID, $0.epStatus) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for (subjectID, epStatus) in self.watchingStatusBySubjectID {
                        self.rememberedEpStatusBySubjectID[subjectID] = epStatus
                    }
                } catch {
                    print("[HeroCarouselStore] Failed to fetch user collections: \(error)")
                }
            } else {
                self.watchingStatusBySubjectID = [:]
            }

            withAnimation {
                items = mappedItems
                isLoading = false
            }
        } catch {
            exceptionMessage = error.localizedDescription
            isLoading = false
            hasLoaded = false
        }
    }

    func reloadWatchingStatus(database: any DatabaseWriter) async {
        do {
            currentProfile = try await AniTVDatabase.currentUserProfile(in: database)
        } catch {
            currentProfile = nil
        }
        guard let profile = currentProfile, profile.isAuthenticated, let bgmUserID = profile.effectiveBgmUserID else {
            watchingStatusBySubjectID = [:]
            return
        }
        do {
            let collections = try await bgmRepository.fetchUserCollections(
                userID: bgmUserID,
                subjectType: 2,
                collectionType: .watching,
                limit: 50,
                offset: 0
            )
            watchingStatusBySubjectID = Dictionary(
                collections.data.map { ($0.subjectID, $0.epStatus) },
                uniquingKeysWith: { first, _ in first }
            )
            for (subjectID, epStatus) in watchingStatusBySubjectID {
                rememberedEpStatusBySubjectID[subjectID] = epStatus
            }
        } catch {
            print("[HeroCarouselStore] Failed to reload user collections: \(error)")
        }
    }

    func toggleWatchingState(
        for subjectID: Int,
        onCompleted: @escaping () -> Void
    ) async {
        guard let profile = currentProfile, profile.isAuthenticated else { return }
        let isWatching = watchingStatusBySubjectID[subjectID] != nil
        let targetType: SubjectCollectionType = isWatching ? .dropped : .watching

        if isWatching, let current = watchingStatusBySubjectID[subjectID] {
            rememberedEpStatusBySubjectID[subjectID] = current
        }

        do {
            try await bgmRepository.setSubjectCollectionType(
                subjectID: subjectID,
                type: targetType.rawValue,
                userID: profile.effectiveBgmUserID
            )

            var epStatusToSet = rememberedEpStatusBySubjectID[subjectID] ?? 0
            if !isWatching && epStatusToSet == 0 {
                if let remote = try? await bgmRepository.currentUserCollection(
                    subjectID: subjectID,
                    userID: profile.effectiveBgmUserID
                ) {
                    epStatusToSet = remote.epStatus
                    rememberedEpStatusBySubjectID[subjectID] = remote.epStatus
                }
            }

            await MainActor.run {
                if isWatching {
                    watchingStatusBySubjectID.removeValue(forKey: subjectID)
                } else {
                    watchingStatusBySubjectID[subjectID] = epStatusToSet
                }
                onCompleted()
            }
        } catch {
            print("[HeroCarouselStore] Failed to toggle watching status: \(error)")
        }
    }

    private func mapSubjectType(_ type: Int) -> String {
        switch type {
        case 2: return "tv"
        case 6: return "real"
        default: return "other"
        }
    }

    func moveSelection(by step: Int) {
        guard !items.isEmpty else { return }
        let nextIndex = (selection + step + items.count) % items.count
        transitionDirection = step >= 0 ? 1 : -1
        withAnimation(.easeInOut(duration: 0.45)) {
            selection = nextIndex
        }
    }

    func displayDescription(for item: AnimeSubject) -> String {
        let epStatus = watchingStatusBySubjectID[item.id] ?? 0
        let detail = heroDetailsBySubjectID[item.id]
        let summary = detail?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 如果当前剧集未看过 (未登录、未在看或 epStatus == 0)
        guard let currentProfile, currentProfile.isAuthenticated, epStatus > 0 else {
            return !summary.isEmpty ? summary : item.info
        }

        // 如果当前剧集看过 (epStatus > 0)
        // 展示下一集的 (name_cn??name)? ((name_cn??name)+(description?": "+description:"")):summary
        if let episodes = detail?.episodes {
            let nextSort = Double(epStatus + 1)
            let nextEp = episodes.first(where: { $0.sort == nextSort })
                ?? (episodes.indices.contains(epStatus) ? episodes[epStatus] : nil)

            if let nextEp {
                let nameCN = nextEp.nameCN.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = nextEp.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let epTitle = !nameCN.isEmpty ? nameCN : name

                if !epTitle.isEmpty {
                    let desc = nextEp.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !desc.isEmpty {
                        return "\(epTitle): \(desc)"
                    } else {
                        return epTitle
                    }
                }
            }
        }

        return !summary.isEmpty ? summary : item.info
    }
}

struct HeroCarouselView: View {
    let openAnimeDetail: (Int) -> Void
    var isCarouselActive: Bool = false
    @ObservedObject private var store = HeroCarouselStore.shared
    
    // 自动滚动
    private let autoScrollDuration: TimeInterval = 10.0
    @State private var timer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    @State private var isAutoScrolling = false
    
    @Dependency(\.defaultDatabase) private var database
    
    var body: some View {
        ZStack {
            if store.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if !store.exceptionMessage.isEmpty {
                Text(store.exceptionMessage)
            } else if store.items.isEmpty {
                Text("暂无推荐内容")
            } else {
                GeometryReader { _ in
                    ZStack(alignment: .bottomLeading) {
                        if let currentItem = store.currentItem {
                            HeroCardView(item: currentItem)
                                .id(currentItem.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: store.insertionEdge).combined(with: .opacity),
                                        removal: .move(edge: store.removalEdge).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.loadIfNeeded(database: database) }
        
        // 🎯 自动滚动
        .onAppear {
            if !isCarouselActive {
                timer.upstream.connect().cancel()
            }
        }
        .onReceive(timer) { _ in
            guard isCarouselActive else { return }
            guard !store.items.isEmpty, !store.isLoading else { return }
            isAutoScrolling = true
            store.moveSelection(by: 1)
        }
        .onChange(of: isCarouselActive) { _, active in
            if active {
                resetTimer()
            } else {
                timer.upstream.connect().cancel()
            }
        }
        .onChange(of: store.selection) { _, _ in
            if !isAutoScrolling {
                resetTimer()
            } else {
                isAutoScrolling = false
            }
        }
    }
    private func resetTimer() {
        timer.upstream.connect().cancel()
        guard isCarouselActive else { return }
        timer = Timer.publish(every: autoScrollDuration, on: .main, in: .common).autoconnect()
    }
}
#Preview {
    HeroCarouselView(openAnimeDetail: { _ in })
        .zIndex(0)
}
