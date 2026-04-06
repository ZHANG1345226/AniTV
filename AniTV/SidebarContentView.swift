//
//  SidebarContentView.swift
//  AniTV
//
//  Created by Codex on 2426/4/4.
//

import SwiftUI

enum NavigationCategory: String, Hashable {
    case search
    case home
    case animeList
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
    @FocusState private var focusedCategory: NavigationCategory?
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
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(currentUser)
                                        .font(.headline)
                                    Text("切换账户")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 40, trailing: 0))
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
                    }

                    Section {
                        NavigationLink(value: NavigationCategory.settings) {
                            Label("设置", systemImage: "gear")
                        }
                        .prefersDefaultFocus(selectedCategory == .settings, in: sidebarFocusScope)
                        .focused($focusedCategory, equals: .settings)
                    }
                }
                .focusScope(sidebarFocusScope)
            } detail: {
                SidebarDetailView(
                    selectedCategory: $selectedCategory,
                    columnVisibility: $columnVisibility,
                    openAnimeDetail: openAnimeDetail
                )
            }

            if let bgmId = presentedAnimeDetailID {
                AnimeDetailScreen(
                    bgmId: bgmId,
                    onClose: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            columnVisibility = .detailOnly
                            presentedAnimeDetailID = nil
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
    case player(BgmEpisodeInfo, String)
}

private struct AnimeDetailScreen: View {
    let bgmId: Int
    let onClose: () -> Void
    @State private var navigationPath: [AnimeDetailRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                AnimeDetailView(
                    bgmId: bgmId,
                    openEpisodePlayer: { episodeInfo, sessionTitle in
                        navigationPath.append(.player(episodeInfo, sessionTitle))
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .navigationDestination(for: AnimeDetailRoute.self) { route in
                switch route {
                case .player(let episodeInfo, let sessionTitle):
                    AnimePlayerContainerView(
                        episodeInfo: episodeInfo,
                        sessionTitle: sessionTitle
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationBarBackButtonHidden(true)
                }
            }
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

    var body: some View {
        SidebarPlaceholderView(
            title: "设置",
            systemImage: "gear",
            description: "这里可以放播放偏好、账号与数据源设置。",
            columnVisibility: $columnVisibility
        )
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
