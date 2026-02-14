//
//  HeroCarouselView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import SwiftUI
import Combine
import Kingfisher

struct HeroCarouselView: View {
    @State private var items: [AnimeSubject] = []
    @State private var selection = 0
    @State private var isLoading = true
    @State private var exceptionMessage = ""
    
    // 焦点
    @FocusState private var focusedIndex: Int?
    
    // 自动滚动
    private let autoScrollDuration: TimeInterval = 10.0
    @State private var timer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    @State private var isAutoScrolling = false
    
    // 🔁 状态同步防循环标志
    @State private var isUpdatingSelection = false
    @State private var isUpdatingFocus = false
    
    private let repository = PrivateRepository()
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else if !exceptionMessage.isEmpty {
                Text(exceptionMessage)
            } else if items.isEmpty {
                Text("暂无推荐内容")
            } else {
                TabView(selection: $selection) {
                    ForEach(0..<items.count, id: \.self) { index in
                        HeroCardView(item: items[index])
                            .tag(index)
                            .ignoresSafeArea()
                            .focused($focusedIndex, equals: index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // 指示器
                VStack {
                    Spacer()
                    CustomIndexBar(
                        numberOfPages: items.count,
                        currentPage: selection,
                        duration: autoScrollDuration
                    )
                    .padding(.bottom, 40)
                }
            }
        }
        .task { await load() }
        
        // 🎯 自动滚动
        .onReceive(timer) { _ in
            guard !items.isEmpty, !isLoading else { return }
            let nextIndex = (selection + 1) % items.count
            isAutoScrolling = true
            withAnimation {
                selection = nextIndex      // ⚠️ 会触发 onChange(of: selection)
            }completion: {
                focusedIndex = nextIndex
            }
        }
        
        // 🔗 双向同步：selection → focusedIndex
        .onChange(of: selection) { oldValue, newValue in
            // 防循环：避免因 focusedIndex 变化再次进入
            guard !isUpdatingFocus else { return }

            
            // 定时器重置：仅手动切换时重置
            if !isAutoScrolling {
                isUpdatingSelection = true
                focusedIndex = newValue
                isUpdatingSelection = false
                resetTimer()
            } else {
                // 自动切换完成后清除标记
                isAutoScrolling = false
            }
        }
        
        // 🔗 双向同步：focusedIndex → selection
        .onChange(of: focusedIndex) { oldValue, newValue in
            guard let newIndex = newValue,
                  !isUpdatingSelection else { return }
            isUpdatingFocus = true
            selection = newIndex
            isUpdatingFocus = false
        }
        
        // 🎬 首次加载完成：设置初始焦点
        .onChange(of: isLoading) { _, loading in
            if !loading && !items.isEmpty {
                focusedIndex = 0
            }
        }
    }
    
    private func resetTimer() {
        timer.upstream.connect().cancel()
        timer = Timer.publish(every: autoScrollDuration, on: .main, in: .common).autoconnect()
    }

    func load() async {
        do {
            let response = try await repository.fetchTrendingSubjects()
            await MainActor.run {
                withAnimation {
                    self.items = response.data
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.exceptionMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
#Preview {
    HeroCarouselView()
        .zIndex(0)
}
