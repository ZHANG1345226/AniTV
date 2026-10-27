//
//  HeroCardView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/12.
//

import SwiftUI
import Kingfisher

enum HeroActionButtonFocus: Hashable {
    case previousTrigger
    case play
    case favorite
    case info
}

struct HeroCardView: View {
    let item: AnimeSubject

    private var isTMDB: Bool {
        item.backdrop?.host?.contains("tmdb.org") == true
    }

    var body: some View {
        ZStack {
            KFImage(item.backdrop)
                .setProcessor(isTMDB ? DefaultImageProcessor.default : BGMBackdropCropProcessor.default)
                .resizable()
                .placeholder {
                    Color.gray.opacity(0.3)
                }
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .clipped()
        }
        .ignoresSafeArea()
    }
}

struct ActionButtonsView: View {
    @FocusState private var focusedButton: HeroActionButtonFocus?
    @State private var lastFocusedButton: HeroActionButtonFocus?
    var anime: AnimeSubject
    var playTitle: String = "立即播放"
    var onPlay: () -> Void = {}
    var isWatching: Bool = false
    var onToggleWatching: () -> Void = {}
    let openAnimeDetail: (Int) -> Void
    let onMoveToPrevious: () -> Void
    let onMoveToNext: () -> Void
    var defaultFocusScope: Namespace.ID?
    var preferredFocusTarget: HeroActionButtonFocus = .play
    var onActionFocused: (HeroActionButtonFocus) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }
    var prefersDefaultFocus = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 20) {
                UnifiedActionButton(
                    title: playTitle,
                    systemImage: "play.fill",
                    action: onPlay,
                    focusedButton: $focusedButton,
                    focusTarget: .play,
                    defaultFocusScope: defaultFocusScope,
                    prefersDefaultFocus: prefersDefaultFocus && preferredFocusTarget == .play
                )

                CircleActionButton(
                    systemImage: isWatching ? "checkmark" : "plus",
                    action: onToggleWatching,
                    focusedButton: $focusedButton,
                    focusTarget: .favorite,
                    defaultFocusScope: defaultFocusScope,
                    prefersDefaultFocus: prefersDefaultFocus && preferredFocusTarget == .favorite
                )
                
                CircleNavigationButton(
                    systemImage: "info.circle",
                    onActivate: {
                        openAnimeDetail(anime.id)
                    },
                    focusedButton: $focusedButton,
                    focusTarget: .info,
                    defaultFocusScope: defaultFocusScope,
                    prefersDefaultFocus: prefersDefaultFocus && preferredFocusTarget == .info,
                    onMoveRight: {
                        onMoveToNext()
                        DispatchQueue.main.async {
                            focusedButton = .info
                        }
                    }
                )
            }

            InvisibleFocusTriggerButton(
                focusedButton: $focusedButton,
                focusTarget: .previousTrigger
            )
            .offset(x: -88)
        }
        .padding()
        .focusSection()
        .onAppear {
            restoreDefaultFocusIfNeeded()
            onFocusChange(focusedButton != nil)
        }
        .onChange(of: prefersDefaultFocus) { _, shouldPrefer in
            guard shouldPrefer else { return }
            restoreDefaultFocusIfNeeded()
        }
        .onChange(of: focusedButton) { oldValue, newValue in
            onFocusChange(newValue != nil)
            guard let newValue else {
                lastFocusedButton = nil
                return
            }

            if newValue == .previousTrigger {
                if oldValue == .play || lastFocusedButton == .play {
                    onMoveToPrevious()
                }
                lastFocusedButton = .play
                DispatchQueue.main.async {
                    focusedButton = .play
                }
            } else {
                lastFocusedButton = newValue
                onActionFocused(newValue)
            }
        }
    }

    private func restoreDefaultFocusIfNeeded() {
        guard prefersDefaultFocus else { return }
        DispatchQueue.main.async {
            focusedButton = preferredFocusTarget
        }
    }
}

struct InvisibleFocusTriggerButton: View {
    fileprivate let focusedButton: FocusState<HeroActionButtonFocus?>.Binding
    fileprivate let focusTarget: HeroActionButtonFocus
    
    private var isFocused: Bool {
        focusedButton.wrappedValue == focusTarget
    }

    var body: some View {
        Button(action: {}) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.clear)
                .overlay {
                    Text("Prev")
                        .font(.caption.bold())
                        .foregroundStyle(Color.clear)
                }
                .frame(width: 44, height: 80)
        }
        .buttonStyle(CleanButtonStyle())
        .focused(focusedButton, equals: focusTarget)
        .focusEffectDisabled(true)
    }
}

struct UnifiedActionButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void = {}
    let height: CGFloat = 80
    fileprivate let focusedButton: FocusState<HeroActionButtonFocus?>.Binding
    fileprivate let focusTarget: HeroActionButtonFocus
    var defaultFocusScope: Namespace.ID?
    var prefersDefaultFocus = false

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .frame(width: 76)
                    .padding(.leading, 8)

                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.leading, 8)
                    .padding(.trailing, 28)
            }
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .frame(width: 300, height: height)
            // 手动控制聚焦时的背景色
            .background(isFocused ? Color.white : Color.white.opacity(0.1))
            .foregroundColor(isFocused ? .black : .white)
            .cornerRadius(50)
        }
        .buttonStyle(CleanButtonStyle())   // 🎯 使用自定义样式
        .focused(focusedButton, equals: focusTarget)

        if let defaultFocusScope {
            button.prefersDefaultFocus(prefersDefaultFocus, in: defaultFocusScope)
        } else {
            button
        }
    }
    
    private var isFocused: Bool {
        focusedButton.wrappedValue == focusTarget
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
    let systemImage: String
    var action: () -> Void = {}
    let size: CGFloat = 80 // 必须与上面高度一致
    fileprivate let focusedButton: FocusState<HeroActionButtonFocus?>.Binding
    fileprivate let focusTarget: HeroActionButtonFocus
    var defaultFocusScope: Namespace.ID?
    var prefersDefaultFocus = false

    var body: some View {
        let button = Button(action: action) {
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
        .focused(focusedButton, equals: focusTarget)

        if let defaultFocusScope {
            button.prefersDefaultFocus(prefersDefaultFocus, in: defaultFocusScope)
        } else {
            button
        }
    }
    
    private var isFocused: Bool {
        focusedButton.wrappedValue == focusTarget
    }
}
struct CircleNavigationButton: View {
    let systemImage: String
    let onActivate: () -> Void
    let size: CGFloat = 80
    fileprivate let focusedButton: FocusState<HeroActionButtonFocus?>.Binding
    fileprivate let focusTarget: HeroActionButtonFocus
    var defaultFocusScope: Namespace.ID?
    var prefersDefaultFocus = false
    var onMoveRight: (() -> Void)? = nil
    
    var body: some View {
        let button = Button(action: onActivate) {
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
        .buttonStyle(CleanButtonStyle())
        .focused(focusedButton, equals: focusTarget)
        .onMoveCommand { direction in
            if direction == .right {
                onMoveRight?()
            }
        }

        if let defaultFocusScope {
            button.prefersDefaultFocus(prefersDefaultFocus, in: defaultFocusScope)
        } else {
            button
        }
    }
    
    private var isFocused: Bool {
        focusedButton.wrappedValue == focusTarget
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
    HeroCardView(item: AnimeSubject.mock)
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
