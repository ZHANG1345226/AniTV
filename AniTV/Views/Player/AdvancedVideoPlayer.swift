//
//  AdvancedVideoPlayer.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/16.
//


import SwiftUI
import AVKit

struct AdvancedVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let title: String
    let sort: Int
    @Binding var showInfoPanel: Bool
    
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

        // 🌟 魔法在这里：把按钮注入到原生的 Metadata 面板中
        controller.infoViewActions = [startOverAction, favoriteAction]
        
        // 1. 创建“跳过片头”按钮的 UIAction
        // title: 按钮标题，image: 使用 SF Symbols 图标
        let skipIntroAction = UIAction(
            title: "跳过 OP",
            image: UIImage(systemName: "forward.end.fill")
        ) { _ in
            // 💡 点击后的逻辑：让播放器快进 90 秒 (标准日漫 OP 长度)
            guard let currentPlayer = controller.player else { return }
            let currentTime = currentPlayer.currentTime()
            let skipTime = CMTimeMake(value: 90, timescale: 1)
            currentPlayer.seek(to: CMTimeAdd(currentTime, skipTime))
        }
        
        // 2. 创建“Sources”菜单（支持二级菜单）
        let sourceAAction = UIAction(
            title: "线路 A",
            image: UIImage(systemName: "a.circle")
        ) { _ in
            print("切换到线路 A")
        }
        
        let sourceBAction = UIAction(
            title: "线路 B",
            image: UIImage(systemName: "b.circle")
        ) { _ in
            print("切换到线路 B")
        }
        
        let backupSourceMenu = UIMenu(
            title: "备用线路",
            image: UIImage(systemName: "ellipsis.circle"),
            children: [
                UIAction(title: "备用 1", image: UIImage(systemName: "1.circle")) { _ in
                    print("切换到备用 1")
                },
                UIAction(title: "备用 2", image: UIImage(systemName: "2.circle")) { _ in
                    print("切换到备用 2")
                }
            ]
        )
        
        let sourcesMenu = UIMenu(
            title: "Sources",
            image: UIImage(systemName: "play.square.stack"),
            children: [sourceAAction, sourceBAction, backupSourceMenu]
        )
        
        // 3. 创建 PiP 按钮
        let pipAction = UIAction(
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
        
        // 3. 将这两个 Action 组装成菜单项数组，
        // 🌟 然后塞进底部的 Transport Bar！
        controller.transportBarCustomMenuItems = [skipIntroAction, sourcesMenu, pipAction]
        
        if #available(tvOS 14.0, *) {
            controller.loadViewIfNeeded()
            if let playerLayer = findPlayerLayer(in: controller.view.layer) {
                context.coordinator.pipController = AVPictureInPictureController(playerLayer: playerLayer)
            }
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 当控制面板弹出时，隐藏播放器的默认控制条，避免抢夺焦点和遮挡
        uiViewController.showsPlaybackControls = !showInfoPanel

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
