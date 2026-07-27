//
//  DanDanPlayDanmuProvider.swift
//  AniTV
//
//  Created by Codex on 2026/7/26.
//

import Foundation
import Combine
import UIKit

struct ParsedDanDanPlayDanmu {
    let time: TimeInterval
    let mode: Int
    let color: UInt32
    let userId: String
    let text: String
}

class DanDanPlayDanmuProvider: DanmuProviderProtocol {
    let onSendTextModel = PassthroughSubject<DanmakuTextCellModel, Never>()
    private var allDanmus = [ParsedDanDanPlayDanmu]()
    
    private var lastTime: TimeInterval = 0
    private var danmuIdx: Int = 0
    
    init(episodeId: Int) {
        Task {
            await fetchComments(episodeId: episodeId)
        }
    }
    
    private func fetchComments(episodeId: Int) async {
        do {
            let comments = try await DanDanPlayAPI.shared.getComments(episodeId: episodeId)
            let parsed = comments.compactMap { comment -> ParsedDanDanPlayDanmu? in
                let parts = comment.p.components(separatedBy: ",")
                guard parts.count >= 4,
                      let time = TimeInterval(parts[0]),
                      let mode = Int(parts[1]),
                      let color = UInt32(parts[2]) else {
                    return nil
                }
                return ParsedDanDanPlayDanmu(time: time, mode: mode, color: color, userId: parts[3], text: comment.m)
            }
            
            self.allDanmus = parsed.sorted(by: { $0.time < $1.time })
            self.danmuIdx = 0
            self.lastTime = 0
            print("[DanDanPlay] Loaded \(self.allDanmus.count) danmus for episode \(episodeId)")
        } catch {
            print("[DanDanPlay] Failed to fetch comments for episode \(episodeId): \(error)")
        }
    }
    
    func playerTimeChange(time: TimeInterval) {
        let diff = time - lastTime
        
        // If seek happened, reset the index
        if diff > 5 || diff < 0 {
            danmuIdx = allDanmus.firstIndex(where: { $0.time > time }) ?? allDanmus.count
        }
        
        lastTime = time
        
        while danmuIdx < allDanmus.count {
            let dm = allDanmus[danmuIdx]
            guard dm.time < time else { break }
            danmuIdx += 1
            
            let model = DanmakuTextCellModel(str: dm.text)
            
            let r = CGFloat((dm.color >> 16) & 0xFF) / 255.0
            let g = CGFloat((dm.color >> 8) & 0xFF) / 255.0
            let b = CGFloat(dm.color & 0xFF) / 255.0
            model.color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
            
            switch dm.mode {
            case 4:
                model.type = .bottom
            case 5:
                model.type = .top
            default:
                model.type = .floating
            }
            
            print("[DanDanPlayProvider] Emitting danmaku at time \(time): '\(dm.text)'")
            onSendTextModel.send(model)
        }
    }
}
