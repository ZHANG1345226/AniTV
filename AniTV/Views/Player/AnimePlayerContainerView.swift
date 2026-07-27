//
//  AnimePlayerContainerView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/15.
//


import SwiftUI
import AVKit
import SQLiteData

private let sourceFetchConcurrency = 1

private struct QueuedVideoResource {
    let sourceIndex: Int
    let resourceIndex: Int
    let resource: VideoResource
}

private struct QueuedVideoResourceKey: Hashable {
    let sourceIndex: Int
    let resourceIndex: Int
}

private struct PlaybackProgressSnapshot {
    let playheadSeconds: Int
    let isCompleted: Bool
}

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
}

struct AnimePlayerContainerView: View {
    @Dependency(\.defaultDatabase) private var database
    @State private var player = AVPlayer()
    @State private var videoSources: [VideoSource] = []
    @State private var isLoading = true
    @State private var isSourcePanelPresented = true
    @State private var sourcePanelPresentationID = 0
    @State private var hasUserSelectedSource = false
    @State private var hasResolvedAutoPlayback = false
    @State private var queuedVideoResources: [QueuedVideoResource] = []
    @State private var queuedVideoResourceKeys: Set<QueuedVideoResourceKey> = []
    @State private var attemptedAutoResourceKeys: Set<QueuedVideoResourceKey> = []
    @State private var isAttemptingPlayback = false
    @State private var fetchSourcesTask: Task<Void, Never>?
    @State private var playbackTask: Task<Void, Never>?
    @State private var lastPlaybackPosition: CMTime?
    @State private var mediaResolver = TVOSMediaResolver.shared
    @StateObject private var sourcePanelModel = SourceSwitchPanelModel()
    @State private var currentBgmUserID: Int?
    @State private var periodicTimeObserver: Any?
    @State private var timeControlStatusObservation: NSKeyValueObservation?
    @State private var lastSavedPlayheadSeconds: Int?
    @State private var playbackCompletionThreshold = AniTVDatabase.defaultPlaybackCompletionThreshold
    @State private var didFinishPlayback = false
    @State private var didSyncCompletionToBangumi = false
    
    // 💥 1. 新增一个 State 来强引用监听器，防止它被销毁
    @State private var statusObservation: NSKeyValueObservation?
    @State private var danmuManager: DanmuViewManager?
    
    let episodeInfo: BgmEpisodeInfo
    let sessionTitle: String
    let initialPlaybackPositionSeconds: Int?
    var onPlaybackCompleted: (() -> Void)? = nil
    @State private var text = "正在解析番剧源..."

    init(
        episodeInfo: BgmEpisodeInfo,
        sessionTitle: String,
        initialPlaybackPositionSeconds: Int? = nil,
        onPlaybackCompleted: (() -> Void)? = nil
    ) {
        self.episodeInfo = episodeInfo
        self.sessionTitle = sessionTitle
        self.initialPlaybackPositionSeconds = initialPlaybackPositionSeconds
        self.onPlaybackCompleted = onPlaybackCompleted
    }

    var body: some View {
        ZStack {
            AdvancedVideoPlayer(
                player: player,
                title: sessionTitle,
                sort: Int(episodeInfo.sort),
                availableSources: videoSources,
                isSourcePanelPresented: $isSourcePanelPresented,
                danmuManager: danmuManager,
                onSourceSelected: handleUserSelectedResource
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
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let finishedItem = notification.object as? AVPlayerItem,
                  finishedItem === player.currentItem else { return }
            didFinishPlayback = true
            finalizePlaybackProgress(trigger: "completed", shouldSyncCompletionToBangumi: true)
            onPlaybackCompleted?()
        }
        .onAppear {
            setupDanmaku(bgmId: episodeInfo.subjectId, sort: episodeInfo.sort)
            hasResolvedAutoPlayback = false
            hasUserSelectedSource = false
            queuedVideoResources = []
            queuedVideoResourceKeys = []
            attemptedAutoResourceKeys = []
            isAttemptingPlayback = false
            didFinishPlayback = false
            didSyncCompletionToBangumi = false
            if let initialPlaybackPositionSeconds, initialPlaybackPositionSeconds > 0 {
                lastPlaybackPosition = CMTime(
                    seconds: Double(initialPlaybackPositionSeconds),
                    preferredTimescale: 600
                )
            } else {
                lastPlaybackPosition = nil
            }
            lastSavedPlayheadSeconds = initialPlaybackPositionSeconds
            configurePlaybackProgressTracking()
            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: handleUserSelectedResource
            )
            Task {
                await loadPlaybackPersistenceContext()
            }
            fetchSourcesTask?.cancel()
            fetchSourcesTask = Task { @MainActor in
                await doFetch()
            }
        }
        .onDisappear {
            // 退出时清理资源和监听器
            finalizePlaybackProgress(trigger: "exit", shouldSyncCompletionToBangumi: true)
            fetchSourcesTask?.cancel()
            fetchSourcesTask = nil
            playbackTask?.cancel()
            playbackTask = nil
            Task { @MainActor in
                mediaResolver.cancelResolve()
            }
            lastPlaybackPosition = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            statusObservation?.invalidate()
            statusObservation = nil
            removePlaybackProgressTracking()
            cleanup()
        }
    }

    private func handleUserSelectedResource(sourceIndex: Int, resourceIndex: Int, resource: VideoResource) {
        hasUserSelectedSource = true
        hasResolvedAutoPlayback = true
        startPlaybackAttempt(
            sourceIndex: sourceIndex,
            resourceIndex: resourceIndex,
            resource: resource,
            isUserInitiated: true
        )
    }

    private func startPlaybackAttempt(
        sourceIndex: Int,
        resourceIndex: Int,
        resource: VideoResource,
        isUserInitiated: Bool
    ) {
        isAttemptingPlayback = true
        playbackTask?.cancel()
        playbackTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        sourcePanelModel.beginSelectionAttempt(sourceIndex: sourceIndex, resourceIndex: resourceIndex)
        onSwitch(resource: resource, isUserInitiated: isUserInitiated)
    }

    private func attemptNextQueuedResourceIfNeeded() {
        guard !hasUserSelectedSource, !hasResolvedAutoPlayback, !isAttemptingPlayback else { return }

        while !queuedVideoResources.isEmpty {
            let next = queuedVideoResources.removeFirst()
            let key = QueuedVideoResourceKey(sourceIndex: next.sourceIndex, resourceIndex: next.resourceIndex)
            queuedVideoResourceKeys.remove(key)
            guard !attemptedAutoResourceKeys.contains(key) else { continue }
            attemptedAutoResourceKeys.insert(key)
            startPlaybackAttempt(
                sourceIndex: next.sourceIndex,
                resourceIndex: next.resourceIndex,
                resource: next.resource,
                isUserInitiated: false
            )
            return
        }
    }

    private func enqueueResources(_ resources: [VideoResource], forSourceIndex sourceIndex: Int) {
        for (resourceIndex, resource) in resources.enumerated() {
            let key = QueuedVideoResourceKey(sourceIndex: sourceIndex, resourceIndex: resourceIndex)
            guard !queuedVideoResourceKeys.contains(key), !attemptedAutoResourceKeys.contains(key) else { continue }
            queuedVideoResources.append(
                QueuedVideoResource(
                    sourceIndex: sourceIndex,
                    resourceIndex: resourceIndex,
                    resource: resource
                )
            )
            queuedVideoResourceKeys.insert(key)
        }
    }

    private func onSwitch(resource: VideoResource, isUserInitiated: Bool){
        playbackTask = Task { @MainActor in
            let currentTime = player.currentTime()
            let currentItemStatus = player.currentItem?.status
            let validCurrentTime = validatedPlaybackPosition(from: currentTime)
            let resumeTime: CMTime?

            if currentItemStatus != .failed, let validCurrentTime {
                resumeTime = validCurrentTime
                lastPlaybackPosition = validCurrentTime
            } else {
                resumeTime = lastPlaybackPosition
            }
            mediaResolver.cancelResolve()
            print("解析地址: \(resource.url)")
            var link: ExtractionResult
            do {
                link = try await mediaResolver.resolve(pageUrl: resource.url, config: resource.matchConfig)
                print("🎉 最终 m3u8 直链: \(link.m3u8Url)")
                print("📋 请求头: \(link.headers)")
                print("🍪 Cookies: \(link.cookieString)")
            }catch {
                if error is CancellationError {
                    return
                }
                print("❌ 解析失败或超时: \(error.localizedDescription)")
                isAttemptingPlayback = false
                sourcePanelModel.markPendingSelectionResolveFailed()
                if !isUserInitiated {
                    attemptNextQueuedResourceIfNeeded()
                }
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
                        isAttemptingPlayback = false
                        sourcePanelModel.markPendingSelectionPlaybackFailed()
                        if !isUserInitiated {
                            attemptNextQueuedResourceIfNeeded()
                        }
                    } else if item.status == .readyToPlay {
                        print("✅ 准备就绪，可以播放")
                        isLoading = false
                        isAttemptingPlayback = false
                        hasResolvedAutoPlayback = true
                        sourcePanelModel.confirmPendingSelection()
                        isSourcePanelPresented = false
                        if let resumeTime {
                            lastPlaybackPosition = resumeTime
                            player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                player.play()
                            }
                        } else {
                            player.play()
                        }
                    } else if item.status == .unknown {
                        print("⏳ 状态未知，正在缓冲...")
                    }
                }
            }
            
            player.replaceCurrentItem(with: playerItem)
        }
    }

    private func doFetch() async -> URL?{
        guard !Task.isCancelled else { return nil }
        let configs: [MediaSourceConfig]
        do {
            configs = try await AniTVDatabase.fetchMediaSourceConfigs(in: database)
        } catch {
            print("[AnimePlayer] Failed to load media sources from database: \(error)")
            videoSources = []
            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: handleUserSelectedResource
            )
            sourcePanelModel.setLoadingSources(Set<Int>())
            return nil
        }

        guard !configs.isEmpty else {
            print("[AnimePlayer] No media sources available in database")
            videoSources = []
            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: handleUserSelectedResource
            )
            sourcePanelModel.setLoadingSources(Set<Int>())
            return nil
        }

        let indexedConfigs = Array(configs.enumerated())

        videoSources = configs.enumerated().map { index, config in
            VideoSource(
                sourceName: config.arguments?.name ?? "Source \(index)",
                resources: []
            )
        }
        sourcePanelModel.update(
            sources: videoSources,
            onSourceSelected: handleUserSelectedResource
        )
        sourcePanelModel.setLoadingSources(Set(indexedConfigs.map(\.0)))

        for batchStart in stride(from: 0, to: indexedConfigs.count, by: sourceFetchConcurrency) {
            guard !Task.isCancelled else { return nil }
            let batchEnd = min(batchStart + sourceFetchConcurrency, indexedConfigs.count)
            let batch = Array(indexedConfigs[batchStart..<batchEnd])

            let batchResults = await withTaskGroup(of: (Int, [VideoResource]).self) { group in
                for (index, config) in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return (index, []) }
                        print("get lines: \(config.arguments?.name ?? "UNKNOWN SOURCE \(index)")")
                        let mediaSource = SelectorMediaSource(
                            mediaSourceId: "1",
                            config: config,
                            repository: SelectorMediaSourceEpisodeCacheRepository(),
                            client: URLSessionHTTPClient()
                        )
                        print(episodeInfo.name)
                        let result = await mediaSource.fetch(query: MediaFetchRequest(
                            subjectId: "\(episodeInfo.subjectId)",
                            episodeId: "\(episodeInfo.id)",
                            subjectNameCN: sessionTitle,
                            subjectNames: [sessionTitle],
                            episodeSort: .normal(number: Float(Int(episodeInfo.sort))),
                            episodeName: "\(episodeInfo.nameCN)",
                            episodeEp: .normal(number: Float(Int(episodeInfo.ep)))
                        ))

                        // 线路选择面板优先选择 session title exact match 的项目
                        let exactMatchedItems = result.filter {
                            $0.media.properties.subjectName == sessionTitle
                        }
                        let displayedItems = exactMatchedItems.isEmpty ? result : exactMatchedItems

                        let resources = displayedItems.map {
                            VideoResource(
                                resourceName: $0.media.properties.alliance,
                                url: $0.media.originalUrl,
                                matchConfig: (config.arguments?.searchConfig.matchVideo)!
                            )
                        }
                        return (index, resources)
                    }
                }

                var collected: [(Int, [VideoResource])] = []
                for await item in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return collected
                    }
                    collected.append(item)
                }
                return collected
            }

            guard !Task.isCancelled else { return nil }
            for (index, resources) in batchResults.sorted(by: { $0.0 < $1.0 }) {
                guard videoSources.indices.contains(index) else { continue }
                videoSources[index] = VideoSource(
                    sourceName: videoSources[index].sourceName,
                    resources: resources
                )
                sourcePanelModel.markSourceLoaded(index)
                enqueueResources(resources, forSourceIndex: index)
            }

            sourcePanelModel.update(
                sources: videoSources,
                onSourceSelected: handleUserSelectedResource
            )
            attemptNextQueuedResourceIfNeeded()
        }
        return nil
    }
    
    private func createMetadata() -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []
        let episodeTitle = resolvedEpisodeTitle()
        
        // 1. 设置主标题 (例如："葬送的芙莉莲")
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = episodeTitle as NSString // 使用你传入的 title
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

    private func resolvedEpisodeTitle() -> String {
        let chineseTitle = episodeInfo.nameCN.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chineseTitle.isEmpty {
            return chineseTitle
        }

        let originalTitle = episodeInfo.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !originalTitle.isEmpty {
            return originalTitle
        }

        return "第 \(Int(episodeInfo.ep)) 集"
    }

    @MainActor
    private func loadPlaybackPersistenceContext() async {
        do {
            let profile = try await AniTVDatabase.currentUserProfile(in: database)
            currentBgmUserID = profile?.effectiveBgmUserID
            playbackCompletionThreshold = try await AniTVDatabase.playbackCompletionThreshold(in: database)
        } catch {
            currentBgmUserID = nil
            playbackCompletionThreshold = AniTVDatabase.defaultPlaybackCompletionThreshold
            print("Failed to load playback persistence context: \(error)")
        }
    }

    private func configurePlaybackProgressTracking() {
        removePlaybackProgressTracking()

        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 600),
            queue: .main
        ) { [weak player] _ in
            guard player != nil else { return }
            persistPlaybackProgress(trigger: "periodic")
        }

        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.old, .new]
        ) { _, change in
            DispatchQueue.main.async {
                if change.newValue == .playing {
                    danmuManager?.play()
                } else if change.newValue == .paused {
                    danmuManager?.pause()
                    if change.oldValue == .playing {
                        persistPlaybackProgress(trigger: "pause")
                    }
                }
            }
        }
    }

    private func removePlaybackProgressTracking() {
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
    }

    private func cleanup() {
        print("🧹 Cleaning up AnimePlayerContainerView...")
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil

        if let periodicTimeObserver = periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        danmuManager = nil
    }

    private func setupDanmaku(bgmId: Int, sort: Double) {
        Task {
            do {
                let bangumi = try await DanDanPlayAPI.shared.getBangumiDetails(bgmId: bgmId)
                let sortString = String(Int(sort))
                var targetEpisodeId: Int? = nil
                
                for ep in bangumi.episodes {
                    if ep.episodeNumber == sortString || ep.episodeTitle == sortString || ep.episodeTitle.contains("第\(sortString)话") || ep.episodeTitle.contains("第\(sortString)集") || ep.episodeTitle == "0\(sortString)" {
                        targetEpisodeId = ep.episodeId
                        break
                    }
                }
                
                if targetEpisodeId == nil {
                    for ep in bangumi.episodes {
                        let numbers = ep.episodeTitle.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                        if numbers.contains(sortString) {
                            targetEpisodeId = ep.episodeId
                            break
                        }
                    }
                }
                
                if targetEpisodeId == nil, let first = bangumi.episodes.first(where: { $0.episodeTitle.contains(sortString) }) {
                    targetEpisodeId = first.episodeId
                }
                
                if let epId = targetEpisodeId {
                    print("[DanDanPlay] Found episode \(epId) for sort \(sort) in bgmId \(bgmId)")
                    let provider = DanDanPlayDanmuProvider(episodeId: epId)
                    let manager = DanmuViewManager(provider: provider)
                    await MainActor.run {
                        self.danmuManager = manager
                        if player.timeControlStatus == .playing || player.rate > 0 {
                            manager.play()
                        }
                    }
                } else {
                    print("[DanDanPlay] Could not find episode matching sort \(sort) in bgmId \(bgmId)")
                }
            } catch {
                print("[DanDanPlay] Failed to get bangumi details for bgmId \(bgmId): \(error)")
            }
        }
    }

    private func persistPlaybackProgress(trigger: String) {
        guard let snapshot = currentPlaybackProgressSnapshot(includeCompletionThreshold: false) else { return }
        saveLocalPlaybackProgress(
            snapshot.isCompleted ? 0 : snapshot.playheadSeconds,
            trigger: trigger
        )
    }

    private func finalizePlaybackProgress(
        trigger: String,
        shouldSyncCompletionToBangumi: Bool
    ) {
        guard let snapshot = currentPlaybackProgressSnapshot(includeCompletionThreshold: true) else { return }

        let persistedSeconds = snapshot.isCompleted ? 0 : snapshot.playheadSeconds
        saveLocalPlaybackProgress(persistedSeconds, trigger: trigger)

        guard shouldSyncCompletionToBangumi,
              snapshot.isCompleted,
              !didSyncCompletionToBangumi,
              currentBgmUserID != nil else { return }

        didSyncCompletionToBangumi = true

        Task {
            let repository = BangumiRepository()
            do {
                try await repository.ensureSubjectCollectionWatchingIfNeeded(
                    subjectID: episodeInfo.subjectId
                )
                try await repository.markEpisodesWatched(
                    subjectID: episodeInfo.subjectId,
                    episodeIDs: [episodeInfo.id]
                )
                print("Synced watched episode to Bangumi (\(trigger)): subject=\(episodeInfo.subjectId), episode=\(episodeInfo.id)")
            } catch {
                didSyncCompletionToBangumi = false
                print("Failed to sync watched episode to Bangumi (\(trigger)): \(error)")
            }
        }
    }

    private func currentPlaybackProgressSnapshot(
        includeCompletionThreshold: Bool
    ) -> PlaybackProgressSnapshot? {
        let resolvedTime = validatedPlaybackPosition(from: player.currentTime()) ?? lastPlaybackPosition
        guard let resolvedTime else { return nil }

        lastPlaybackPosition = resolvedTime
        let playheadSeconds = max(0, Int(resolvedTime.seconds.rounded(.down)))
        let isCompleted =
            didFinishPlayback
            || (includeCompletionThreshold && completionRatio(for: playheadSeconds) >= playbackCompletionThreshold)

        return PlaybackProgressSnapshot(
            playheadSeconds: playheadSeconds,
            isCompleted: isCompleted
        )
    }

    private func saveLocalPlaybackProgress(_ playheadSeconds: Int, trigger: String) {
        guard let bgmUserID = currentBgmUserID else { return }
        guard lastSavedPlayheadSeconds != playheadSeconds else { return }

        lastSavedPlayheadSeconds = playheadSeconds

        Task {
            do {
                try await AniTVDatabase.upsertLocalEpisodeWatchState(
                    bgmUserID: bgmUserID,
                    episodeID: episodeInfo.id,
                    type: LocalEpisodeWatchState.watchingType,
                    updatedAt: 0,
                    playheadSeconds: playheadSeconds,
                    in: database
                )
                print("Saved playback progress (\(trigger)): episode=\(episodeInfo.id), seconds=\(playheadSeconds)")
            } catch {
                print("Failed to save playback progress (\(trigger)): \(error)")
            }
        }
    }

    private func completionRatio(for playheadSeconds: Int) -> Double {
        let durationSeconds = resolvedDurationSeconds()
        guard durationSeconds > 0 else { return 0 }
        return min(1, Double(playheadSeconds) / Double(durationSeconds))
    }

    private func resolvedDurationSeconds() -> Int {
        if episodeInfo.durationSeconds > 0 {
            return episodeInfo.durationSeconds
        }

        if let duration = validatedPlaybackPosition(from: player.currentItem?.duration ?? .invalid) {
            return max(0, Int(duration.seconds.rounded(.down)))
        }

        return 0
    }

    private func validatedPlaybackPosition(from time: CMTime) -> CMTime? {
        guard time.isValid,
              !time.isIndefinite,
              !time.isNegativeInfinity,
              !time.isPositiveInfinity,
              time.seconds.isFinite,
              time.seconds >= 0 else {
            return nil
        }
        return time
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
