//
//  SMSeasoningListViewModel.swift
//  SeasoningManager
//
//  Created by DIO on 2020/11/22.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMSeasoningListTableViewCellSectionOfModel: Any {
    public var header: String
    public var items: [Item]
    
    init(header: String, items: [Item]) {
        self.header = header
        self.items = items
    }
}


extension SMSeasoningListTableViewCellSectionOfModel: AnimatableSectionModelType {
    
    typealias Item = SMSeasoningListTableViewCellModel
    
    init(original: SMSeasoningListTableViewCellSectionOfModel, items: [Item]) {
        self = original
        self.items = items
    }
    
    var identity: String {
        return self.header
    }
}
