//
//  AnimePlayerContainerView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/15.
//


import SwiftUI
import AVKit

struct AnimePlayerContainerView: View {
    @State private var player = AVPlayer()
    @State private var videoSources: [VideoSource] = []
    @State private var isLoading = true
    
    // 💥 1. 新增一个 State 来强引用监听器，防止它被销毁
    @State private var statusObservation: NSKeyValueObservation?
    
    let episodeInfo: BgmEpisodeInfo
    let sessionTitle: String
    @State private var text = "正在解析番剧源..."

    var body: some View {
        ZStack {
            AdvancedVideoPlayer(player: player, title:sessionTitle, sort: Int(episodeInfo.sort), availableSources: videoSources)
                .ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text(text)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .onAppear {
            fetchStream()
        }
        .onDisappear {
            // 退出时清理资源和监听器
            player.pause()
            player.replaceCurrentItem(with: nil)
            statusObservation?.invalidate()
            statusObservation = nil
        }
    }
    
    private func onSwitch(resource: VideoResource){
        let playerItem = AVPlayerItem(url: URL(string: resource.url)!)
        playerItem.externalMetadata = createMetadata()

        // 💥 2. 把返回的监听器赋值给 State 变量
        statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { item, _ in
            // 因为是异步回调，确保在主线程打印和处理
            DispatchQueue.main.async {
                if item.status == .failed {
                    print("❌ 播放失败: \(String(describing: item.error?.localizedDescription))")
                    if let error = item.error as NSError? {
                        print("❌ 详细错误信息: \(error.userInfo)")
                    }
                    text = "播放失败"
                } else if item.status == .readyToPlay {
                    print("✅ 准备就绪，可以播放")
                    isLoading = false
                } else if item.status == .unknown {
                    print("⏳ 状态未知，正在缓冲...")
                }
            }
        }

        player.replaceCurrentItem(with: playerItem)
        player.play()
    }
    
    private func fetchStream() {
        Task { @MainActor in
            await doFetch()
//            guard let url =  else {
//                return
//            }

            
            
        }
    }

    private func doFetch() async -> URL?{
        let config = MediaSourceConfig(serializedArguments: nil, arguments:SelectorMediaSourceArguments.mock)
        let a =  SelectorMediaSource(mediaSourceId: "1", config: config, repository: SelectorMediaSourceEpisodeCacheRepository(), client: URLSessionHTTPClient())
        print(episodeInfo.name)
        let result = await a.fetch(query: MediaFetchRequest(
            subjectId: "\(episodeInfo.subjectId)", episodeId: "\(episodeInfo.id)", subjectNameCN: sessionTitle, subjectNames: [sessionTitle], episodeSort: .normal(number: Float(Int(episodeInfo.sort))), episodeName: "\(episodeInfo.nameCN)", episodeEp: .normal(number: Float(Int(episodeInfo.ep)))
        ))
        let resolver = TVOSMediaResolver()
        
        print(result)
        var index = 0;
        for r in result{
            print("解析地址: \(r.media.originalUrl)")
            do {
                let link = try await resolver.resolve(pageUrl: r.media.originalUrl, config: config.arguments!.searchConfig.matchVideo)
                print("🎉 最终 m3u8 直链: \(link.m3u8Url)")
                print("📋 请求头: \(link.headers)")
                print("🍪 Cookies: \(link.cookieString)")
//                return URL(string:link.m3u8Url)
                videoSources.append(VideoSource(sourceName: "\(index)", resources: [VideoResource(resourceName: "\(index)", url: link.m3u8Url, headers: link.headers)]))
                index+=1
            }catch {
                print("❌ 解析失败或超时: \(error.localizedDescription)")
            }
        }
//        text = "解析失败：没有找到对应的番剧\(sessionTitle),\(episodeInfo.sort),\(episodeInfo.ep)"
        return nil
    }
    
    private func createMetadata() -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []
        
        // 1. 设置主标题 (例如："葬送的芙莉莲")
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = episodeInfo.nameCN as NSString // 使用你传入的 title
        titleItem.extendedLanguageTag = "und" // "und" 表示 undefined，通用语言标签
        metadata.append(titleItem)
        
        // 2. 设置副标题或简介 (例如："第 1 集")
        let subtitle = AVMutableMetadataItem()
        subtitle.identifier = .commonIdentifierCreationDate
        subtitle.value =  "\(sessionTitle) 第 \(Int(episodeInfo.ep)) 集" as NSString // 结合你传入的 sort 变量
        subtitle.extendedLanguageTag = "und"
        metadata.append(subtitle)
        
        // 2. 设置副标题或简介 (例如："第 1 集")
        let descItem = AVMutableMetadataItem()
        descItem.identifier = .commonIdentifierDescription
        descItem.value =  episodeInfo.desc as NSString // 结合你传入的 sort 变量
        descItem.extendedLanguageTag = "und"
        metadata.append(descItem)
        
        // 3. 设置流派/分类 (显示在标题上方的小字，例如："AniTV 播放器")
        let genreItem = AVMutableMetadataItem()
        genreItem.identifier = .quickTimeMetadataAlbum
        genreItem.value = sessionTitle as NSString
        genreItem.extendedLanguageTag = "und"
        metadata.append(genreItem)
        
        return metadata
    }
    
}

#Preview {
    AnimePlayerContainerView(
        episodeInfo: BgmEpisodeInfo(
            id: 1,
            subjectId: 1,
            type: 1,
            ep: 1.0,
            sort: 1.0,
            name: "test",
            nameCN: "test",
            duration: "test",
            durationSeconds: 0,
            airdate: "test",
            comment: 0,
            desc: "test",
            disc: 0
        ),
        sessionTitle: "test"
    )
    .zIndex(0)
}
