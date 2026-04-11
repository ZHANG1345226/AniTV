//
//  AppBootstrapView.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import SwiftUI
import Combine
import SQLiteData

@MainActor
final class AppBootstrapModel: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case downloading
        case importing
        case ready
        case failed(String)

        var message: String {
            switch self {
            case .preparing:
                return "正在检查 Bangumi 数据…"
            case .downloading:
                return "正在下载 Bangumi 数据…"
            case .importing:
                return "正在写入 Bangumi 数据…"
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

    init(database: DatabaseQueue) {
        self.database = database
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

    private func bootstrap() async {
        do {
            let release = try await AniTVDatabase.resolveBangumiDataRelease()
            print("[AppBootstrap] Latest bangumi-data version: \(release.version)")

            if try await AniTVDatabase.shouldUpdateBangumiData(to: release, in: database) {
                print("[AppBootstrap] Starting bangumi-data download from \(release.url.absoluteString)")
                phase = .downloading
                let items = try await AniTVDatabase.downloadBangumiData(from: release.url)

                phase = .importing
                try await AniTVDatabase.replaceBangumiData(items, version: release.version, in: database)
            } else {
                print("[AppBootstrap] bangumi-data is already up to date, skipping import")
            }

            print("[AppBootstrap] Bootstrap finished")
            phase = .ready
        } catch {
            AniTVDatabase.logBootstrapError(error)
            print("[AppBootstrap] Bootstrap failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }
}

struct AppBootstrapView: View {
    @StateObject private var model: AppBootstrapModel

    init(database: DatabaseQueue) {
        _model = StateObject(wrappedValue: AppBootstrapModel(database: database))
    }

    var body: some View {
        Group {
            if model.phase == .ready {
                SidebarContentView()
            } else {
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
        .task {
            await model.startIfNeeded()
        }
    }
}
