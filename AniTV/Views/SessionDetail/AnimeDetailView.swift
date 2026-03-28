//
//  AnimeDetailView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/13.
//


import SwiftUI
import Kingfisher

struct AnimeDetailView: View {
    let anime: AnimeSubject // 上一轮定义的 DTO
    @State private var showingFullInfo = false
    
    @State private var episodes: [BgmEpisodeInfo] = []
    
    var body: some View {
        ZStack {
            //Layer 1: 沉浸式背景图
            GeometryReader { proxy in
                KFImage(anime.backdrop)
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
                        Text(anime.displayName)
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .shadow(radius: 10)
                        
                        // 2. 标签行 (年份 | 评分 | 类型)


                        HStack(spacing: 20) {
                            if let starts = anime.startDate {
                                var dateString: String {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy年M月"
                                    return formatter.string(from: starts)
                                }
                                BadgeView(text: dateString)
                            }
                            BadgeView(text: anime.type.uppercased())
                            Text(anime.title)
                        }
                        
                        let score: Double = 7.99
                        let count: Int = 2987
                        let rank: Int = 238
                        ScoreView(
                            score: score,
                            count: count,
                            rank: rank
                        )
                        // 给评分和下方的标签加点间距
                        .padding(.bottom, 10)
                        
                        // 3. 简介 (限制行数)
                        Button(action: { self.showingFullInfo = true }) {
                            Text(anime.info) // 或者使用 anime.summary 如果有的话
                                .font(.body)
                                .foregroundColor(.gray)
                                .lineLimit(3)
                                .frame(maxWidth: 900, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        
                        // 4. 操作按钮组
                        HStack(spacing: 20) {
                            Button(action: {
                                print("Play Tapped")
     
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
                                    sessionTitle: anime.titleTranslate.zhHans,
                                    stillURL: anime.backdrop // 这里暂时用 backdrop 演示，实际用 still_path
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
            do {
                let repo = BangumiRepository()
                let response = try await repo.getEpisodes(id: anime.id)
                episodes = response.data
            } catch {
                print("Failed to load episodes: \(error)")
            }
        }
        .sheet(isPresented: $showingFullInfo) {
            VStack(spacing: 30) {
                Text("简介")
                    .font(.title.bold())
                
                ScrollView {
                    Text(anime.info)
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
        AnimeDetailView(anime: AnimeSubject(
            id: 515759,
            title: "葬送のフリーレン 第2期",
            info: "「流泪道别并不适合我们，因为下次再见时会很难为情。」\r\n在勇者欣梅尔一行人击败魔王后的世界中，与欣梅尔等人一同为世界带来和平、活了千年以上的精灵魔法使──芙莉莲。\r\n在面对寿命已尽的欣梅尔之死时，因落下的泪水与心中涌现的情感，踏上了「理解人类之心的旅程」。在旅途中，她与曾由过去伙伴海塔抚养长大的魔法使费伦，以及同为伙伴艾冉的弟子、战士修塔尔克结伴同行，一同朝向灵魂长眠之地前进。\r\n在旅程中，与各种人们相遇交流，并与狡诈的魔族与魔物展开战斗。有时平静温柔，有时无聊琐碎，有时激烈动荡，有时直击心扉……所有的一切、每一个瞬间，都一点一滴地堆叠成三人无可取代的珍贵回忆。而在这趟旅程的终点，究竟等待着他们的会是什么？\r\n魔法使资格测试结束后，他们三人将再度启程──\r\n\r\n\r\n\r\n[简介原文]\r\n「週刊少年サンデー」(小学館)で連載中、山田鐘人(原作)とアベツカサ(作画)による漫画『葬送のフリーレン』。\r\n勇者とそのパーティーによって魔王が倒された“その後”の世界を舞台に、\r\n勇者と共に魔王を打倒した千年以上生きる魔法使い・フリーレンと、彼女が新たに出会う人々の旅路が描かれていく。\r\n“魔王討伐後”という斬新な時系列で展開する胸に刺さるドラマやセリフ、魔法や剣による戦い、\r\n思わず笑ってしまうユーモアなど、キャラクターたちが織り成す物語で、多くの読者を獲得。\r\nこれまでに「マンガ大賞2021」大賞、「第25回手塚治虫文化賞」新生賞、\r\n「第69回(2023年度)小学館漫画賞」、「第48回講談社漫画賞」少年部門など数々の漫画賞を受賞。\r\nそして現在発売中のコミックスは累計部数3200万部を突破！漫画ファンの間で旋風を起こしている。\r\nそれを原作とするTVアニメは2023年9月から2024年3月まで放送され、\r\n国内外で幅広い、数多くのファンを獲得し、大きな反響を呼んだ。\r\nそしてこの度、待望の第2期が2026年1月より日本テレビ系で放送決定！\r\nフリーレンの「人の心を知る旅」が、再び始まる―。",
            score: 7.99,
            // 添加 mock 的 rating 数据
            titleTranslate: TitleTranslate(en: "", zhHans: "葬送的芙莉莲 第二季", zhHant: ""),
            type: "tv",
            lang: "ja",
            begin: "2026-01-16",
            broadcast: "",
            end: "",
            backdrop: URL(string: "https://image.tmdb.org/t/p/original/vnEbPrBGoZItDSv7bfvLBXTpurR.jpg")
        ))
        .previewDevice("Apple TV 4K (3rd generation)")
    }
}
