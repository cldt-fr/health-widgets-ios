//
//  Item.swift
//  Health Widgets
//
//  Created by Clément on 01/11/2026.
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
