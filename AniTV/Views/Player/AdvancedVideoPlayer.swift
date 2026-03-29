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
        let sourcePanelModel = SourceSwitchPanelModel()
        var detailsHostingController: UIHostingController<AniTVCustomDropdownView>?
        var sourceHostingController: UIHostingController<SourceSwitchPanelView>?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        let detailsHostingController = UIHostingController(rootView: AniTVCustomDropdownView(title: title, sort: sort))
        detailsHostingController.view.backgroundColor = .clear
        detailsHostingController.title = String(localized: .nextUp)
        context.coordinator.detailsHostingController = detailsHostingController

        context.coordinator.sourcePanelModel.update(sources: availableSources, onSourceSelected: onSourceSelected)
        let sourceHostingController = UIHostingController(rootView: SourceSwitchPanelView(model: context.coordinator.sourcePanelModel))
//        sourceHostingController.view.backgroundColor = .clear
        sourceHostingController.title = "Sources"
//        sourceHostingController.preferredContentSize = CGSize(width: 1760, height: 324)
        context.coordinator.sourceHostingController = sourceHostingController
        
        controller.customInfoViewControllers = [sourceHostingController, detailsHostingController]
        
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
        controller.transportBarCustomMenuItems = [getPipAction(context: context)]
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        context.coordinator.detailsHostingController?.rootView = AniTVCustomDropdownView(title: title, sort: sort)
        context.coordinator.sourcePanelModel.update(sources: availableSources, onSourceSelected: onSourceSelected)
        uiViewController.transportBarCustomMenuItems = [getPipAction(context: context)]
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
