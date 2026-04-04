//
//  SidebarContentView.swift
//  AniTV
//
//  Created by Codex on 2026/4/4.
//

import SwiftUI

enum AniTVTab: String {
    case search
    case home
    case animeList
}

struct SidebarContentView: View {
    @AppStorage("AniTV.SelectedTab") private var selectedTab: AniTVTab = .home
    @State private var showingProfileSelection = false
    @State private var currentUser = "小明"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("搜索", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchPlaceholderView()
            }

            Tab("首页", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("我的追番", systemImage: "play.tv", value: .animeList) {
                AnimeListPlaceholderView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
//        .tabViewSidebarHeader {
//        }
        .sheet(isPresented: $showingProfileSelection) {
            ProfileSwitcherView(currentUser: $currentUser)
        }
    }
}

private struct SearchPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "搜索",
            systemImage: "magnifyingglass",
            description: Text("这里可以接入全局搜索、历史记录和热门推荐。")
        )
    }
}

private struct AnimeListPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "我的追番",
            systemImage: "play.tv",
            description: Text("这里可以展示你已收藏、追更中的番剧列表。")
        )
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
