//
//  Item.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/10.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
