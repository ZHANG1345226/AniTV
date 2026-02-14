//
//  PosterCard.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import SwiftUI

struct PosterCard: View {
  let title: String
  let imageURL: URL?

  var body: some View {
    Button(action: {
      print("点击了 \(title)")
    }) {
      // 这里放你的图片
      AsyncImage(url: imageURL) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        // 加载中的占位图
        Color.gray
      }
    }
    .buttonStyle(.card)  // <--- 这行代码是灵魂！自动实现放大、发光、视差效果
    // 调整卡片大小（tvOS海报标准比例通常是 2:3 或 16:9）
    .frame(width: 200, height: 300)
    // 标题通常放在卡片下方，而不是里面
    .overlay(
      Text(title)
        .font(.caption)
        .padding(.top, 10)
        .opacity(0)  // 默认隐藏，聚焦时显示（这需要更高级的FocusState，初学可先忽略）
      , alignment: .bottom
    )
  }
}
