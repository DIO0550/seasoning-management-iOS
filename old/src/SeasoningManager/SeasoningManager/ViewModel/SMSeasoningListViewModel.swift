//
//  SMSeasoningListViewModel.swift
//  SeasoningManager
//
//  Created by DIO on 2020/11/22.
//

import UIKit
import RxDataSources
import RxSwift
import RxCocoa

class SMSeasoningListViewModel {
    typealias Section = SMSeasoningListTableViewCellSectionOfModel
    typealias Model = SMSeasoningListTableViewCellModel
    
    private var items = BehaviorRelay<[Section]>(value: [])
    
    func sectionsObservable() -> Observable<[Section]> {
        return self.items.asObservable()
    }
    
    func updateItems() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let allSeasonings = appDelegate.fetchAllSeasoning()
        var value: [Section] = []
        for seasoning in allSeasonings {
            let index = self.sameTypeFirstIndex(sections: value, seasoningType: seasoning.type)
            if index != nil {
                value[index!].items += [SMSeasoningListTableViewCellModel(seasoning: seasoning)]
            }
            else {
                let sectionOfCell = Section.init(header: seasoning.type!, items: [Model(seasoning: seasoning)])
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
