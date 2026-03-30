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

fileprivate struct SourcePanelResourceKey: Hashable {
    let sourceIndex: Int
    let resourceIndex: Int
}

@MainActor
final class SourceSwitchPanelModel: ObservableObject {
    @Published var sources: [VideoSource] = []
    @Published var focusedSourceIndex: Int = 0
    @Published var committedSourceIndex: Int?
    @Published var committedResourceIndex: Int?
    @Published var pendingSourceIndex: Int?
    @Published var pendingResourceIndex: Int?
    @Published var loadingSourceIndices: Set<Int> = []
    @Published fileprivate var failedResourceKeys: Set<SourcePanelResourceKey> = []

    var onSourceSelected: ((Int, Int, VideoResource) -> Void)?

    func update(sources: [VideoSource], onSourceSelected: ((Int, Int, VideoResource) -> Void)?) {
        self.sources = sources
        self.onSourceSelected = onSourceSelected

        if sources.isEmpty {
            focusedSourceIndex = 0
            committedSourceIndex = nil
            committedResourceIndex = nil
            pendingSourceIndex = nil
            pendingResourceIndex = nil
            return
        }

        focusedSourceIndex = min(focusedSourceIndex, sources.count - 1)
        committedSourceIndex = clampedSourceIndex(committedSourceIndex)
        pendingSourceIndex = clampedSourceIndex(pendingSourceIndex)
        committedResourceIndex = clampedResourceIndex(committedResourceIndex, in: committedSourceIndex)
        pendingResourceIndex = clampedResourceIndex(pendingResourceIndex, in: pendingSourceIndex)
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
        if let pendingSourceIndex {
            return index == pendingSourceIndex
        }
        return index == committedSourceIndex
    }

    func isPlayingResource(_ index: Int) -> Bool {
        guard pendingSourceIndex == nil else { return false }
        return index == committedResourceIndex && focusedSourceIndex == committedSourceIndex
    }

    func isPendingResource(_ index: Int) -> Bool {
        index == pendingResourceIndex && focusedSourceIndex == pendingSourceIndex
    }

    func isFailedResource(_ index: Int) -> Bool {
        failedResourceKeys.contains(
            SourcePanelResourceKey(
                sourceIndex: focusedSourceIndex,
                resourceIndex: index
            )
        )
    }

    func selectResource(at index: Int) {
        guard focusedResources.indices.contains(index) else { return }
        beginSelectionAttempt(sourceIndex: focusedSourceIndex, resourceIndex: index)
        onSourceSelected?(focusedSourceIndex, index, focusedResources[index])
    }

    func beginSelectionAttempt(sourceIndex: Int, resourceIndex: Int) {
        guard sources.indices.contains(sourceIndex),
              sources[sourceIndex].resources.indices.contains(resourceIndex) else { return }
        focusedSourceIndex = sourceIndex
        pendingSourceIndex = sourceIndex
        pendingResourceIndex = resourceIndex
        failedResourceKeys.remove(
            SourcePanelResourceKey(
                sourceIndex: sourceIndex,
                resourceIndex: resourceIndex
            )
        )
    }

    func confirmPendingSelection() {
        if let pendingSourceIndex, let pendingResourceIndex {
            failedResourceKeys.remove(
                SourcePanelResourceKey(
                    sourceIndex: pendingSourceIndex,
                    resourceIndex: pendingResourceIndex
                )
            )
        }
        committedSourceIndex = pendingSourceIndex
        committedResourceIndex = pendingResourceIndex
        pendingSourceIndex = nil
        pendingResourceIndex = nil
    }

    func markPendingSelectionFailed() {
        if let pendingSourceIndex, let pendingResourceIndex {
            failedResourceKeys.insert(
                SourcePanelResourceKey(
                    sourceIndex: pendingSourceIndex,
                    resourceIndex: pendingResourceIndex
                )
            )
        }
        clearPendingSelection()
    }

    func clearPendingSelection() {
        pendingSourceIndex = nil
        pendingResourceIndex = nil
    }

    var isFocusedSourceLoading: Bool {
        loadingSourceIndices.contains(focusedSourceIndex)
    }

    func setLoadingSources(_ indices: Set<Int>) {
        loadingSourceIndices = indices
    }

    func markSourceLoaded(_ index: Int) {
        loadingSourceIndices.remove(index)
    }

    private func clampedSourceIndex(_ index: Int?) -> Int? {
        guard let index, sources.indices.contains(index) else { return nil }
        return index
    }

    private func clampedResourceIndex(_ index: Int?, in sourceIndex: Int?) -> Int? {
        guard let sourceIndex,
              sources.indices.contains(sourceIndex),
              let index else { return nil }

        let resources = sources[sourceIndex].resources
        guard resources.indices.contains(index) else { return nil }
        return index
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
        //  .padding(.horizontal, 22)
        //  .padding(.bottom, 22)
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
         .onChange(of: model.sources.count) { _, _ in
             guard focusedTarget == nil else { return }
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
        guard let target = preferredInitialFocusTarget else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            switch target {
            case .source(let index):
                model.focusSource(at: index)
            case .resource(let index):
                if let sourceIndex = preferredSelectedSourceIndex {
                    model.focusSource(at: sourceIndex)
                }
                focusedTarget = nil
            }
            focusedTarget = target
        }
    }

    private var preferredInitialFocusTarget: SourcePanelFocusTarget? {
        if let sourceIndex = preferredSelectedSourceIndex,
           let resourceIndex = preferredSelectedResourceIndex {
            return .resource(resourceIndex)
        }

        if let sourceIndex = firstSourceWithResourcesIndex {
            return .source(sourceIndex)
        }

        guard !model.sources.isEmpty else { return nil }
        return .source(0)
    }

    private var preferredSelectedSourceIndex: Int? {
        if let pendingSourceIndex = model.pendingSourceIndex {
            return pendingSourceIndex
        }
        return model.committedSourceIndex
    }

    private var preferredSelectedResourceIndex: Int? {
        if let pendingResourceIndex = model.pendingResourceIndex {
            return pendingResourceIndex
        }
        return model.committedResourceIndex
    }

    private var firstSourceWithResourcesIndex: Int? {
        model.sources.firstIndex { !$0.resources.isEmpty }
    }

    private func resourceIndicator(for index: Int) -> SourcePanelButtonRow.Indicator {
        if model.isPendingResource(index) {
            return .loading
        }
        if model.isPlayingResource(index) {
            return .checkmark
        }
        if model.isFailedResource(index) {
            return .failure
        }
        return .none
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
                            indicator: model.isPlayingSource(index) ? .checkmark : .none,
                            isFocused: focusedTarget == .source(index),
                            isInitiallyFocused: preferredInitialFocusTarget == .source(index),
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

    @ViewBuilder
    private var resourceColumn: some View {
        if model.isFocusedSourceLoading {
            statusContent {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity)
            .padding(.leading, 28)
        } else if model.focusedResources.isEmpty {
            statusContent {
                Text("暂无线路")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity)
            .padding(.leading, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .center, spacing: 12) {
                        ForEach(Array(model.focusedResources.enumerated()), id: \.offset) { index, resource in
                                panelButton(
                                    title: resource.resourceName,
                                    indicator: resourceIndicator(for: index),
                                    isFocused: focusedTarget == .resource(index),
                                    isInitiallyFocused: preferredInitialFocusTarget == .resource(index),
                                    focusScope: sourcePanelFocusScope,
                                    focusTarget: SourcePanelFocusTarget.resource(index),
                                    focusedTarget: $focusedTarget
                            ) {
                                model.selectResource(at: index)
                            }
                            .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.focusedSourceIndex) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
                .onChange(of: model.committedResourceIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity)
            .padding(.leading, 28)
        }
    }

    private func panelButton(
        title: String,
        indicator: SourcePanelButtonRow.Indicator,
        isFocused: Bool,
        isInitiallyFocused: Bool,
        focusScope: Namespace.ID,
        focusTarget: SourcePanelFocusTarget,
        focusedTarget: FocusState<SourcePanelFocusTarget?>.Binding,
        action: @escaping () -> Void
    ) -> some View {
        SourcePanelButtonRow(
            title: title,
            indicator: indicator,
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

    private func statusContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SourcePanelButtonRow: View {
    enum Indicator {
        case none
        case checkmark
        case loading
        case failure
    }

    let title: String
    let indicator: Indicator
    let isFocused: Bool
    let isInitiallyFocused: Bool
    let focusScope: Namespace.ID
    let focusTarget: SourcePanelFocusTarget
    let focusedTarget: FocusState<SourcePanelFocusTarget?>.Binding
    let action: () -> Void

    var body: some View {
        let leadingIndicator = Group {
            switch indicator {
            case .none:
                Color.clear
            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.9)
            case .failure:
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.95))
            }
        }
        .frame(width: 24, height: 24, alignment: .center)

        let label = Text(title)
            .font(.system(size: 29, weight: .bold))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .frame(height: 52)

        return HStack(spacing: 10) {
            leadingIndicator

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
