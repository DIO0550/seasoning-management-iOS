//
//  SMUsingSeasoningCollectionViewCellSectionOfModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/16.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

struct SMUsingSeasoningCollectionViewCellSectionOfModel {
    public var header: String
    public var items: [Item]
    
    init(header: String, items: [Item]) {
        self.header = header
        self.items = items
    }
}

extension SMUsingSeasoningCollectionViewCellSectionOfModel: AnimatableSectionModelType {
    
    typealias Item = SMUsingSeasoningCollectionViewCellModel
    
    init(original: SMUsingSeasoningCollectionViewCellSectionOfModel, items: [Item]) {
        self = original
        self.items = items
    }
    
    var identity: String {
        return self.header
    }
}

