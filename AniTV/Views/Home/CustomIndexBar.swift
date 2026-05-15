//
//  CustomIndexBar.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/12.
//
import SwiftUI

// MARK: - 指示器组件
struct CustomIndexBar: View {
    let numberOfPages: Int
    let currentPage: Int
    // ⚠️ 必须与 HeroCarouselView 里的 Timer 时间保持一致 (例如 5.0 秒)
    let duration: TimeInterval
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                let isSelected = index == currentPage
                
                if isSelected {
                    // 选中的：显示倒计时胶囊
                    TimerCapsule(duration: duration)
                        .frame(width: 32, height: 8)
                } else {
                    // 未选中的：显示普通小圆点
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .opacity(0.4)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
        }
        .padding(12)
        .background(Material.thin) // 毛玻璃背景
        .clipShape(Capsule())
        // 给整个容器加个动画，让 圆点 <-> 胶囊 的形状变化平滑过渡
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
    }
}

// MARK: - 倒计时胶囊组件
struct TimerCapsule: View {
    let duration: TimeInterval
    
    // 控制进度的状态
    @State private var width: CGFloat = 0
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // 1. 底轨 (Track)
                Capsule()
                    .fill(Color.white.opacity(0.3))
                
                // 2. 进度条 (Progress)
                Capsule()
                    .fill(Color.white)
                    .frame(width: width) // 宽度由 State 控制
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .onAppear {
                // 当视图出现时 (即切换到了这个 index)，立即开始动画
                // 初始状态是 0
                width = 0
                // 线性动画，时长等于自动轮播的间隔
                withAnimation(.linear(duration: duration)) {
                    width = proxy.size.width // 填满宽度
                }
            }
        }
    }
}
