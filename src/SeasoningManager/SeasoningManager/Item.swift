//
//  Item.swift
//  SeasoningManager
//
//  Created by DIO on 2026/09/28.
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
