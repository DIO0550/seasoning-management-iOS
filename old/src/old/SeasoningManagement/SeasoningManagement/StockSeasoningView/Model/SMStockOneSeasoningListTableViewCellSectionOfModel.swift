//
//  SMStockOneSeasoningListTableViewCellSectionOfModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/07/05.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMStockOneSeasoningListTableViewCellSectionOfModel {
    public var items: [Item] = []
    
    init() {
    }
}


extension SMStockOneSeasoningListTableViewCellSectionOfModel: AnimatableSectionModelType {
    
    typealias Item = SMStockOneSeasoningListTableViewCellModel
    
    init(original: SMStockOneSeasoningListTableViewCellSectionOfModel, items: [Item]) {
        self = original
        self.items = items
    }
    
    var identity: String {
        return UUID().uuidString
    }
}
