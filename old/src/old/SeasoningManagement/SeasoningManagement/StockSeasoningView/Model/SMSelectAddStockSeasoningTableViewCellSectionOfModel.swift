//
//  SMAddStockSeasoningTableViewCellSectionOfModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/06/25.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources

struct SMSelectAddStockSeasoningTableViewCellSectionOfModel {
    public var header: String
    public var items: [Item]
    
    init(header: String, items: [Item]) {
        self.header = header
        self.items = items
    }
}


extension SMSelectAddStockSeasoningTableViewCellSectionOfModel: AnimatableSectionModelType {
    
    typealias Item = SMSelectAddStockSeasoningTableViewCellModel
    
    init(original: SMSelectAddStockSeasoningTableViewCellSectionOfModel, items: [Item]) {
        self = original
        self.items = items
    }
    
    var identity: String {
        return self.header
    }
}
