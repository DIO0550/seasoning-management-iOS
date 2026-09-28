//
//  SMStockSeasoningTableViewCellSectionOfModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/20.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMStockSeasoningTableViewCellSectionOfModel {
    public var header: String
    public var items: [Item]
    
    init(header: String, items: [Item]) {
        self.header = header
        self.items = items
    }
}


extension SMStockSeasoningTableViewCellSectionOfModel: AnimatableSectionModelType {
    
    typealias Item = SMStockSeasoningTableViewCellModel
    
    init(original: SMStockSeasoningTableViewCellSectionOfModel, items: [Item]) {
        self = original
        self.items = items
    }
    
    var identity: String {
        return self.header
    }
}

