//
//  SMStockSeasoningTableViewCellModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/20.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMStockSeasoningTableViewCellModel: IdentifiableType, Equatable {
    var seasoningName: String? {
        return self.seasoningData.name
    }
    var stockCount: Int = 1
    var seasoningData: SeasoningData
    init(seasoningData: SeasoningData) {
        self.seasoningData = seasoningData
    }
    
    typealias Identity = String
    var identity: String {
        return id
    }
    let id: String = UUID().uuidString
}
