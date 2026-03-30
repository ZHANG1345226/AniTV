//
//  AnimePlayerContainerView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/15.
//


import SwiftUI
import AVKit

private struct SourcePanelOverlayContainer: UIViewControllerRepresentable {
    @ObservedObject var model: SourceSwitchPanelModel

    func makeUIViewController(context: Context) -> SourcePanelOverlayViewController {
        SourcePanelOverlayViewController(model: model)
    }

    func updateUIViewController(_ uiViewController: SourcePanelOverlayViewController, context: Context) {
        uiViewController.update(model: model)
    }
}

private final class SourcePanelOverlayViewController: UIViewController {
    private let hostingController: UIHostingController<SourceSwitchPanelView>

    init(model: SourceSwitchPanelModel) {
        hostingController = UIHostingController(rootView: SourceSwitchPanelView(model: model))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        setupHostingController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestPanelFocus()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let focusableView = findFirstFocusableView(in: hostingController.view) {
            return [focusableView]
        }
        return [hostingController.view]
    }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        guard let previouslyFocusedView = context.previouslyFocusedView,
              isDescendant(previouslyFocusedView, of: hostingController.view) else {
            return true
        }

        guard let nextFocusedView = context.nextFocusedView else {
            return false
        }

        if isDescendant(nextFocusedView, of: hostingController.view) {
            return true
        }

        let heading = context.focusHeading
        if heading.contains(.up) || heading.contains(.down) {
            return false
        }

        return false
    }

    func update(model: SourceSwitchPanelModel) {
    }

    private func setupHostingController() {
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }
    private func requestPanelFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.hostingController.view.setNeedsLayout()
            self.hostingController.view.layoutIfNeeded()
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            self.hostingController.view.setNeedsFocusUpdate()
            self.hostingController.view.updateFocusIfNeeded()
        }
    }

    private func isDescendant(_ view: UIView, of ancestor: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate === ancestor {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private func findFirstFocusableView(in rootView: UIView) -> UIView? {
        if rootView.canBecomeFocused, !rootView.isHidden, rootView.alpha > 0.01 {
            return rootView
        }

        for subview in rootView.subviews {
            if let match = findFirstFocusableView(in: subview) {
                return match
            }
        }

        return nil
    }
}

struct AnimePlayerContainerView: View {
    @State private var player = AVPlayer()
    @State private var videoSources: [VideoSource] = []
    @State private var isLoading = true
    @State private var isSourcePanelPresented = false
    @State private var sourcePanelPresentationID = 0
    @StateObject private var sourcePanelModel = SourceSwitchPanelModel()
    
    // 💥 1. 新增一个 State 来强引用监听器，防止它被销毁
    @State private var statusObservation: NSKeyValueObservation?
    
    let episodeInfo: BgmEpisodeInfo
    let sessionTitle: String
    @State private var text = "正在解析番剧源..."

    var body: some View {
        ZStack {
            AdvancedVideoPlayer(
                player: player,
                title: sessionTitle,
                sort: Int(episodeInfo.sort),
                availableSources: videoSources,
                isSourcePanelPresented: $isSourcePanelPresented,
                onSourceSelected: onSwitch(resource:)
            )
                .ignoresSafeArea()

            if isSourcePanelPresented {
                VStack(spacing: 0) {
                    SourcePanelOverlayContainer(model: sourcePanelModel)
                    .id(sourcePanelPresentationID)
                    .frame(width: 1760, height: 360)
                    .padding(.top, 0)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
                .onExitCommand {
                    isSourcePanelPresented = false
                }
            }
            
//            if isLoading {
//                VStack(spacing: 20) {
//                    ProgressView()
//                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
//                        .scaleEffect(1.5)
//                    Text(text)
//                        .foregroundColor(.gray)
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .background(Color.black)
//            }
        }
        .animation(.easeOut(duration: 0.2), value: isSourcePanelPresented)
        .onChange(of: isSourcePanelPresented) { _, isPresented in
            guard isPresented else { return }
            sourcePanelPresentationID += 1
        }
        .onAppear {
            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: { resource in
                    isSourcePanelPresented = false
                    onSwitch(resource: resource)
                }
            )
            onSwitch(resource: VideoResource(resourceName: "", url: "", matchConfig: SelectorSearchConfig.MatchVideoConfig()))
            Task { @MainActor in
                await doFetch()
            }
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
        Task { @MainActor in
            let resolver = TVOSMediaResolver()
            print("解析地址: \(resource.url)")
            var link: ExtractionResult
            do {
                link = try await resolver.resolve(pageUrl: resource.url, config: resource.matchConfig)
                print("🎉 最终 m3u8 直链: \(link.m3u8Url)")
                print("📋 请求头: \(link.headers)")
                print("🍪 Cookies: \(link.cookieString)")
            }catch {
                print("❌ 解析失败或超时: \(error.localizedDescription)")
                return
            }
                        
            
            let playerItem = AVPlayerItem(url: URL(string: link.m3u8Url)!)
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
    }

    private func doFetch() async -> URL?{
        for (index, config) in getConfig().enumerated(){
            print("get lines: \(config.arguments?.name ?? "UNKNOWN SOURCE \(index)")")
            let a =  SelectorMediaSource(mediaSourceId: "1", config: config, repository: SelectorMediaSourceEpisodeCacheRepository(), client: URLSessionHTTPClient())
            print(episodeInfo.name)
            let result = await a.fetch(query: MediaFetchRequest(
                subjectId: "\(episodeInfo.subjectId)", episodeId: "\(episodeInfo.id)", subjectNameCN: sessionTitle, subjectNames: [sessionTitle], episodeSort: .normal(number: Float(Int(episodeInfo.sort))), episodeName: "\(episodeInfo.nameCN)", episodeEp: .normal(number: Float(Int(episodeInfo.ep)))
            ))
            
            var videoResources: [VideoResource] = []
            for r in result {
                videoResources.append(VideoResource(resourceName: r.media.properties.alliance, url: r.media.originalUrl, matchConfig: (config.arguments?.searchConfig.matchVideo)!))
            }
            
            videoSources.append(VideoSource(sourceName: config.arguments?.name ?? "Source \(index)", resources: videoResources))
            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: { resource in
                    isSourcePanelPresented = false
                    onSwitch(resource: resource)
                }
            )

        }
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
