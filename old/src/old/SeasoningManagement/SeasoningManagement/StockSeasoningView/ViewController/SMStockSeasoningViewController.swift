//
//  SecondViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/09.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

class SMStockSeasoningViewController: UIViewController, UITableViewDelegate {
    let disposeBag = DisposeBag()
    
    var dataSource: RxTableViewSectionedAnimatedDataSource<SMStockSeasoningTableViewCellSectionOfModel>?
    var viewModel: SMStockSeasoningTableViewModel = SMStockSeasoningTableViewModel()
    
    @IBOutlet weak var addStockSeasoningData: UIBarButtonItem!
    
    
    @IBOutlet weak var stockSeasoningTableView: UITableView! {
        didSet {
            let nib = UINib(nibName: SMCommonConst.SMStockSeasoningTableViewCellIdentifier, bundle: nil)
            self.stockSeasoningTableView.register(nib,
                                                  forCellReuseIdentifier: SMCommonConst.SMStockSeasoningTableViewCellIdentifier);
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
         self.viewModel.updateItems()
     }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        let dataSource = RxTableViewSectionedAnimatedDataSource<SMStockSeasoningTableViewCellSectionOfModel>(
          configureCell: { dataSource, tableView, indexPath, item in
            let stockSeasoningTableViewCell = tableView.dequeueReusableCell(withIdentifier: SMCommonConst.SMStockSeasoningTableViewCellIdentifier, for: indexPath) as! SMStockSeaoningTableViewCell
            let model: SMStockSeasoningTableViewCellModel = dataSource[indexPath]
            stockSeasoningTableViewCell.seaoningName.text = model.seasoningName
            stockSeasoningTableViewCell.seaoningCount.text = String(model.stockCount)
            return stockSeasoningTableViewCell
        })
    
        
        self.dataSource = dataSource
        
        self.stockSeasoningTableView.rx.setDelegate(self).disposed(by: self.disposeBag)

        self.viewModel.sectionsObservable()
            .bind(to: self.stockSeasoningTableView.rx.items(dataSource: self.dataSource!))
            .disposed(by: disposeBag)
        
        self.addStockSeasoningData.rx.tap.asDriver().drive(onNext: { [weak self] in
        self?.performSegue(withIdentifier: "SMSelectAddStockSeasoningViewControllerIdentifier",
                           sender: nil)
        })
        .disposed(by: disposeBag)
        
        self.stockSeasoningTableView.rx
            .modelSelected(SMStockSeasoningTableViewCellModel.self)
            .subscribe(onNext: { [weak self] model in
                self?.performSegue(withIdentifier: "SMStockOneSeasoningListViewControllerIdentifier",
                                   sender: nil)
            }).disposed(by: disposeBag)
    }
}

