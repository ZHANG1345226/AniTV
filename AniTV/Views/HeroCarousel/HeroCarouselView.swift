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

struct HeroCarouselView: View {
    let openAnimeDetail: (Int) -> Void
    @State private var items: [AnimeSubject] = []
    @State private var selection = 0
    @State private var isLoading = true
    @State private var exceptionMessage = ""
    @State private var transitionDirection = 1
    
    // 自动滚动
    private let autoScrollDuration: TimeInterval = 10.0
    @State private var timer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    @State private var isAutoScrolling = false
    
    @Dependency(\.defaultDatabase) private var database
    private let bgmRepository = BangumiRepository()
    private let tmdbRepository: TMDBRepository = TMDBRepository()
    
    private var currentItem: AnimeSubject? {
        guard items.indices.contains(selection) else { return nil }
        return items[selection]
    }
    
    private func moveSelection(by step: Int, isManual: Bool = true) {
        guard !items.isEmpty else { return }
        let nextIndex = (selection + step + items.count) % items.count
        transitionDirection = step >= 0 ? 1 : -1
        if isManual {
            isAutoScrolling = false
        }
        withAnimation(.easeInOut(duration: 0.45)) {
            selection = nextIndex
        }
    }
    
    private var insertionEdge: Edge {
        transitionDirection >= 0 ? .trailing : .leading
    }
    
    private var removalEdge: Edge {
        transitionDirection >= 0 ? .leading : .trailing
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else if !exceptionMessage.isEmpty {
                Text(exceptionMessage)
            } else if items.isEmpty {
                Text("暂无推荐内容")
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        if let currentItem {
                            HeroCardView(item: currentItem)
                                .id(currentItem.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: insertionEdge).combined(with: .opacity),
                                        removal: .move(edge: removalEdge).combined(with: .opacity)
                                    )
                                )
                        }

                        if let currentItem {
                            carouselOverlay(for: currentItem, width: proxy.size.width)
                        }

                        VStack {
                            Spacer()
                            CustomIndexBar(
                                numberOfPages: items.count,
                                currentPage: selection,
                                duration: autoScrollDuration
                            )
                            .padding(.bottom, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task { await load() }
        
        // 🎯 自动滚动
        .onReceive(timer) { _ in
            guard !items.isEmpty, !isLoading else { return }
            isAutoScrolling = true
            moveSelection(by: 1, isManual: false)
        }
        .onChange(of: selection) { _, _ in
            if !isAutoScrolling {
                resetTimer()
            } else {
                isAutoScrolling = false
            }
        }
    }
    
    @ViewBuilder
    private func carouselOverlay(for item: AnimeSubject, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if item.endDate == nil, let airDate = item.startDate {
                NewArrivalPill(text: airDate.formatted(.dateTime.weekday(.wide)))
            }
            
            Text(item.displayName)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(radius: 4)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Text(item.isMovie ? "劇場版" : "新番組")
                Text("·")
                Text("评分 \(item.scoreString)")
                    .foregroundStyle(.yellow)
                if item.displayOriginalTitle {
                    Text("·")
                    Text(item.title)
                }
            }
            .font(.headline)
            .foregroundStyle(.white.opacity(0.8))
            
            Text(item.info)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            
            ActionButtonsView(
                anime: item,
                openAnimeDetail: openAnimeDetail,
                onMoveToPrevious: { moveSelection(by: -1) },
                onMoveToNext: { moveSelection(by: 1) }
            )
        }
        .padding(40)
        .background(
            EllipticalGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.0)
                ]),
                center: .center,
                startRadiusFraction: 0.0,
                endRadiusFraction: 1.0
            )
            .blur(radius: 50)
        )
        .padding(.horizontal, 50)
        .padding(.bottom, 200)
        .frame(maxWidth: width * 0.6, alignment: .leading)
    }
    
    private func resetTimer() {
        timer.upstream.connect().cancel()
        timer = Timer.publish(every: autoScrollDuration, on: .main, in: .common).autoconnect()
    }

    func load() async {
        do {
            let response = try await bgmRepository.fetchTrendingSubjects()
            var mappedItems: [AnimeSubject] = []
            mappedItems.reserveCapacity(response.data.count)

            for entry in response.data {
                let subject = entry.subject

                var backdropURL = URL(string: subject.images.large)
                if let tmdbID = try await AniTVDatabase.tmdbIDForBangumiID(String(subject.id), in: database) {
                    let tmdbBackdrop = await tmdbRepository.getBackdrop(tmdbID: tmdbID)
                    if !tmdbBackdrop.isEmpty, let url = URL(string: tmdbBackdrop) {
                        backdropURL = url
                    }
                }

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

            await MainActor.run {
                withAnimation {
                    self.items = mappedItems
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.exceptionMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func mapSubjectType(_ type: Int) -> String {
        switch type {
        case 2: return "tv"
        case 6: return "real"
        default: return "other"
        }
    }
}
#Preview {
    HeroCarouselView(openAnimeDetail: { _ in })
        .zIndex(0)
}
