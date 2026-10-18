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

    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.detailOnly)) {
        self._columnVisibility = columnVisibility
    }

    @State private var selectedSubpage: SettingsSubpage? = nil
    @State private var currentProfile: UserProfile? = nil
    @State private var isDebugRenderEnabled: Bool = TVOSMediaResolver.isDebugRenderEnabled

    // Setting values
    @State private var searchConcurrency: Int = 5
    @State private var completionThreshold: Double = 0.9
    @State private var isAutoPlayNext: Bool = true
    @State private var isRememberDanmakuState: Bool = true
    @State private var subscriptionURLString: String = MediaSourceConfigLoader.defaultSubscriptionURL.absoluteString

    private enum BangumiOAuthConfig {
        static let clientID = AppConfig.bangumiOAuthClientID
        static let appCallbackURL = BangumiOAuthManager.defaultRedirectURI
        static let secret = AppConfig.bangumiOAuthClientSecret
    }

    private var currentTitle: String {
        selectedSubpage?.rawValue ?? "设置"
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
        .background(
            Color.black.opacity(0.2)
        )
        .ignoresSafeArea()
        .task {
            await loadSettings()
        }
        .onExitCommand {
            if selectedSubpage != nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedSubpage = nil
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    columnVisibility = .all
                }
            }
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

    // MARK: - Left Panel Views (Centered horizontally, shifted upwards, 2x enlarged)
    @ViewBuilder
    private var leftPanelView: some View {
        VStack(alignment: .center, spacing: 24) {
            Spacer().frame(height: 10)

            if let subpage = selectedSubpage {
                switch subpage {
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
                if let profile = currentProfile, profile.isAuthenticated {
                    userProfileCard(profile: profile)
                } else {
                    unauthenticatedLoginCard
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // Authenticated User Left Card (2x enlarged, pill button)
    private func userProfileCard(profile: UserProfile) -> some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 20)
                    .frame(width: 520, height: 520)

                if let avatarURLString = profile.effectiveAvatar, let url = URL(string: avatarURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            defaultAvatarImage
                        }
                    }
                    .frame(width: 480, height: 480)
                    .clipShape(Circle())
                } else {
                    defaultAvatarImage
                        .frame(width: 480, height: 480)
                        .clipShape(Circle())
                }
            }

            if let nickname = profile.nickname, !nickname.isEmpty {
                Text(nickname)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }

            SettingsPillButton {
                Task {
                    try? await AniTVDatabase.logoutCurrentUser(in: database)
                    await loadSettings()
                }
            } label: {
                Text("登出")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 280, height: 68)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }

    private var defaultAvatarImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
    }

    // Unauthenticated QR & Login Left Card (2x enlarged, pill button)
    private var unauthenticatedLoginCard: some View {
        VStack(spacing: 24) {
            LANLoginQRCodeView(urlString: bangumiOAuthManager.lanEntryURL)
                .frame(width: 520, height: 520)
                .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            SettingsPillButton {
                bangumiOAuthManager.startLogin(
                    clientID: BangumiOAuthConfig.clientID,
                    clientSecret: BangumiOAuthConfig.secret,
                    redirectURI: BangumiOAuthConfig.appCallbackURL
                )
            } label: {
                Text("用 Apple 设备登录")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 360, height: 68)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .disabled(bangumiOAuthManager.isAuthenticating)

            VStack(spacing: 6) {
                Text("扫描二维码或访问")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))

                Text(bangumiOAuthManager.lanEntryURL.isEmpty ? "http://局域网地址/path" : bangumiOAuthManager.lanEntryURL)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // Subpage Left Illustrations (2x enlarged)
    private var playerAndDanmakuLeftIllustration: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 64, style: .continuous)
                    .stroke(.white, lineWidth: 24)
                    .frame(width: 640, height: 420)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .foregroundStyle(.white)
                    .offset(x: 12)
            }

            Capsule()
                .fill(.white)
                .frame(width: 280, height: 32)
        }
    }

    private var dataSourceLeftIllustration: some View {
        VStack(spacing: 24) {
            // Filmstrip icon (2x enlarged)
            HStack(spacing: 40) {
                VStack(spacing: 32) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 280, height: 40)
                    Capsule()
                        .fill(.white)
                        .frame(width: 200, height: 40)
                    Capsule()
                        .fill(.white)
                        .frame(width: 200, height: 40)
                    Capsule()
                        .fill(.white)
                        .frame(width: 200, height: 40)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(.white, lineWidth: 20)
                        .frame(width: 300, height: 320)

                    VStack(spacing: 24) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.8))
                            .frame(width: 180, height: 100)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.8))
                            .frame(width: 180, height: 100)
                    }

                    // Sprocket holes along left and right (2x enlarged)
                    VStack(spacing: 16) {
                        ForEach(0..<4) { _ in
                            HStack(spacing: 248) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            }
        }
    }

    private var developerOptionsLeftIllustration: some View {
        VStack(spacing: 24) {
            Text("{ }")
                .font(.system(size: 320, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text("开启后，解析 m3u8 时会将后台的 WKWebView 全屏渲染在屏幕上")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }

    private var aboutLeftIllustration: some View {
        VStack(spacing: 24) {
            Image(systemName: "info.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 360, height: 360)
                .foregroundStyle(.white)

            Text("AniTV V0.2.0")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Right Panel Views (FocusGuide enabled)
    @ViewBuilder
    private var rightPanelView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let subpage = selectedSubpage {
                switch subpage {
                case .playerAndDanmaku:
                    playerAndDanmakuSettingsOptions
                case .dataSource:
                    dataSourceSettingsOptions
                case .developerOptions:
                    developerOptionsSettingsOptions
                case .about:
                    aboutSettingsOptions
                }
            } else {
                mainSettingsNavigationMenu
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusScope(rightListFocusScope)
        .focusSection()
    }

    // Main Navigation Menu (4 categories)
    private var mainSettingsNavigationMenu: some View {
        VStack(spacing: 16) {
            ForEach(Array(SettingsSubpage.allCases.enumerated()), id: \.element.id) { index, subpage in
                SettingsRowButton {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedSubpage = subpage
                    }
                } label: {
                    HStack {
                        Text(subpage.rawValue)
                            .font(.title3.weight(.medium))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 76)
                }
                .prefersDefaultFocus(index == 0, in: rightListFocusScope)
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
                        .font(.title3.weight(.medium))

                    Spacer()

                    Text("\(Int(completionThreshold * 100))%")
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .prefersDefaultFocus(true, in: rightListFocusScope)

            SettingsRowButton {
                isAutoPlayNext.toggle()
                Task {
                    try? await AniTVDatabase.setAutoPlayNextEnabled(isAutoPlayNext, in: database)
                }
            } label: {
                HStack {
                    Text("自动连播")
                        .font(.title3.weight(.medium))

                    Spacer()

                    Text(isAutoPlayNext ? "是" : "否")
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }

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
                        .font(.title3.weight(.medium))

                    Spacer()

                    Text(isRememberDanmakuState ? "是" : "否")
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
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
                        .font(.title3.weight(.medium))

                    Spacer()

                    Text("\(searchConcurrency)")
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .prefersDefaultFocus(true, in: rightListFocusScope)

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
                        .font(.title3.weight(.medium))

                    Spacer()

                    Text(isDebugRenderEnabled ? "开" : "关")
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 28)
                .frame(height: 76)
            }
            .prefersDefaultFocus(true, in: rightListFocusScope)
        }
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
            .prefersDefaultFocus(true, in: rightListFocusScope)
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
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    Capsule()
                        .fill(isFocused ? Color.white : Color.white.opacity(0.18))
                )
                .scaleEffect(isFocused ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

struct SettingsPillButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Content
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            label()
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .shadow(color: isFocused ? Color.white.opacity(0.5) : Color.black.opacity(0.3), radius: isFocused ? 14 : 6)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
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
                    .padding(16)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.12))
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
