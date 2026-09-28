//
//  SMSelectAddStockSeasoningTableViewCellModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/06/25.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources

struct SMSelectAddStockSeasoningTableViewCellModel: IdentifiableType, Equatable {
    init(seasoningData: SeasoningData) {
        self.seasoningData = seasoningData
    }
    var seasoningData: SeasoningData
    
    typealias Identity = String
    var identity: String {
        return self.seasoningData.identifier!.uuidString
    }
}
