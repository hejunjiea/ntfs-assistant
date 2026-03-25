//
//  Item.swift
//  NTFS助手
//
//  Created by tanyou on 2026/3/25.
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
