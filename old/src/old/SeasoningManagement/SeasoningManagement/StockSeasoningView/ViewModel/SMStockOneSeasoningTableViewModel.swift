//
//  SMStockOneSeasoningTableViewModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/07/05.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources
import RxSwift
import RxCocoa

class SMStockOneSeasoningTableViewModel {
    typealias Section = SMStockOneSeasoningListTableViewCellSectionOfModel
    typealias Model = SMStockOneSeasoningListTableViewCellModel
    
    private var items = BehaviorRelay<[Section]>(value: [])
    
    func sectionsObservable() -> Observable<[Section]> {
        return self.items.asObservable()
    }
    
    func updateItems(seasoningData: SeasoningData?) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let filterSeasoning = appDelegate.fetchSeasoningFilterSeasningData(seasoningData: seasoningData)
        var value: [Section] = []
        var section: Section = Section()
        for seasoning in filterSeasoning {
            section.items.append(Model(seasoning: seasoning))
        }
        value.append(section)
        self.items.accept(value)
    }
}
