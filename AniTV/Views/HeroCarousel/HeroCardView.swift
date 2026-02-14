//
//  HeroCardView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/12.
//

import SwiftUI
import Kingfisher

// MARK: - 单卡片视图
struct HeroCardView: View {
    let item: AnimeSubject
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) { // ⚠️ 显式对齐：左下角
            
                // 1. 背景图
                // TODO: backdrop 为nil
                KFImage(item.backdrop)
                    .resizable()
                    .placeholder {
                        Color.gray.opacity(0.3)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()
                    .clipped()
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.5),
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.9),
                        Color.black.opacity(1)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // 3. 文字内容区域
                VStack(alignment: .leading, spacing: 16) {
                    if(item.endDate == nil){
                        if let airDate = item.startDate{
                            NewArrivalPill(text: airDate.formatted(.dateTime.weekday(.wide)))
                        }
                    }
                    
                    // 标题 (处理长标题)
                    Text(item.displayName)
                        .font(.system(size: 64, weight: .heavy)) // tvOS 标题要大
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(radius: 4)
                        .fixedSize(horizontal: false, vertical: true) // 防止文字被压缩
                    // 信息行 (类型 · 评分)
                    HStack(spacing: 12) {
//                        Image(systemName: "tv")
                        Text(item.isMovie ? "劇場版":"新番組")
                        Text("·")
                        Text("评分 \(item.scoreString)")
                            .foregroundStyle(.yellow)
                        Text("·")
                        if item.displayOriginalTitle{
                            Text(item.title)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                    
                    // 简介
                    Text(item.info)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                    
                    // 按钮组
                    ActionButtonsView(anime: item)
                    
                }
                .padding(40) // 1. 重要：增加内边距，给渐变留出“淡出”的空间，否则文字边缘会被截断
                .background(
                    EllipticalGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.7), // 中间：最黑
                            Color.black.opacity(0.5), // 中途：半透明
                            Color.black.opacity(0.0)  // 边缘：完全透明
                        ]),
                        center: .center,
                        startRadiusFraction: 0.0, // 从中心开始
                        endRadiusFraction: 1.0    // 到边缘结束
                    )
                    .blur(radius: 50)
                )

                .padding(.horizontal, 80 - 30) // 4. 调整外边距 (减去上面加的内边距30，保持视觉位置不变)
                .padding(.bottom, 200)
                .frame(maxWidth: proxy.size.width * 0.6, alignment: .leading)
            }
        }.ignoresSafeArea()
    }
}

struct ActionButtonsView: View {
    let buttonHeight: CGFloat = 80 // 定义统一的高度
    @FocusState var isPlayFocused: Bool // 监听聚焦
    var anime: AnimeSubject
    
    var body: some View {
        HStack(spacing: 20) {
            UnifiedActionButton(title: "立即播放", systemImage: "play.fill")

            
            CircleActionButton(systemImage: "plus")
            
            CircleNavigationButton(systemImage: "info.circle", value: anime)
        }
        .padding()
    }
}

struct UnifiedActionButton: View {
    @FocusState private var isFocused: Bool
    let title: String
    let systemImage: String
    let height: CGFloat = 80

    var body: some View {
        Button(action: { print("Action") }) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.headline)
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .padding(.horizontal, 40)
            .frame(height: height)
            // 手动控制聚焦时的背景色
            .background(isFocused ? Color.white : Color.white.opacity(0.1))
            .foregroundColor(isFocused ? .black : .white)
            .cornerRadius(50)
        }
        .buttonStyle(CleanButtonStyle())   // 🎯 使用自定义样式
        .focused($isFocused)              // 仍需监听聚焦以手动改变颜色
        // ❌ 不再需要 .focusEffectDisabled，因为 CleanButtonStyle 已包含
    }
}
struct CleanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 完全禁用系统焦点效果（缩放、阴影、高光背景）
            .focusEffectDisabled(true)
            // 可选：保留按压动画（按需）
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// 圆形按钮组件
struct CircleActionButton: View {
    @FocusState private var isFocused: Bool
    let systemImage: String
    let size: CGFloat = 80 // 必须与上面高度一致

    var body: some View {
        Button(action: { print("Action") }) {
            Image(systemName: systemImage)
                .scaleEffect(isFocused ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .frame(width: size, height: size) // 强制等宽高
                .background(
                    isFocused ? Color.white : Color.white.opacity(0.1)
                )
                .foregroundColor(isFocused ? .black : .white)
                .clipShape(Circle())
        }
        .buttonStyle(CleanButtonStyle()) // 核心：干掉系统缩放
        .focused($isFocused)
    }
}
struct CircleNavigationButton<T: Hashable>: View {
    @FocusState private var isFocused: Bool
    
    let systemImage: String
    let value: T          // 1. 新增：要传递的数据（例如 AnimeSubject）
    let size: CGFloat = 80
    
    var body: some View {
        // 2. 将 Button 替换为 NavigationLink
        NavigationLink(value: value) {
            Image(systemName: systemImage)
                .scaleEffect(isFocused ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .frame(width: size, height: size)
                .background(
                    isFocused ? Color.white : Color.white.opacity(0.1)
                )
                .foregroundColor(isFocused ? .black : .white)
                .clipShape(Circle())
        }
        // 3. 关键：NavigationLink 也接受 buttonStyle，这能去掉系统自带的卡片背景
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

struct NewArrivalPill: View {
    let text: String
    var body: some View {
        Text("New Episode Every \(text)")
            .font(.caption.bold())
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

#Preview {
    HeroCardView( item: AnimeSubject.mock)
}

extension AnimeSubject {
    static var mock: AnimeSubject {
        let json = """
{
      "id": 510753,
      "title": "勇者刑に処す 懲罰勇者9004隊刑務記録",
      "info": "11话 / 2026年1月7日 / 上野壮大 / 鵜飼有志（MF文庫J「死亡遊戯で飯を食う。」／KADOKAWA 刊） / 長田絵里",
      "score": 6.4,
      "titleTranslate": {
        "en": "SHIBOYUGI: Playing Death Games to Put Food on the Table",
        "zh-Hans": "勇者处刑 惩罚勇者9004队服刑记录",
        "zh-Hant": "靠死亡遊戲混飯吃。"
      },
      "type": "tv",
      "lang": "ja",
      "begin": "2026-01-07T14:00:00.000Z",
      "broadcast": "R/2026-01-07T14:00:00.000Z/P7D",
      "end": "",
      "backdrop": "https://image.tmdb.org/t/p/original/rcwfBh8gPBL4sKUEPqu0lEKreha.jpg"
    }
""".data(using: .utf8)!
        
        return try! JSONDecoder().decode(AnimeSubject.self, from: json)
    }
}
