//
//  AniTVCustomDropdownView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/16.
//


import SwiftUI

// 这是你自定义的下拉面板，想怎么画就怎么画
struct AniTVCustomDropdownView: View {
    let title: String
    let sort: Int
    var onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 60, weight: .bold))
            
            Text("当前播放：第 \(sort) 集")
                .font(.title2)
                .foregroundColor(.gray)
            
            // 你甚至可以在这里放一个横向滚动的选集列表
            ScrollView(.horizontal) {
                HStack {
                    ForEach(1...12, id: \.self) { episode in
                        Button(action: {
                            print("切换到第 \(episode) 集")
                            onClose() // 切换选集后关闭面板
                        }) {
                            Text("第 \(episode) 集")
                                .frame(width: 150, height: 80)
                        }
                    }
                }
            }
//            
//            Spacer()
        }
        .padding(60)
        .background(
            // 为了让焦点能够正常捕获并响应遥控器的“Menu”返回键来关闭面板
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.top)
        )
        // 支持遥控器 Menu 键返回
        .onExitCommand {
            onClose()
        }
    }
}
