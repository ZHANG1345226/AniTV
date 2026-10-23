//
//  SettingsView.swift
//  AniTV
//
//  Created by Codex on 2026/8/8.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import SQLiteData

enum SettingsSubpage: String, CaseIterable, Identifiable {
    case profile = "个人资料"
    case playerAndDanmaku = "播放器与弹幕"
    case dataSource = "数据源"
    case developerOptions = "开发者选项"
    case about = "关于"

    var id: String { rawValue }
}

struct SettingsView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject private var bangumiOAuthManager: BangumiOAuthManager
    @Dependency(\.defaultDatabase) private var database
    @Namespace private var rightListFocusScope
    @FocusState private var focusedMainMenuSubpage: SettingsSubpage?
    @FocusState private var focusedSubpageItem: String?

    // Left panel illustration opacity constant (75%)
    private static let leftIllustrationOpacity: Double = 0.75

    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.detailOnly)) {
        self._columnVisibility = columnVisibility
    }

    @State private var selectedSubpage: SettingsSubpage? = nil
    @State private var lastSelectedSubpage: SettingsSubpage? = nil
    @State private var showingLoginSheet: Bool = false
    @State private var showingLogoutConfirmation: Bool = false
    @State private var currentProfile: UserProfile? = nil
    @State private var isDebugRenderEnabled: Bool = TVOSMediaResolver.isDebugRenderEnabled

    // Setting values
    @State private var searchConcurrency: Int = 5
    @State private var completionThreshold: Double = 0.9
    @State private var isAutoPlayNext: Bool = true
    @State private var isRememberDanmakuState: Bool = true
    @State private var isHlsAdFilterEnabled: Bool = LocalHlsPlaybackPreparer.isEnabled
    @State private var subscriptionURLString: String = MediaSourceConfigLoader.defaultSubscriptionURL.absoluteString

    private enum BangumiOAuthConfig {
        static let clientID = AppConfig.bangumiOAuthClientID
        static let appCallbackURL = BangumiOAuthManager.defaultRedirectURI
        static let secret = AppConfig.bangumiOAuthClientSecret
    }

    private var currentTitle: String {
        selectedSubpage?.rawValue ?? "设置"
    }

    private func defaultFocusItem(for subpage: SettingsSubpage) -> String {
        switch subpage {
        case .profile:
            return currentProfile?.isAuthenticated == true ? "profile_logout" : "profile_login"
        case .playerAndDanmaku:
            return "player_threshold"
        case .dataSource:
            return "datasource_concurrency"
        case .developerOptions:
            return "developer_debug"
        case .about:
            return "about_repo"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Title
            headerView

            HStack(alignment: .top, spacing: 60) {
                // Left Panel
                leftPanelView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right Panel
                rightPanelView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(
//            Color.black.opacity(0.2)
//        )
        .ignoresSafeArea()
        .task {
            await loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userProfileDidChange)) { _ in
            Task {
                await loadSettings()
            }
        }
        .onExitCommand {
            if selectedSubpage != nil {
                let target = lastSelectedSubpage ?? .profile
                focusedSubpageItem = nil
                withAnimation(.easeInOut(duration: 0.28)) {
                    selectedSubpage = nil
                }
                focusedMainMenuSubpage = target
            } else {
                withAnimation(.easeInOut(duration: 0.28)) {
                    columnVisibility = .all
                }
            }
        }
        .onChange(of: selectedSubpage) { _, newSubpage in
            if let newSubpage {
                focusedMainMenuSubpage = nil
                focusedSubpageItem = defaultFocusItem(for: newSubpage)
            }
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            OOBEProfileSetupView(
                isAuthenticating: bangumiOAuthManager.isAuthenticating,
                statusMessage: bangumiOAuthManager.statusMessage,
                lanEntryURL: bangumiOAuthManager.lanEntryURL,
                lanServiceStatus: bangumiOAuthManager.lanServiceStatus,
                createGuestAction: {
                    Task {
                        _ = try? await AniTVDatabase.insertGuestUserProfile(in: database)
                        await loadSettings()
                        showingLoginSheet = false
                    }
                },
                connectBangumiAction: {
                    bangumiOAuthManager.startLogin(
                        clientID: BangumiOAuthConfig.clientID,
                        clientSecret: BangumiOAuthConfig.secret,
                        redirectURI: BangumiOAuthConfig.appCallbackURL
                    )
                },
                onDismiss: {
                    showingLoginSheet = false
                }
            )
        }
        .onChange(of: showingLoginSheet) { _, isShowing in
            if !isShowing {
                Task {
                    await loadSettings()
                }
            }
        }
        .onChange(of: bangumiOAuthManager.authenticatedSession) { _, session in
            if session != nil {
                showingLoginSheet = false
                Task {
                    await loadSettings()
                }
            }
        }
        .alert("退出登录", isPresented: $showingLogoutConfirmation) {
            Button("退出登录", role: .destructive) {
                Task {
                    try? await AniTVDatabase.logoutCurrentUser(in: database)
                    await loadSettings()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要退出当前账号吗？")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Spacer()
            Text(currentTitle)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.top, 60)
        .padding(.bottom, 30)
    }

    // MARK: - Left Panel Views (Consistent illustration size & position with crossfade)
    @ViewBuilder
    private var leftPanelView: some View {
        VStack(spacing: 24) {
            // Fixed-size illustration container
            ZStack {
                currentLeftIllustration
                    .opacity(Self.leftIllustrationOpacity)
                    .id(selectedSubpage?.rawValue ?? "home_illustration")
                    .transition(.opacity)
            }
            .frame(width: 540, height: 380)

            // Fixed-size hint container so the icon above never jumps
            ZStack(alignment: .top) {
                if let hint = currentLeftHint {
                    Text(hint)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                        .id(hint)
                        .transition(.opacity)
                }
            }
            .frame(width: 540, height: 80, alignment: .top)
            .animation(.easeInOut(duration: 0.2), value: currentLeftHint)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    @ViewBuilder
    private var currentLeftIllustration: some View {
        if let subpage = selectedSubpage {
            switch subpage {
            case .profile:
                profileLeftIllustration
            case .playerAndDanmaku:
                playerAndDanmakuLeftIllustration
            case .dataSource:
                dataSourceLeftIllustration
            case .developerOptions:
                developerOptionsLeftIllustration
            case .about:
                aboutLeftIllustration
            }
        } else {
            homeLeftIllustration
        }
    }

    private var currentLeftHint: String? {
        if let item = focusedSubpageItem {
            switch item {
            case "developer_debug":
                return "开启后，解析 m3u8 时会将后台的 WKWebView 全屏渲染在屏幕上"
            case "player_ad_filter":
                return "自动识别并跳过 m3u8 视频源中插入的切片广告"
            case "danmaku_remember_state":
                return "开启后，播放器将记住弹幕开关状态并在下次播放时恢复"
            default:
                return nil
            }
        }
        if selectedSubpage == .developerOptions {
            return "开启后，解析 m3u8 时会将后台的 WKWebView 全屏渲染在屏幕上"
        }
        return nil
    }

    // Home Left Illustration (Gear)
    private var homeLeftIllustration: some View {
        Image(systemName: "gear")
            .resizable()
            .scaledToFit()
            .frame(width: 360, height: 360)
            .foregroundStyle(.white)
    }

    // Profile Left Illustration (Person)
    private var profileLeftIllustration: some View {
        Image(systemName: "person")
            .resizable()
            .scaledToFit()
            .frame(width: 360, height: 360)
            .foregroundStyle(.white)
    }

    // Subpage Left Illustrations
    private var playerAndDanmakuLeftIllustration: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .stroke(.white, lineWidth: 20)
                    .frame(width: 460, height: 300)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.white)
                    .offset(x: 8)
            }

            Capsule()
                .fill(.white)
                .frame(width: 220, height: 24)
        }
        .frame(width: 540, height: 380)
    }

    private var dataSourceLeftIllustration: some View {
        HStack(spacing: 32) {
            VStack(spacing: 24) {
                Capsule()
                    .fill(.white)
                    .frame(width: 200, height: 32)
                Capsule()
                    .fill(.white)
                    .frame(width: 150, height: 32)
                Capsule()
                    .fill(.white)
                    .frame(width: 150, height: 32)
                Capsule()
                    .fill(.white)
                    .frame(width: 150, height: 32)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(.white, lineWidth: 18)
                    .frame(width: 240, height: 260)

                VStack(spacing: 20) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.8))
                        .frame(width: 140, height: 80)

                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.8))
                        .frame(width: 140, height: 80)
                }

                // Sprocket holes along left and right
                VStack(spacing: 12) {
                    ForEach(0..<4) { _ in
                        HStack(spacing: 196) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white)
                                .frame(width: 20, height: 20)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            }
        }
        .frame(width: 540, height: 380)
    }

    private var developerOptionsLeftIllustration: some View {
        Text("{ }")
            .font(.system(size: 320, weight: .light, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 360, height: 360)
    }

    private var aboutLeftIllustration: some View {
        Image(systemName: "info.circle")
            .resizable()
            .scaledToFit()
            .frame(width: 360, height: 360)
            .foregroundStyle(.white)
    }

    // MARK: - Right Panel Views (FocusGuide enabled)
    @ViewBuilder
    private var rightPanelView: some View {
        ZStack(alignment: .topLeading) {
            mainSettingsNavigationMenu
                .offset(x: selectedSubpage == nil ? 0 : -100)
                .opacity(selectedSubpage == nil ? 1 : 0)
                .allowsHitTesting(selectedSubpage == nil)
                .disabled(selectedSubpage != nil)

            if let subpage = selectedSubpage {
                subpageView(for: subpage)
                    .defaultFocus($focusedSubpageItem, defaultFocusItem(for: subpage), priority: .userInitiated)
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: 100).combined(with: .opacity),
                            removal: .offset(x: 100).combined(with: .opacity)
                        )
                    )
                    .id("subpage_\(subpage.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusScope(rightListFocusScope)
        .focusSection()
    }

    @ViewBuilder
    private func subpageView(for subpage: SettingsSubpage) -> some View {
        switch subpage {
        case .profile:
            profileSettingsOptions
        case .playerAndDanmaku:
            playerAndDanmakuSettingsOptions
        case .dataSource:
            dataSourceSettingsOptions
        case .developerOptions:
            developerOptionsSettingsOptions
        case .about:
            aboutSettingsOptions
        }
    }

    // Main Navigation Menu (5 categories)
    private var mainSettingsNavigationMenu: some View {
        VStack(spacing: 16) {
            ForEach(SettingsSubpage.allCases) { subpage in
                Button {
                    lastSelectedSubpage = subpage
                    focusedMainMenuSubpage = nil
                    focusedSubpageItem = defaultFocusItem(for: subpage)
                    withAnimation(.easeInOut(duration: 0.28)) {
                        selectedSubpage = subpage
                    }
                } label: {
                    SettingsRowContent {
                        HStack {
                            Text(subpage.rawValue)
                                .font(.headline.weight(.medium))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(.horizontal, 28)
                        .frame(height: 76)
                    }
                }
                .buttonStyle(CleanButtonStyle())
                .focused($focusedMainMenuSubpage, equals: subpage)
            }
        }
        .defaultFocus($focusedMainMenuSubpage, lastSelectedSubpage ?? .profile, priority: selectedSubpage == nil ? .userInitiated : .automatic)
    }

    // Subpage: Profile
    @ViewBuilder
    private var profileSettingsOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let profile = currentProfile, profile.isAuthenticated {
                Text("账号信息")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))

                if let nickname = profile.nickname, !nickname.isEmpty {
                    SettingsRowButton {
                    } label: {
                        HStack {
                            Text("用户名")
                                .font(.headline.weight(.medium))

                            Spacer()

                            Text(nickname)
                                .font(.headline.weight(.semibold))
                        }
                        .padding(.horizontal, 28)
                        .frame(height: 76)
                    }
                    .focused($focusedSubpageItem, equals: "profile_username")
                }

                SettingsRowButton {
                    showingLogoutConfirmation = true
                } label: {
                    HStack {
                        Text("退出登录")
                            .font(.headline.weight(.medium))

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 76)
                }
                .focused($focusedSubpageItem, equals: "profile_logout")
            } else {
                Text("账号状态")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))

                SettingsRowButton {
                    showingLoginSheet = true
                } label: {
                    HStack {
                        Text("登录")
                            .font(.headline.weight(.medium))

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 76)
                }
                .focused($focusedSubpageItem, equals: "profile_login")
            }
        }
    }

    // Subpage: Player & Danmaku
    private var playerAndDanmakuSettingsOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("播放器")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))

            SettingsRowButton {
                cycleCompletionThreshold()
            } label: {
                HStack {
                    Text("自动标记为看过")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text("\(Int(completionThreshold * 100))%")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "player_threshold")

            SettingsRowButton {
                isAutoPlayNext.toggle()
                Task {
                    try? await AniTVDatabase.setAutoPlayNextEnabled(isAutoPlayNext, in: database)
                }
            } label: {
                HStack {
                    Text("自动连播")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text(isAutoPlayNext ? "是" : "否")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "player_autoplay")

            SettingsRowButton {
                isHlsAdFilterEnabled.toggle()
                LocalHlsPlaybackPreparer.isEnabled = isHlsAdFilterEnabled
            } label: {
                HStack {
                    Text("过滤切片广告 (实验性)")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text(isHlsAdFilterEnabled ? "是" : "否")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "player_ad_filter")

            Text("弹幕")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 10)

            SettingsRowButton {
                isRememberDanmakuState.toggle()
                Task {
                    try? await AniTVDatabase.setRememberDanmakuStateEnabled(isRememberDanmakuState, in: database)
                }
            } label: {
                HStack {
                    Text("记住弹幕开关状态")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text(isRememberDanmakuState ? "是" : "否")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "danmaku_remember_state")
        }
    }

    // Subpage: Data Source
    private var dataSourceSettingsOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsRowButton {
                cycleSearchConcurrency()
            } label: {
                HStack {
                    Text("播放查询并发数")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text("\(searchConcurrency)")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "datasource_concurrency")

            Text("订阅")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 12)

            SettingsRowButton {
                // Subscription URL detail or action
            } label: {
                HStack {
                    Text(subscriptionURLString)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "datasource_subscription")
        }
    }

    // Subpage: Developer Options
    private var developerOptionsSettingsOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsRowButton {
                isDebugRenderEnabled.toggle()
                TVOSMediaResolver.isDebugRenderEnabled = isDebugRenderEnabled
            } label: {
                HStack {
                    Text("CSS解析Debug模式")
                        .font(.headline.weight(.medium))

                    Spacer()

                    Text(isDebugRenderEnabled ? "开" : "关")
                        .font(.headline.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "developer_debug")
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "AniTV V\(version)"
    }

    // Subpage: About
    private var aboutSettingsOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsRowButton {
                // Repository link
            } label: {
                HStack {
                    Text("https://github.com/moyuwangP/AniTV")
                        .font(.callout)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "about_repo")

            SettingsRowButton {
                // Version info
            } label: {
                HStack {
                    Text("版本号")
                        .font(.callout)

                    Spacer()

                    Text(appVersionString)
                        .font(.callout)
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .focused($focusedSubpageItem, equals: "about_version")
        }
    }

    // MARK: - Actions
    private func loadSettings() async {
        do {
            currentProfile = try await AniTVDatabase.currentUserProfile(in: database)
            searchConcurrency = try await AniTVDatabase.playbackSearchConcurrency(in: database)
            completionThreshold = try await AniTVDatabase.playbackCompletionThreshold(in: database)
            isAutoPlayNext = try await AniTVDatabase.isAutoPlayNextEnabled(in: database)
            isRememberDanmakuState = try await AniTVDatabase.isRememberDanmakuStateEnabled(in: database)
            UserDefaults.standard.set(isRememberDanmakuState, forKey: AniTVDatabase.rememberDanmakuStateSettingKey)
            isHlsAdFilterEnabled = LocalHlsPlaybackPreparer.isEnabled
        } catch {
            print("[SettingsView] Failed to load settings: \(error)")
        }
    }

    private func cycleSearchConcurrency() {
        let values = [1, 3, 5, 8, 10]
        if let idx = values.firstIndex(of: searchConcurrency) {
            searchConcurrency = values[(idx + 1) % values.count]
        } else {
            searchConcurrency = 5
        }
        Task {
            try? await AniTVDatabase.setPlaybackSearchConcurrency(searchConcurrency, in: database)
        }
    }

    private func cycleCompletionThreshold() {
        let values = [0.8, 0.85, 0.9, 0.95]
        if let idx = values.firstIndex(where: { abs($0 - completionThreshold) < 0.01 }) {
            completionThreshold = values[(idx + 1) % values.count]
        } else {
            completionThreshold = 0.9
        }
        Task {
            try? await AniTVDatabase.setPlaybackCompletionThreshold(completionThreshold, in: database)
        }
    }
}

// MARK: - Focus-aware Buttons for tvOS (Pill shape Capsule)
struct SettingsRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Content

    var body: some View {
        Button(action: action) {
            SettingsRowContent(label: label)
        }
        .buttonStyle(CleanButtonStyle())
    }
}

struct SettingsRowContent<Content: View>: View {
    @ViewBuilder let label: () -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label()
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(
                Capsule()
                    .fill(isFocused ? Color.white : Color.white.opacity(0.18))
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

