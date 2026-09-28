//
//  SMSelectAddStockSeasoningTableViewModel.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/06/27.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources
import RxSwift
import RxCocoa

class SMSelectAddStockSeasoningTableViewModel {
    typealias Section = SMSelectAddStockSeasoningTableViewCellSectionOfModel
    typealias Model = SMSelectAddStockSeasoningTableViewCellModel
    
    private var items = BehaviorRelay<[Section]>(value: [])
    
    func sectionsObservable() -> Observable<[Section]> {
        return self.items.asObservable()
    }
    
    func updateItems() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let allSeasoningData = appDelegate.fetchAllSeasonignData()
        var value: [Section] = []
        for seasoningData in allSeasoningData {
            let index = self.sameTypeFirstIndex(sections: value, seasoningType: seasoningData.type)
            if index != nil {
                value[index!].items += [SMSelectAddStockSeasoningTableViewCellModel(seasoningData: seasoningData)]
            }
            else {
                let sectionOfCell = Section.init(header: seasoningData.type!, items: [Model.init(seasoningData: seasoningData)])
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
}
