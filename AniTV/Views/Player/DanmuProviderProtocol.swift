//
//  DanmuProviderProtocol.swift
//  AniTV
//
//  Created by Codex on 2026/7/26.
//

import Foundation
import Combine

protocol DanmuProviderProtocol {
    var onSendTextModel: PassthroughSubject<DanmakuTextCellModel, Never> { get }
    func playerTimeChange(time: TimeInterval)
}
