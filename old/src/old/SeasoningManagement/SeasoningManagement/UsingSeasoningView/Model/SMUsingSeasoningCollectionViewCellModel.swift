//
//  SMUsingSeasoningCollectionViewCellModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/16.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources

struct SMUsingSeasoningCollectionViewCellModel: IdentifiableType, Equatable {
    var seasoningName: String
    var expirationDate: String
    
    typealias Identity = String
    var identity: String {
        return id
    }
    let id: String = UUID().uuidString
}
