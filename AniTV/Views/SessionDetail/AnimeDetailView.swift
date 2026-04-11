//
//  AnimeDetailView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/13.
//


import SwiftUI
import Kingfisher
import SQLiteData

struct AnimeDetailView: View {
    let bgmId: Int
    let openEpisodePlayer: ([BgmEpisodeInfo], BgmEpisodeInfo, String) -> Void
    @Dependency(\.defaultDatabase) private var database
    @State private var showingFullInfo = false
    @State private var subject: SubjectDetailDTO?
    @State private var backdropURL: URL?
    @State private var episodes: [BgmEpisodeInfo] = []

    init(
        bgmId: Int,
        openEpisodePlayer: @escaping ([BgmEpisodeInfo], BgmEpisodeInfo, String) -> Void = { _, _, _ in }
    ) {
        self.bgmId = bgmId
        self.openEpisodePlayer = openEpisodePlayer
    }
    
    var body: some View {
        ZStack {
            //Layer 1: 沉浸式背景图
            GeometryReader { proxy in
                KFImage(backdropURL)
                    .resizable()
                    .placeholder {
                        Color.gray.opacity(0.3)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay(
                        // 渐变遮罩：从下往上变黑，保证文字清晰
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0.95),
                                .black.opacity(0.6),
                                .clear
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    
                
            }
            .edgesIgnoringSafeArea(.all) // 铺满全屏
            
            // Layer 2: 内容区域
            VStack(alignment: .leading, spacing: 40) {
                Spacer() // 把内容推到底部
                
                // A. 顶部元信息区 (标题 + 简介)
                HStack(alignment: .bottom, spacing: 60) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. 标题
                        Text(displayName)
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .shadow(radius: 10)
                        
                        // 2. 标签行 (年份 | 评分 | 类型)


                        HStack(spacing: 20) {
                            if let starts = startDate {
                                var dateString: String {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy年M月"
                                    return formatter.string(from: starts)
                                }
                                BadgeView(text: dateString)
                            }
                            BadgeView(text: typeText.uppercased())
                            Text(originalTitle)
                        }
                        
                        ScoreView(
                            score: score,
                            count: count,
                            rank: rank
                        )
                        // 给评分和下方的标签加点间距
                        .padding(.bottom, 10)
                        
                        // 3. 简介 (限制行数)
                        Button(action: { self.showingFullInfo = true }) {
                            Text(infoText)
                                .font(.body)
                                .foregroundColor(.gray)
                                .lineLimit(3)
                                .frame(maxWidth: 900, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        
                        // 4. 操作按钮组
                        HStack(spacing: 20) {
                            Button(action: {
                                guard let firstEpisode = episodes.first else { return }
                                openEpisodePlayer(episodes, firstEpisode, displayName)
     
                            }) {
                                Label("开始播放", systemImage: "play.fill")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                            }
                            // 2. 修正这里：参数是 (true, in: namespace)
                            .prefersDefaultFocus(true, in: focusNamespace)
                            .focused($focusedField, equals: "playButton")
                            
                            Button(action: { print("Fav Tapped") }) {
                                Label("追番", systemImage: "heart")
                            }
                        }
                    }.focusScope(focusNamespace)
                }
                .padding(.horizontal, 80) // tvOS 两侧留白通常较大
                
                // B. 底部剧集列表 (Shelf)
                VStack(alignment: .leading, spacing: 20) {
                    Text("剧集列表")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal, 80)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 40) {
                            // 第一个元素加 Padding，让它缩进去
                            Spacer().frame(width: 40)
                            
                            ForEach(episodes.enumerated(), id: \.element.id) { index, episode in
                                EpisodeCardView(
                                    episodeInfo: episode,
                                    sessionTitle: displayName,
                                    stillURL: backdropURL,
                                    onOpenPlayer: {
                                        openEpisodePlayer(episodes, episode, displayName)
                                    }
                                )
                            }
                            
                            Spacer().frame(width: 80)
                        }
                        .padding(.bottom, 60) // 底部留白，防止贴边
                    }
                }
            }
        }
        .onAppear {
            focusedField = "playButton"
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $showingFullInfo) {
            VStack(spacing: 30) {
                Text("简介")
                    .font(.title.bold())
                
                ScrollView {
                    Text(infoText)
                        .font(.body)
                }
                
                Button("关闭") {
                    self.showingFullInfo = false
                }
            }
            .padding(60)
        }
    }
    
    // 用于管理焦点的命名空间
    @FocusState private var focusedField: String?
    @Namespace var focusNamespace

    private var displayName: String {
        if let nameCN = subject?.nameCN, !nameCN.isEmpty { return nameCN }
        return subject?.name ?? "加载中..."
    }

    private var originalTitle: String {
        subject?.name ?? ""
    }

    private var infoText: String {
        if let summary = subject?.summary, !summary.isEmpty { return summary }
        if let info = subject?.info, !info.isEmpty { return info }
        return "暂无简介"
    }

    private var typeText: String {
        guard let type = subject?.type else { return "UNKNOWN" }
        switch type {
        case 2: return "TV"
        case 6: return "LIVE"
        default: return "TYPE\(type)"
        }
    }

    private var score: Double {
        subject?.rating.score ?? 0
    }

    private var count: Int {
        subject?.rating.total ?? 0
    }

    private var rank: Int {
        subject?.rating.rank ?? 0
    }

    private var startDate: Date? {
        guard let dateString = subject?.airtime.date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func loadData() async {
        let bgmRepo = BangumiRepository()
        do {
            let detail = try await bgmRepo.getSubject(subjectID: bgmId)
            await MainActor.run {
                subject = detail
                // Fallback: use Bangumi large image first.
                if let large = detail.images?.large {
                    backdropURL = URL(string: large)
                }
            }

            if let tmdbID = try await AniTVDatabase.tmdbIDForBangumiID(String(bgmId), in: database) {
                let tmdbRepo = TMDBRepository()
                let backdrop = await tmdbRepo.getBackdrop(tmdbID: tmdbID)
                await MainActor.run {
                    // Prefer TMDB backdrop; keep BGM image when TMDB fails.
                    if !backdrop.isEmpty {
                        backdropURL = URL(string: backdrop)
                    }
                }
            }
        } catch {
            print("Failed to load subject detail: \(error)")
        }

        do {
            let response = try await bgmRepo.getEpisodes(id: bgmId)
            await MainActor.run {
                episodes = response.data
            }
        } catch {
            print("Failed to load episodes: \(error)")
        }
    }

}

// 辅助小组件：标签
struct BadgeView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2))
            .cornerRadius(4)
    }
}


extension SelectorMediaSourceArguments {
    static var mock: SelectorMediaSourceArguments {
        let json = #"""
{
          "name": "omofun111",
          "description": "直连，来自omofun动漫视频网，导航：https://enlienli.link/",
          "iconUrl": "https://enlienli.link/upload/mxprocms/20230707-1/49f4b8a7fd5cbf77ffcfa7a52e755675.gif",
          "searchConfig": {
            "searchUrl": "https://enlienli.link/vod/search.html?wd={keyword}",
            "searchUseOnlyFirstWord": true,
            "subjectFormatId": "a",
            "selectorSubjectFormatA": {
              "selectLists": ".module-card-item>.module-card-item-info>.module-card-item-title>a",
              "preferShorterName": false
            },
            "channelFormatId": "index-grouped",
            "selectorChannelFormatFlattened": {
              "selectChannelNames": "div>div>div>div>div>div.module-tab-items-box>.module-tab-item>span",
              "matchChannelName": "(?!高清线路3)",
              "selectEpisodeLists": ".module-play-list-content",
              "selectEpisodesFromList": "a",
              "selectEpisodeLinksFromList": "",
              "matchEpisodeSortFromName": "第\\s*(?<ep>.+)\\s*[话集]"
            },
            "defaultResolution": "1080P",
            "defaultSubtitleLanguage": "CHS",
            "onlySupportsPlayers": [],
            "selectMedia": {
              "distinguishSubjectName": true,
              "distinguishChannelName": true
            },
            "matchVideo": {
              "enableNestedUrl": true,
              "matchNestedUrl": "$^",
              "matchVideoUrl": "(^http(s)?:\\/\\/(?!.*http).+\\.(mp4|m3u8|flv|mkv))|(url=(?<v>http(s)?:\\/\\/.+\\.(mp4|m3u8|flv|mkv)))|(^http(s)?:\\/\\/(?!.*http).+(sign\\.bytetos|sign\\.byteimg|mcloud\\.139|cloudflarestorage|tos-cn)\\.com(?!.*\\.ts).+(-expires|-signature))|((bilivideo|akamaized|szbdyd)\\.com(?!.*\\.ts))|(\\/video\\/tos\\/alisg\\/)|(\\/video\\/.*mime_type=video)",
              "cookies": "",
              "addHeadersToVideo": {
                "referer": "",
"userAgent":""
              }
            }
          },
          "tier": 0
        }
"""#.data(using: .utf8)!
        
        return try! JSONDecoder().decode(SelectorMediaSourceArguments.self, from: json)
    }
}


struct AnimeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        AnimeDetailView(bgmId: 515759, openEpisodePlayer: { _, _, _ in })
        .previewDevice("Apple TV 4K (3rd generation)")
    }
}
