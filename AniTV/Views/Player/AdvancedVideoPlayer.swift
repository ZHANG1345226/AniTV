//
//  AdvancedVideoPlayer.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/16.
//


import SwiftUI
import AVKit

struct VideoSource{
    let sourceName: String
    let resources: [VideoResource]
}

struct VideoResource{
    let resourceName: String
    let url: String
//    let headers: [String: String]
    let matchConfig: SelectorSearchConfig.MatchVideoConfig
}

struct AdvancedVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let title: String
    let sort: Int
    var availableSources: [VideoSource]
    
    // 选中的线路回调（如果需要通知外部去切换 m3u8）
    var onSourceSelected: ((VideoResource) -> Void)?
    
    final class Coordinator: NSObject {
        var pipController: AVPictureInPictureController?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        // 🌟 魔法在这里！把刚才写的 SwiftUI 视图包装成 UIViewController
        let customUI = AniTVCustomDropdownView(title: title, sort: sort)
        let hostingController = UIHostingController(rootView: customUI)
        
        // 背景设为透明，这样下拉时还能隐约看到后面的视频
        hostingController.view.backgroundColor = .clear
        hostingController.title = String(localized: .nextUp)
        
        // 🌟 告诉系统：下滑时，展示我的面板！
        controller.customInfoViewControllers = [hostingController]
        
        let startOverAction = UIAction(
                title: "从头开始", // 或者 "从头播放"
                image: UIImage(systemName: "arrow.counterclockwise") // 苹果原生常用的重播图标
            ) { _ in
                // 核心逻辑：将播放器的进度拨回起点，并确保继续播放
                controller.player?.seek(to: .zero)
                controller.player?.play()
            }
        
        let favoriteAction = UIAction(
            title: "加入追番",
            image: UIImage(systemName: "heart.fill")
        ) { _ in
            print("触发了追番逻辑！")
        }
        
        controller.loadViewIfNeeded()
        if let playerLayer = findPlayerLayer(in: controller.view.layer) {
            context.coordinator.pipController = AVPictureInPictureController(playerLayer: playerLayer)
        }
        
        controller.infoViewActions = [startOverAction, favoriteAction]
        controller.transportBarCustomMenuItems = makeTransportBarItems(context: context)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 1. 根据当前抓取到的线路，动态生成 UIAction 数组
        uiViewController.transportBarCustomMenuItems = makeTransportBarItems(context: context)
    }

    private func makeTransportBarItems(context: Context) -> [UIMenuElement] {
        var items: [UIMenuElement] = [getPipAction(context: context)]
        if let sourceMenu = getSourceMenu() {
            items.insert(sourceMenu, at: 0)
        }
        print("transportBar items: \(items.count), sources: \(availableSources.count)")
        return items
    }
    
    private func getPipAction(context: Context) -> UIAction{
        return UIAction(
            title: "画中画",
            image: UIImage(systemName: "pip")
        ) { _ in
            guard let pipController = context.coordinator.pipController else {
                print("PiP 不可用")
                return
            }
            if pipController.isPictureInPictureActive {
                pipController.stopPictureInPicture()
            } else if pipController.isPictureInPicturePossible {
                pipController.startPictureInPicture()
            } else {
                print("PiP 暂不可用")
            }
        }
    }
    
    private func getSourceMenu() -> UIMenu? {
        var sourceActions: [UIMenuElement] = []
        var sourceManualActions: [UIMenuElement] = []

        for source in availableSources {
            let children = source.resources.map { resource in
                UIAction(title: resource.resourceName) { _ in
                    print("切换线路: \(resource.resourceName)")
                    onSourceSelected?(resource)
                }
            }

            if children.isEmpty {
                continue
            }

            sourceManualActions.append(
                UIMenu(
                    title: source.sourceName,
                    children: children
                )
            )
        }
        
        sourceActions.append(UIMenu(options:.displayInline, children: sourceManualActions))
        

        sourceActions.append(UIAction(title: "自动") { _ in
                print("切换线路: null")
            })
        return UIMenu(
            title: "Sources",
            image: UIImage(systemName: "play.square.stack"),
            children: sourceActions
        )
    }
    
    private func findPlayerLayer(in layer: CALayer) -> AVPlayerLayer? {
        if let playerLayer = layer as? AVPlayerLayer {
            return playerLayer
        }
        guard let sublayers = layer.sublayers else { return nil }
        for sublayer in sublayers {
            if let match = findPlayerLayer(in: sublayer) {
                return match
            }
        }
        return nil
    }
}
