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
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        // 🌟 魔法在这里！把刚才写的 SwiftUI 视图包装成 UIViewController
        let customUI = AniTVCustomDropdownView(title: title, sort: sort)
        let hostingController = UIHostingController(rootView: customUI)
        
        // 背景设为透明，这样下拉时还能隐约看到后面的视频
        hostingController.view.backgroundColor = .clear
        hostingController.title = "Next Up"
        
        // 🌟 告诉系统：下滑时，展示我的面板！
        #if os(tvOS)
        if #available(tvOS 15.0, *) {
            controller.customInfoViewControllers = [hostingController]
        } else {
            controller.customInfoViewController = hostingController
        }
        #endif
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 当控制面板弹出时，隐藏播放器的默认控制条，避免抢夺焦点和遮挡
        uiViewController.showsPlaybackControls = !showInfoPanel

    }
}
