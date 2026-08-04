//
//  Item.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
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
