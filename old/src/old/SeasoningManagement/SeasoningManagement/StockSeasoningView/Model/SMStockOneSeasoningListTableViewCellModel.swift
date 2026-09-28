
//
//  SMStockOneSeasoningListTableViewCellModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/07/05.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMStockOneSeasoningListTableViewCellModel: IdentifiableType, Equatable {
    var seasoningName: String? {
        return self.seasoning.seasoningData!.name
    }
    
    var seasoning: Seasoning
    init(seasoning: Seasoning) {
        self.seasoning = seasoning
    }
    
    typealias Identity = String
    var identity: String {
        return id
    }
    let id: String = UUID().uuidString
}
