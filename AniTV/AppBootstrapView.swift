//
//  AppBootstrapView.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import SwiftUI
import Combine
import SQLiteData
import CoreImage.CIFilterBuiltins
import UIKit

@MainActor
final class AppBootstrapModel: ObservableObject {
    enum Phase: Equatable {
        case oobe
        case preparing
        case downloadingBangumiData
        case importingBangumiData
        case downloadingMediaSources
        case importingMediaSources
        case ready
        case failed(String)

        var message: String {
            switch self {
            case .oobe:
                return ""
            case .preparing:
                return "正在准备应用…"
            case .downloadingBangumiData:
                return "正在下载 Bangumi 数据…"
            case .importingBangumiData:
                return "正在写入 Bangumi 数据…"
            case .downloadingMediaSources:
                return "正在下载数据源配置…"
            case .importingMediaSources:
                return "正在写入数据源配置…"
            case .ready:
                return ""
            case .failed(let message):
                return message
            }
        }
    }

    @Published private(set) var phase: Phase = .preparing

    private let database: DatabaseQueue
    private var didStart = false
    private weak var bangumiOAuthManager: BangumiOAuthManager?
    private var bangumiTokenRefreshTask: Task<Void, Never>?
    private var bangumiDataRefreshLoopTask: Task<Void, Never>?
    private var bangumiDataRefreshTask: Task<Void, Never>?
    private var mediaSourceRefreshTask: Task<Void, Never>?

    init(database: DatabaseQueue) {
        self.database = database
    }

    func setBangumiOAuthManager(_ bangumiOAuthManager: BangumiOAuthManager) {
        self.bangumiOAuthManager = bangumiOAuthManager
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await bootstrap()
    }

    func retry() async {
        phase = .preparing
        await bootstrap()
    }

    func createGuestProfile() async {
        do {
            _ = try await AniTVDatabase.insertGuestUserProfile(in: database)
            try await AniTVDatabase.setBangumiOAuthRefreshBlocked(false, in: database)
            phase = .preparing
            await bootstrap()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func finishBangumiLogin(session: BangumiAuthenticatedSession) async {
        do {
            _ = try await AniTVDatabase.upsertCurrentUserProfile(
                bgmUserID: session.bgmUserID,
                username: session.username,
                nickname: session.nickname,
                avatar: session.avatar,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                tokenType: session.tokenType,
                expiresAt: session.expiresAt,
                in: database
            )
            try await AniTVDatabase.setBangumiOAuthRedirectURI(session.redirectURI, in: database)
            try await AniTVDatabase.setBangumiOAuthRefreshBlocked(false, in: database)
            phase = .preparing
            await bootstrap()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func bootstrap() async {
        do {
            if try await AniTVDatabase.isMediaSourceEmpty(in: database) {
                try await performInitialMediaSourceLoad()
            }

            if try await AniTVDatabase.currentUserProfile(in: database) == nil {
                bangumiTokenRefreshTask?.cancel()
                bangumiTokenRefreshTask = nil
                bangumiDataRefreshTask?.cancel()
                bangumiDataRefreshTask = nil
                mediaSourceRefreshTask?.cancel()
                mediaSourceRefreshTask = nil
                bangumiDataRefreshLoopTask?.cancel()
                bangumiDataRefreshLoopTask = nil
                phase = .oobe
                return
            }

            if try await AniTVDatabase.isBangumiDataEmpty(in: database) {
                try await performInitialBangumiDataLoad()
            }

            phase = .ready
            startBangumiDataRefreshLoopIfNeeded()
            await triggerBangumiTokenRefreshIfNeeded()
            await triggerBangumiDataRefreshIfNeeded()
            await triggerMediaSourceRefreshIfNeeded()
            print("[AppBootstrap] Bootstrap finished")
        } catch {
            AniTVDatabase.logBootstrapError(error)
            print("[AppBootstrap] Bootstrap failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func performInitialBangumiDataLoad() async throws {
        phase = .preparing

        let release = try await AniTVDatabase.resolveBangumiDataRelease()
        print("[AppBootstrap] Initial bangumi-data load version: \(release.version)")

        phase = .downloadingBangumiData
        let items = try await AniTVDatabase.downloadBangumiData(from: release.url)

        phase = .importingBangumiData
        try await AniTVDatabase.replaceBangumiData(items, version: release.version, in: database)
        print("[AppBootstrap] Initial bangumi-data load finished")
    }

    private func performInitialMediaSourceLoad() async throws {
        phase = .preparing

        let subscriptionURL = MediaSourceConfigLoader.defaultSubscriptionURL.absoluteString
        print("[AppBootstrap] Initial media source load from: \(subscriptionURL)")

        phase = .downloadingMediaSources
        let didUpdate = try await AniTVDatabase.refreshMediaSourcesIfNeeded(in: database)

        phase = .importingMediaSources
        print("[AppBootstrap] Initial media source load finished, updated: \(didUpdate)")
    }

    private func startBangumiDataRefreshLoopIfNeeded() {
        guard bangumiDataRefreshLoopTask == nil else { return }

        bangumiDataRefreshLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                await self.triggerBangumiTokenRefreshIfNeeded()
                await self.triggerBangumiDataRefreshIfNeeded()
                await self.triggerMediaSourceRefreshIfNeeded()
            }
        }
    }

    private func triggerBangumiTokenRefreshIfNeeded() async {
        guard bangumiTokenRefreshTask == nil,
              let bangumiOAuthManager else { return }

        bangumiTokenRefreshTask = Task { @MainActor [weak self, bangumiOAuthManager] in
            guard let self else { return }

            defer {
                self.bangumiTokenRefreshTask = nil
            }

            await bangumiOAuthManager.refreshAccessTokenIfNeeded(in: self.database)
        }
    }

    private func triggerBangumiDataRefreshIfNeeded() async {
        guard bangumiDataRefreshTask == nil else { return }

        do {
            guard try await AniTVDatabase.shouldRefreshBangumiData(in: database) else { return }
        } catch {
            AniTVDatabase.logBootstrapError(error)
            print("[AppBootstrap] Failed to check bangumi-data refresh status: \(error.localizedDescription)")
            return
        }

        bangumiDataRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.bangumiDataRefreshTask = nil
            }

            do {
                let didUpdate = try await AniTVDatabase.refreshBangumiDataIfNeeded(in: self.database)
                print("[AppBootstrap] Background bangumi-data refresh finished, updated: \(didUpdate)")
            } catch {
                AniTVDatabase.logBootstrapError(error)
                print("[AppBootstrap] Background bangumi-data refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func triggerMediaSourceRefreshIfNeeded() async {
        guard mediaSourceRefreshTask == nil else { return }

        do {
            guard try await AniTVDatabase.shouldRefreshMediaSources(in: database) else { return }
        } catch {
            AniTVDatabase.logBootstrapError(error)
            print("[AppBootstrap] Failed to check media source refresh status: \(error.localizedDescription)")
            return
        }

        mediaSourceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.mediaSourceRefreshTask = nil
            }

            do {
                let didUpdate = try await AniTVDatabase.refreshMediaSourcesIfNeeded(in: self.database)
                print("[AppBootstrap] Background media source refresh finished, updated: \(didUpdate)")
            } catch {
                AniTVDatabase.logBootstrapError(error)
                print("[AppBootstrap] Background media source refresh failed: \(error.localizedDescription)")
            }
        }
    }
}

struct AppBootstrapView: View {
    @StateObject private var model: AppBootstrapModel
    @EnvironmentObject private var bangumiOAuthManager: BangumiOAuthManager

    init(database: DatabaseQueue) {
        _model = StateObject(wrappedValue: AppBootstrapModel(database: database))
    }

    var body: some View {
        Group {
            if model.phase == .ready {
                SidebarContentView()
            } else if model.phase == .oobe {
                OOBEProfileSetupView(
                    isAuthenticating: bangumiOAuthManager.isAuthenticating,
                    statusMessage: bangumiOAuthManager.statusMessage,
                    lanEntryURL: bangumiOAuthManager.lanEntryURL,
                    lanServiceStatus: bangumiOAuthManager.lanServiceStatus,
                    createGuestAction: {
                        Task { await model.createGuestProfile() }
                    },
                    connectBangumiAction: {
                        bangumiOAuthManager.startLogin(
                            clientID: BangumiOAuthManager.sharedClientID,
                            clientSecret: BangumiOAuthManager.sharedClientSecret,
                            redirectURI: BangumiOAuthManager.defaultRedirectURI
                        )
                    }
                )
            } else {
                bootstrapProgressView
            }
        }
        .task {
            model.setBangumiOAuthManager(bangumiOAuthManager)
            await model.startIfNeeded()
        }
        .onChange(of: bangumiOAuthManager.authenticatedSession) { _, session in
            guard let session else { return }
            let consumed = bangumiOAuthManager.consumeAuthenticatedSession() ?? session
            Task {
                await model.finishBangumiLogin(session: consumed)
            }
        }
    }

    private var bootstrapProgressView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text(model.phase.message)
                    .font(.headline)
                    .foregroundStyle(.white)

                if case .failed(let message) = model.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

                    Button("重试") {
                        Task {
                            await model.retry()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .padding(32)
        }
    }
}

private struct OOBEProfileSetupView: View {
    let isAuthenticating: Bool
    let statusMessage: String
    let lanEntryURL: String
    let lanServiceStatus: String
    let createGuestAction: () -> Void
    let connectBangumiAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.04, green: 0.05, blue: 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                HStack(alignment: .top, spacing: max(proxy.size.width * 0.15, 180)) {
                    leftColumn(maxWidth: min(proxy.size.width * 0.34, 470))
                    rightColumn(maxWidth: min(proxy.size.width * 0.42, 620))
                }
                .frame(maxWidth: 1580, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 76)
                .padding(.top, proxy.size.height * 0.105)
            }
        }
    }

    @ViewBuilder
    private func leftColumn(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AniTV")
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 42)

                Text("连接至 Bangumi")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)

                Text("通过 Bangumi 账号，你可以管理番剧收藏和收视进度。")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                OOBEActionButton(
                    title: "用 Apple 设备登录",
                    systemImage: "ipad.landscape.and.iphone",
                    action: connectBangumiAction
                )
                .disabled(isAuthenticating)
                .frame(width: 420)

                OOBEActionButton(
                    title: "作为游客继续",
                    systemImage: "person.2",
                    action: createGuestAction
                )
                .disabled(isAuthenticating)
                .frame(width: 420)
            }
            .padding(.top, 270)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func rightColumn(maxWidth: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 0) {
            OOBEQRCodeView(urlString: lanEntryURL)
                .padding(.top, 6)

            VStack(spacing: 14) {
                Text("扫描二维码或访问")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))

                Text(lanEntryURL.isEmpty ? "等待局域网地址" : lanEntryURL)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
            }
            .padding(.top, 54)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: maxWidth)
    }
}

private struct OOBEActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))

                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct OOBEQRCodeView: View {
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
                    .frame(width: 500, height: 500)
                    .padding(36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .frame(width: 572, height: 572)
                    .overlay {
                        VStack(spacing: 14) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 64, weight: .medium))
                                .foregroundStyle(.black.opacity(0.7))

                            Text("等待局域网地址")
                                .font(.headline)
                                .foregroundStyle(.black.opacity(0.7))
                        }
                    }
            }
        }
    }

    private func makeQRCodeImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 14, y: 14)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
