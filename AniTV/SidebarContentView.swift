//
//  SidebarContentView.swift
//  AniTV
//
//  Created by Codex on 2026/4/4.
//

import SwiftUI

enum NavigationCategory: String, Hashable {
    case search
    case home
    case animeList
    case settings
}

struct SidebarContentView: View {
    @AppStorage("AniTV.SelectedCategory") private var selectedCategoryRawValue = NavigationCategory.home.rawValue
    @State private var selectedCategory: NavigationCategory? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingProfileSelection = false
    @State private var currentUser = "小明"

    var body: some View {
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
                }

                Section {
                    NavigationLink(value: NavigationCategory.search) {
                        Label("搜索", systemImage: "magnifyingglass")
                    }

                    NavigationLink(value: NavigationCategory.home) {
                        Label("首页", systemImage: "house")
                    }

                    NavigationLink(value: NavigationCategory.animeList) {
                        Label("我的追番", systemImage: "play.tv")
                    }
                }

                Section {
                    NavigationLink(value: NavigationCategory.settings) {
                        Label("设置", systemImage: "gear")
                    }
                }
            }
        } detail: {
            SidebarDetailView(
                selectedCategory: $selectedCategory,
                columnVisibility: $columnVisibility
            )
        }
        .sheet(isPresented: $showingProfileSelection) {
            ProfileSwitcherView(currentUser: $currentUser)
        }
        .onAppear {
            selectedCategory = NavigationCategory(rawValue: selectedCategoryRawValue) ?? .home
        }
        .onChange(of: selectedCategory) { _, newValue in
            selectedCategoryRawValue = newValue?.rawValue ?? NavigationCategory.home.rawValue
        }
    }
}

private struct SidebarDetailView: View {
    @Binding var selectedCategory: NavigationCategory?
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Group {
            switch selectedCategory ?? .home {
            case .search:
                SearchPlaceholderView(columnVisibility: $columnVisibility)
            case .home:
                HomeView()
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

    var body: some View {
        SidebarPlaceholderView(
            title: "搜索",
            systemImage: "magnifyingglass",
            description: "这里可以接入全局搜索、历史记录和热门推荐。",
            columnVisibility: $columnVisibility
        )
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

    private let users = ["小明", "追番狂魔", "游客模式"]

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
