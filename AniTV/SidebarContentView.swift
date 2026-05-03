//
//  SidebarContentView.swift
//  AniTV
//
//  Created by Codex on 2426/4/4.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

enum NavigationCategory: String, Hashable {
    case search
    case home
    case animeList
    case timeline
    case settings
}

struct SidebarContentView: View {
    @Environment(\.resetFocus) private var resetFocus
    @AppStorage("AniTV.SelectedCategory") private var selectedCategoryRawValue = NavigationCategory.home.rawValue
    @State private var selectedCategory: NavigationCategory? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var presentedAnimeDetailID: Int?
    @State private var showingProfileSelection = false
    @State private var currentUser = "User"
    @State private var timelineFocusRestoreToken = 0
    @State private var timelineLastFocusedEntryID: String?
    @State private var timelinePendingRestoreEntryID: String?
    @FocusState private var focusedCategory: NavigationCategory?
    @FocusState private var isProfileButtonFocused: Bool
    @Namespace private var sidebarFocusScope

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: $selectedCategory) {
                    Section {
                        Button {
                            showingProfileSelection = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)

                                VStack(alignment: .leading, spacing: 2) {
                                    ZStack(alignment: .leading) {
                                        Text(currentUser)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .opacity(isProfileButtonFocused ? 0 : 1)

                                        Text(currentUser)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                            .opacity(isProfileButtonFocused ? 1 : 0)
                                    }

                                    if isProfileButtonFocused {
                                        Text("切换账户")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.72))
                                            .transition(
                                                .opacity.combined(with: .move(edge: .top))
                                            )
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .center)

                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, 6)
                            .animation(.easeInOut(duration: 0.22), value: isProfileButtonFocused)
                        }
                        .buttonStyle(.plain)
                        .focused($isProfileButtonFocused)
                    }

                    Section {
                        NavigationLink(value: NavigationCategory.search) {
                            Label("搜索", systemImage: "magnifyingglass")
                        }
                        .prefersDefaultFocus(selectedCategory == .search, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .search)

                        NavigationLink(value: NavigationCategory.home) {
                            Label("首页", systemImage: "house")
                        }
                        .prefersDefaultFocus(selectedCategory == .home, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .home)

                        NavigationLink(value: NavigationCategory.animeList) {
                            Label("我的追番", systemImage: "play.tv")
                        }
                        .prefersDefaultFocus(selectedCategory == .animeList, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .animeList)

                        NavigationLink(value: NavigationCategory.timeline) {
                            Label("时间线", systemImage: "calendar")
                        }
                        .prefersDefaultFocus(selectedCategory == .timeline, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .timeline)

                        NavigationLink(value: NavigationCategory.settings) {
                            Label("设置", systemImage: "gear")
                        }
                        .prefersDefaultFocus(selectedCategory == .settings, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .settings)
                    }.padding(.top, 60)
                }
                .focusScope(sidebarFocusScope)
            } detail: {
                SidebarDetailView(
                    selectedCategory: $selectedCategory,
                    columnVisibility: $columnVisibility,
                    timelineFocusRestoreToken: timelineFocusRestoreToken,
                    timelineLastFocusedEntryID: $timelineLastFocusedEntryID,
                    timelinePendingRestoreEntryID: $timelinePendingRestoreEntryID,
                    openAnimeDetail: openAnimeDetail
                )
            }
            .disabled(presentedAnimeDetailID != nil)
            .allowsHitTesting(presentedAnimeDetailID == nil)

            if let bgmId = presentedAnimeDetailID {
                AnimeDetailScreen(
                    bgmId: bgmId,
                    onClose: {
                        let shouldRestoreTimelineFocus = selectedCategory == .timeline
                        let restoreEntryID = timelineLastFocusedEntryID
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            columnVisibility = .detailOnly
                            presentedAnimeDetailID = nil
                        }

                        if shouldRestoreTimelineFocus {
                            Task { @MainActor in
                                timelinePendingRestoreEntryID = restoreEntryID
                                await Task.yield()
                                try? await Task.sleep(for: .milliseconds(250))
                                timelineFocusRestoreToken += 1
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingProfileSelection) {
            ProfileSwitcherView(currentUser: $currentUser)
        }
        .onAppear {
            selectedCategory = NavigationCategory(rawValue: selectedCategoryRawValue) ?? .home
            requestSidebarFocus()
        }
        .onChange(of: selectedCategory) { _, newValue in
            selectedCategoryRawValue = newValue?.rawValue ?? NavigationCategory.home.rawValue
        }
        .onChange(of: columnVisibility) { oldValue, newValue in
            guard oldValue == .detailOnly, newValue != .detailOnly else { return }
            requestSidebarFocus()
        }
    }

    private func openAnimeDetail(_ bgmId: Int) {
        presentedAnimeDetailID = bgmId
    }

    private func requestSidebarFocus() {
        Task { @MainActor in
            focusedCategory = nil
            await Task.yield()
            guard columnVisibility != .detailOnly else { return }
            focusedCategory = selectedCategory ?? .home
            resetFocus(in: sidebarFocusScope)
        }
    }
}

private enum AnimeDetailRoute: Hashable {
    case player([BgmEpisodeInfo], Int, String)
}

private struct AnimeEpisodePlayerScreen: View {
    let episodes: [BgmEpisodeInfo]
    let initialEpisodeID: Int
    let sessionTitle: String

    @State private var currentEpisodeIndex: Int = 0

    private var currentEpisode: BgmEpisodeInfo? {
        guard episodes.indices.contains(currentEpisodeIndex) else { return nil }
        return episodes[currentEpisodeIndex]
    }

    var body: some View {
        Group {
            if let currentEpisode {
                AnimePlayerContainerView(
                    episodeInfo: currentEpisode,
                    sessionTitle: sessionTitle,
                    onPlaybackCompleted: playNextEpisodeIfPossible
                )
                .id(currentEpisode.id)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
            currentEpisodeIndex = episodes.firstIndex(where: { $0.id == initialEpisodeID }) ?? 0
        }
    }

    private func playNextEpisodeIfPossible() {
        let nextIndex = currentEpisodeIndex + 1
        guard episodes.indices.contains(nextIndex) else { return }
        currentEpisodeIndex = nextIndex
    }
}

private struct AnimeDetailScreen: View {
    @Environment(\.resetFocus) private var resetFocus
    let bgmId: Int
    let onClose: () -> Void
    @State private var navigationPath: [AnimeDetailRoute] = []
    @Namespace private var detailFocusScope

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                AnimeDetailView(
                    bgmId: bgmId,
                    openEpisodePlayer: { episodes, episodeInfo, sessionTitle in
                        navigationPath.append(.player(episodes, episodeInfo.id, sessionTitle))
                    }
                )
            }
            .focusScope(detailFocusScope)
            .focusSection()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .navigationDestination(for: AnimeDetailRoute.self) { route in
                switch route {
                case .player(let episodes, let episodeID, let sessionTitle):
                    AnimeEpisodePlayerScreen(
                        episodes: episodes,
                        initialEpisodeID: episodeID,
                        sessionTitle: sessionTitle
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .onAppear {
            resetFocus(in: detailFocusScope)
        }
        .onExitCommand {
            if navigationPath.isEmpty {
                onClose()
            } else {
                navigationPath.removeLast()
            }
        }
    }
}

private struct SidebarDetailView: View {
    @Binding var selectedCategory: NavigationCategory?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let timelineFocusRestoreToken: Int
    @Binding var timelineLastFocusedEntryID: String?
    @Binding var timelinePendingRestoreEntryID: String?
    let openAnimeDetail: (Int) -> Void

    var body: some View {
        Group {
            switch selectedCategory ?? .home {
            case .search:
                SearchPlaceholderView(
                    columnVisibility: $columnVisibility,
                    openAnimeDetail: openAnimeDetail
                )
            case .home:
                HomeView(openAnimeDetail: openAnimeDetail)
            case .animeList:
                AnimeListPlaceholderView(columnVisibility: $columnVisibility)
            case .timeline:
                TimelineView(
                    focusRestoreToken: timelineFocusRestoreToken,
                    lastFocusedEntryID: $timelineLastFocusedEntryID,
                    pendingRestoreEntryID: $timelinePendingRestoreEntryID,
                    openAnimeDetail: openAnimeDetail
                )
            case .settings:
                SettingsPlaceholderView(columnVisibility: $columnVisibility)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SearchPlaceholderView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let openAnimeDetail: (Int) -> Void
    @State private var bgmIDText = ""

    private var parsedBgmID: Int? {
        let trimmed = bgmIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "按 BGM ID 跳转",
                systemImage: "magnifyingglass",
                description: Text("输入番剧的 bgmId，确认后直接打开详情页。")
            )

            VStack(spacing: 16) {
                TextField("例如：515759", text: $bgmIDText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 424)

                if let bgmID = parsedBgmID {
                    Button {
                        openAnimeDetail(bgmID)
                    } label: {
                        Label("确认并打开详情", systemImage: "arrow.right.circle.fill")
                            .frame(minWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("请输入有效的正整数 bgmId", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            Button("打开侧边栏") {
                columnVisibility = .all
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AnimeListPlaceholderView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        SidebarPlaceholderView(
            title: "我的追番",
            systemImage: "play.tv",
            description: "这里可以展示你已收藏、追更中的番剧列表。",
            columnVisibility: $columnVisibility
        )
    }
}

private struct SettingsPlaceholderView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject private var bangumiOAuthManager: BangumiOAuthManager

    private enum BangumiOAuthConfig {
        static let clientID = BangumiOAuthManager.sharedClientID
        static let appCallbackURL = BangumiOAuthManager.defaultRedirectURI
        static let secret = BangumiOAuthManager.sharedClientSecret
        static let relayEndpoint = "/oauth/bangumi"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ContentUnavailableView(
                    "设置",
                    systemImage: "gear",
                    description: Text("这里可以放播放偏好、账号与数据源设置。")
                )

                HStack(alignment: .top, spacing: 24) {
                    appleDeviceLoginCard
                    lanQRCodeLoginCard
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appleDeviceLoginCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("通过 Apple 设备登录")
                .font(.title2.weight(.semibold))

            Text("tvOS 会通过系统认证会话打开 Bangumi OAuth 页面，Bangumi 授权完成后直接回调到 `anitv://oauth/bangumi`。")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                SettingsValueRow(title: "Client ID", value: BangumiOAuthConfig.clientID)
                SettingsValueRow(title: "Bangumi Redirect URI", value: BangumiOAuthConfig.appCallbackURL)
                SettingsValueRow(title: "Callback Scheme", value: BangumiOAuthManager.callbackScheme)
            }

            Button {
                startBangumiLogin()
            } label: {
                Label("通过 Apple 设备登录", systemImage: "person.badge.key")
                    .frame(minWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .disabled(bangumiOAuthManager.isAuthenticating)

            Label(bangumiOAuthManager.statusMessage, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !bangumiOAuthManager.accessToken.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Access Token")
                        .font(.headline)

                    Text(bangumiOAuthManager.accessToken)
                        .font(.footnote.monospaced())
                        .lineLimit(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if !bangumiOAuthManager.rawResponse.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Token Response")
                        .font(.headline)

                    Text(bangumiOAuthManager.rawResponse)
                        .font(.footnote.monospaced())
                        .lineLimit(6)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var lanQRCodeLoginCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("局域网二维码登录")
                .font(.title2.weight(.semibold))

            Text("二维码入口会使用电视当前局域网 IP，并且 Bangumi 授权完成后会直接回调到电视本地 HTTP 服务。")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 24) {
                LANLoginQRCodeView(urlString: bangumiOAuthManager.lanEntryURL)

                VStack(alignment: .leading, spacing: 10) {
                    SettingsValueRow(title: "共享 App ID", value: BangumiOAuthConfig.clientID)
                    SettingsValueRow(title: "Bangumi Redirect URI", value: bangumiOAuthManager.lanRedirectURI)
                    SettingsValueRow(title: "扫码入口", value: bangumiOAuthManager.lanEntryURL)
                    SettingsValueRow(title: "授权回调接口", value: BangumiOAuthConfig.relayEndpoint)
                }
            }

            Label(bangumiOAuthManager.lanServiceStatus, systemImage: "dot.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label("AniTV 现在会启动本地 HTTP 服务。手机扫码后会访问 `/oauth/bangumi/start`，Bangumi 授权完成后会直接回调到电视的 `/oauth/bangumi`。", systemImage: "qrcode")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func startBangumiLogin() {
        bangumiOAuthManager.startLogin(
            clientID: BangumiOAuthConfig.clientID,
            clientSecret: BangumiOAuthConfig.secret,
            redirectURI: BangumiOAuthConfig.appCallbackURL
        )
    }
}

private struct LANLoginQRCodeView: View {
    let urlString: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if !urlString.isEmpty, let image = makeQRCodeImage(from: urlString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .overlay {
                        Text("等待局域网地址")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private func makeQRCodeImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            Text(value.isEmpty ? "未配置" : value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct SidebarPlaceholderView: View {
    let title: String
    let systemImage: String
    let description: String
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            Button("打开侧边栏") {
                columnVisibility = .all
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProfileSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currentUser: String

    private let users = ["User", "追番狂魔", "游客模式"]

    var body: some View {
        NavigationStack {
            List(users, id: \.self) { user in
                Button {
                    currentUser = user
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text(user)
                        Spacer()
                        if user == currentUser {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("选择你的 Profile")
        }
    }
}

#Preview {
    SidebarContentView()
}
