//
//  SMSeasoningListTableViewCellModel.swift
//  SeasoningManager
//
//  Created by DIO on 2020/11/22.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources


struct SMSeasoningListTableViewCellModel: IdentifiableType, Equatable {
    var seasoningName: String? {
        return self.seasoning.name
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

