//
//  DanmuViewManager.swift
//  AniTV
//
//  Created by Codex on 2026/7/26.
//

import Foundation
import Combine
import AVKit

class DanmuViewManager {
    let danmuView = DanmakuView()
    private var provider: DanmuProviderProtocol
    private var cancellables = Set<AnyCancellable>()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private weak var player: AVPlayer?
    
    var isEnabled: Bool = true {
        didSet {
            danmuView.isHidden = !isEnabled
            if !isEnabled {
                danmuView.clean()
            }
        }
    }
    
    var displayArea: CGFloat {
        get {
            return danmuView.displayArea
        }
        set {
            danmuView.displayArea = newValue
            danmuView.recaculateTracks()
        }
    }
    
    init(provider: DanmuProviderProtocol) {
        self.provider = provider
        
        provider.onSendTextModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] model in
                print("[DanmuViewManager] Received danmaku model: '\(model.text)' -> shooting to danmuView")
                self?.danmuView.shoot(danmaku: model)
            }
            .store(in: &cancellables)
    }
    
    func setup(with player: AVPlayer, in container: UIView) {
        self.player = player
        print("[DanmuViewManager] setup called in container bounds: \(container.bounds)")
        
        // Setup UI
        danmuView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(danmuView)
        NSLayoutConstraint.activate([
            danmuView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            danmuView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            danmuView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            danmuView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        
        container.layoutIfNeeded()
        danmuView.trackHeight = 52
        danmuView.displayArea = 0.8
        danmuView.recaculateTracks()
        
        print("[DanmuViewManager] After layout, danmuView bounds: \(danmuView.bounds)")
        
        // Observe timeControlStatus directly on player
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if player.timeControlStatus == .playing || player.rate > 0 {
                    print("[DanmuViewManager] Player status playing -> calling danmuView.play()")
                    self.danmuView.play()
                } else if player.timeControlStatus == .paused {
                    print("[DanmuViewManager] Player status paused -> calling danmuView.pause()")
                    self.danmuView.pause()
                }
            }
        }
        
        // Default to play if not explicitly paused
        if player.timeControlStatus != .paused {
            print("[DanmuViewManager] Initial setup: calling danmuView.play()")
            danmuView.play()
        }
        
        // Time observer
        var lastTime: TimeInterval = 0
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            if abs(currentTime - lastTime) > 2 {
                self.clean()
            }
            lastTime = currentTime
            self.provider.playerTimeChange(time: currentTime)
        }
    }
    
    func play() {
        danmuView.play()
    }
    
    func pause() {
        danmuView.pause()
    }
    
    func clean() {
        danmuView.clean()
    }
    
    deinit {
        statusObservation?.invalidate()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        danmuView.stop()
        danmuView.removeFromSuperview()
    }
}
