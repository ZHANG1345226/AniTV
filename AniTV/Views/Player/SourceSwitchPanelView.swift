//
//  SourceSwitchPanelView.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/28.
//

import SwiftUI
import Combine

private let sourcePanelHeight: CGFloat = 324

fileprivate enum SourcePanelFocusTarget: Hashable {
    case source(Int)
    case resource(Int)
}

@MainActor
final class SourceSwitchPanelModel: ObservableObject {
    @Published var sources: [VideoSource] = []
    @Published var focusedSourceIndex: Int = 0
    @Published var playingSourceIndex: Int = 0
    @Published var playingResourceIndex: Int = 0

    var onSourceSelected: ((VideoResource) -> Void)?

    func update(sources: [VideoSource], onSourceSelected: ((VideoResource) -> Void)?) {
        self.sources = sources
        self.onSourceSelected = onSourceSelected

        if sources.isEmpty {
            focusedSourceIndex = 0
            playingSourceIndex = 0
            playingResourceIndex = 0
            return
        }

        focusedSourceIndex = min(focusedSourceIndex, sources.count - 1)
        playingSourceIndex = min(playingSourceIndex, sources.count - 1)
        let resources = sources[playingSourceIndex].resources
        if resources.isEmpty {
            playingResourceIndex = 0
        } else {
            playingResourceIndex = min(playingResourceIndex, resources.count - 1)
        }
    }

    var focusedResources: [VideoResource] {
        guard sources.indices.contains(focusedSourceIndex) else { return [] }
        return sources[focusedSourceIndex].resources
    }

    func focusSource(at index: Int) {
        guard sources.indices.contains(index) else { return }
        focusedSourceIndex = index
    }

    func isPlayingSource(_ index: Int) -> Bool {
        index == playingSourceIndex
    }

    func isPlayingResource(_ index: Int) -> Bool {
        index == playingResourceIndex && focusedSourceIndex == playingSourceIndex
    }

    func selectResource(at index: Int) {
        guard focusedResources.indices.contains(index) else { return }
        playingSourceIndex = focusedSourceIndex
        playingResourceIndex = index
        onSourceSelected?(focusedResources[index])
    }
}

struct SourceSwitchPanelView: View {
    @ObservedObject var model: SourceSwitchPanelModel
    @Namespace private var sourcePanelFocusScope
    @FocusState private var focusedTarget: SourcePanelFocusTarget?
    @FocusState private var isFocusEntryActive: Bool
    private let panelShape = RoundedRectangle(cornerRadius: 60, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            sourceColumn
            Divider()
                .frame(width: 1, height: 162)
                .background(Color.white.opacity(0.24))
                .padding(.vertical, 22)
            resourceColumn
        }
         .padding(.horizontal, 38)
         .padding(.vertical, 26)
         .frame(maxWidth: .infinity)
         .frame(height: sourcePanelHeight)
         .padding(.horizontal, 22)
         .padding(.bottom, 22)
         .background {
             RoundedRectangle(cornerRadius: 50, style: .continuous)
                 .fill(.ultraThinMaterial)
                 .tint(Color.black.opacity(0.20))
                //  .opacity(0.95)
                 .overlay {
                     RoundedRectangle(cornerRadius: 50, style: .continuous)
                         .stroke(Color.white.opacity(0.3), lineWidth: 1)
                 }
                 .padding(.horizontal, 0)
                 .padding(.vertical, 0)
                 .blur(radius: 30)
         }
         .glassEffect(.clear.tint(Color.black.opacity(0.20)), in: panelShape)
         .environment(\.colorScheme, .light)
         .focusScope(sourcePanelFocusScope)
         .focusSection()
         .overlay(alignment: .topLeading) {
             focusEntry
         }
         .onAppear {
             restoreInitialFocus()
         }
         .onChange(of: isFocusEntryActive) { _, isActive in
             guard isActive else { return }
             restoreInitialFocus()
             DispatchQueue.main.async {
                 isFocusEntryActive = false
             }
         }
         .onChange(of: focusedTarget) { _, newValue in
             guard let newValue else { return }
             switch newValue {
             case .source(let index):
                 model.focusSource(at: index)
             case .resource:
                 break
             }
         }
    }

    private func restoreInitialFocus() {
        guard model.sources.indices.contains(model.focusedSourceIndex) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedTarget = .source(model.focusedSourceIndex)
        }
    }

    private var focusEntry: some View {
        Button(action: {}) {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocusEntryActive)
        .prefersDefaultFocus(true, in: sourcePanelFocusScope)
        .opacity(0.001)
        .allowsHitTesting(false)
    }

    private var sourceColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 12) {
                    ForEach(Array(model.sources.enumerated()), id: \.offset) { index, source in
                        panelButton(
                            title: source.sourceName,
                            isPlaying: model.isPlayingSource(index),
                            isFocused: focusedTarget == .source(index),
                            isInitiallyFocused: index == model.focusedSourceIndex,
                            focusScope: sourcePanelFocusScope,
                            focusTarget: SourcePanelFocusTarget.source(index),
                            focusedTarget: $focusedTarget,
                        ) {
                            model.focusSource(at: index)
                        }
                        .id(index)
                    }

                    if model.sources.isEmpty {
                        placeholder(title: "暂无来源")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.focusedSourceIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity)
        .padding(.trailing, 28)
    }

    private var resourceColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 12) {
                    ForEach(Array(model.focusedResources.enumerated()), id: \.offset) { index, resource in
                        panelButton(
                            title: resource.resourceName,
                            isPlaying: model.isPlayingResource(index),
                            isFocused: focusedTarget == .resource(index),
                            isInitiallyFocused: false,
                            focusScope: sourcePanelFocusScope,
                            focusTarget: SourcePanelFocusTarget.resource(index),
                            focusedTarget: $focusedTarget
                        ) {
                            model.selectResource(at: index)
                        }
                        .id(index)
                    }

                    if model.focusedResources.isEmpty {
                        placeholder(title: "暂无线路")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.focusedSourceIndex) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
            .onChange(of: model.playingResourceIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity)
        .padding(.leading, 28)
    }

    private func panelButton(
        title: String,
        isPlaying: Bool,
        isFocused: Bool,
        isInitiallyFocused: Bool,
        focusScope: Namespace.ID,
        focusTarget: SourcePanelFocusTarget,
        focusedTarget: FocusState<SourcePanelFocusTarget?>.Binding,
        action: @escaping () -> Void
    ) -> some View {
        SourcePanelButtonRow(
            title: title,
            isPlaying: isPlaying,
            isFocused: isFocused,
            isInitiallyFocused: isInitiallyFocused,
            focusScope: focusScope,
            focusTarget: focusTarget,
            focusedTarget: focusedTarget,
            action: action
        )
    }

    private func placeholder(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(height: 52)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }
}

private struct SourcePanelButtonRow: View {
    let title: String
    let isPlaying: Bool
    let isFocused: Bool
    let isInitiallyFocused: Bool
    let focusScope: Namespace.ID
    let focusTarget: SourcePanelFocusTarget
    let focusedTarget: FocusState<SourcePanelFocusTarget?>.Binding
    let action: () -> Void

    var body: some View {
        let checkmark = Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .opacity(isPlaying ? 1 : 0)
            .frame(width: 24, alignment: .center)

        let label = Text(title)
            .font(.system(size: 29, weight: .bold))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .frame(height: 52)

        return HStack(spacing: 10) {
            checkmark

            Button(action: action) {
                label
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.92) : Color.clear)
            )
            .buttonStyle(CleanButtonStyle())
            .prefersDefaultFocus(isInitiallyFocused, in: focusScope)
            .focused(focusedTarget, equals: focusTarget)
            .frame(width: 266)
        }
        .frame(width: 300)
    }
}

//#Preview {
//    SourceSwitchPanelView(model: SourceSwitchPanelModel())
//}
