//
//  SMStockSeasoningTableViewModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/20.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources
import RxSwift
import RxCocoa

class SMStockSeasoningTableViewModel {
    typealias Section = SMStockSeasoningTableViewCellSectionOfModel
    typealias Model = SMStockSeasoningTableViewCellModel
    
    private var items = BehaviorRelay<[Section]>(value: [])
    
    func sectionsObservable() -> Observable<[Section]> {
        return self.items.asObservable()
    }
    
    func updateItems() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let allSeasoning = appDelegate.fetchAllSeasonign()
        var value: [Section] = []
        for seasoning in allSeasoning {
            let index = self.sameTypeFirstIndex(sections: value, seasoningType: seasoning.seasoningData!.type)
            if index != nil {
                self.incrementSameStockSeasoningCount(items: &value[index!].items, seasoningData: seasoning.seasoningData!)
            }
            else {
                let sectionOfCell = Section.init(header: seasoning.seasoningData!.type!,
                                                 items: [Model.init(seasoningData: seasoning.seasoningData!)])
                value.append(sectionOfCell)
            }
        }
        self.items.accept(value)
    }
    
    private func sameTypeFirstIndex(sections: [Section], seasoningType: String?) -> Int? {
        if sections.count == 0 { return nil }
        guard let type = seasoningType else { return nil }
        
        for (index, section) in sections.enumerated() {
            if section.header == type {
                return index
            }
        }
        
        return nil
    }
    
    private func incrementSameStockSeasoningCount( items :inout [Model], seasoningData: SeasoningData) {
        for i in 0 ..< items.count {
            if items[i].seasoningData != seasoningData {
                continue
            }
            var item = items[i]
            item.stockCount += 1
            items[i] = item
            return
        }
    }
}
