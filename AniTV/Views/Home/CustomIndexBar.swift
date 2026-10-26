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
    var isActive: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                let isSelected = index == currentPage
                
                if isSelected {
                    // 选中的：显示倒计时胶囊
                    TimerCapsule(duration: duration, isActive: isActive)
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
    var isActive: Bool = true
    
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
                startAnimation(totalWidth: proxy.size.width)
            }
            .onChange(of: isActive) { _, active in
                if active {
                    startAnimation(totalWidth: proxy.size.width)
                } else {
                    width = 0
                }
            }
        }
    }

    private func startAnimation(totalWidth: CGFloat) {
        width = 0
        guard isActive else { return }
        withAnimation(.linear(duration: duration)) {
            width = totalWidth
        }
    }
}
