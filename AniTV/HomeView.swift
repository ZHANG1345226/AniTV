//
//  HomeView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//


import SwiftUI

struct HomeView: View {
    let openAnimeDetail: (Int) -> Void

    // 模拟数据：假设这是从 SwiftData 查出来的番剧分类
    let categories = ["最近更新", "我的收藏", "热血动漫", "科幻", "日常"]
    
    var body: some View {
        // 1. 最外层：垂直滚动
        HeroCarouselView(openAnimeDetail: openAnimeDetail)
//        ScrollView(.vertical, showsIndicators: false) {
//            LazyVStack(alignment: .leading, spacing: 40) { // spacing是行间距
//                
//                // 顶部的大海报（Hero Section）通常也是个TabView
//                // ... (可以稍后实现)
//                
//                // 2. 遍历分类
//                ForEach(categories, id: \.self) { category in
//                    VStack(alignment: .leading) {
//                        // 分类标题
//                        Text(category)
//                            .font(.headline) // tvOS的headline很大
//                            .padding(.leading, 50) // 给标题一点左边距，甚至可以不加，因为Focus会自动调整
//                        
//                        // 3. 每一行：水平滚动
//                        ScrollView(.horizontal, showsIndicators: false) {
//                            LazyHStack(spacing: 40) { // spacing是卡片间距
//                                // 为每一行生成 10 个假海报
//                                ForEach(0..<10) { item in
//                                    PosterCard(
//                                        title: "番剧 \(item)",
//                                        imageURL: URL(string: "https://picsum.photos/200/300")
//                                    )
//                                }
//                            }
//                            // 关键：给滚动视图加 Padding，否则聚焦时卡片会被切掉
//                            .padding(.horizontal, 50)
//                            .padding(.vertical, 40) // 预留卡片放大时的空间，防止被切
//                        }
//                    }
//                }
//            }
//        }
//        .ignoresSafeArea() // 让内容铺满屏幕边缘
    }
}

#Preview {
    HomeView(openAnimeDetail: { _ in })
}
