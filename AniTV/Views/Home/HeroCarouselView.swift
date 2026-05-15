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

    private var hasLoaded = false
    private let trendingService = TrendingService()

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

    func loadIfNeeded(database: DatabaseWriter) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load(database: database)
    }

    func load(database: DatabaseWriter) async {
        isLoading = true
        exceptionMessage = ""

        do {
            let response = try await trendingService.fetchTrendingSubjectsWithBackdrop(database: database)
            var mappedItems: [AnimeSubject] = []
            mappedItems.reserveCapacity(response.count)

            for entry in response {
                let subject = entry.subject.subject
                let backdropURL = URL(string: entry.backdropImage)

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
                    begin: "",
                    broadcast: "",
                    end: "",
                    backdrop: backdropURL
                )
                mappedItems.append(anime)
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
}

struct HeroCarouselView: View {
    let openAnimeDetail: (Int) -> Void
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
        .onReceive(timer) { _ in
            guard !store.items.isEmpty, !store.isLoading else { return }
            isAutoScrolling = true
            store.moveSelection(by: 1)
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
        timer = Timer.publish(every: autoScrollDuration, on: .main, in: .common).autoconnect()
    }
}
#Preview {
    HeroCarouselView(openAnimeDetail: { _ in })
        .zIndex(0)
}
