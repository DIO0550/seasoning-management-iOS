//
//  SMStockOneSeasoningListViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/07/05.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources

class SMStockOneSeasoningListViewController: UIViewController {
    
    let disposeBag = DisposeBag()
    
    var seasoningData: SeasoningData?
    
    // データソース
    var dataSource: RxTableViewSectionedAnimatedDataSource<SMStockOneSeasoningListTableViewCellSectionOfModel>?
    // ビューモデル
    var viewModel: SMStockOneSeasoningTableViewModel = SMStockOneSeasoningTableViewModel()
    
    @IBOutlet weak var stockOneSeasoningListTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }

    override func viewWillAppear(_ animated: Bool) {
        
    }

}
