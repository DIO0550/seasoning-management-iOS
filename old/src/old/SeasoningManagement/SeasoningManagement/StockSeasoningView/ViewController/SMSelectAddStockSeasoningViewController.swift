//
//  SMAddStockSeasoningViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/06/25.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxSwift
import RxDataSources
import RxCocoa

class SMSelectAddStockSeasoningViewController: UIViewController, UITableViewDelegate {
    let disposeBag = DisposeBag()
    
    var seasoningData: SeasoningData?
    
    // データソース
    var dataSource: RxTableViewSectionedAnimatedDataSource<SMSelectAddStockSeasoningTableViewCellSectionOfModel>?
    // ビューモデル
    var viewModel: SMSelectAddStockSeasoningTableViewModel = SMSelectAddStockSeasoningTableViewModel()
    
    @IBOutlet weak var selectAddStockSeasoningTableView: UITableView! {
        didSet {
            let nib = UINib(nibName: SMCommonConst.SMSelectAddStockSeasoningTableViewCellIdentifier, bundle: nil)
            self.selectAddStockSeasoningTableView.register(nib,
                                                  forCellReuseIdentifier: SMCommonConst.SMSelectAddStockSeasoningTableViewCellIdentifier);
        }
    }
    
    override func viewDidLoad() {
        
        self.setupDataSource()
        
        self.selectAddStockSeasoningTableView.rx.setDelegate(self).disposed(by: self.disposeBag)
        
        self.viewModel.sectionsObservable()
            .bind(to: self.selectAddStockSeasoningTableView.rx.items(dataSource: self.dataSource!))
            .disposed(by: disposeBag)
        
        self.selectAddStockSeasoningTableView.rx
            .modelSelected(SMSelectAddStockSeasoningTableViewCellModel.self)
            .subscribe(onNext: { [weak self] model in
                self?.seasoningData = model.seasoningData
                // TODO: 追加画面
                self?.performSegue(withIdentifier: "SMAddStockSeasoningViewControllerIdentifier",
                                   sender: nil)
        }).disposed(by: disposeBag)
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.viewModel.updateItems()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "SMAddStockSeasoningViewControllerIdentifier" {
            guard let seasoningData = self.seasoningData else {
                return
            }
            let destVC = segue.destination as! SMAddStockSeasoningViewController
            destVC.seasoningData = seasoningData;
        }
    }
    
}

extension SMSelectAddStockSeasoningViewController {
    private func setupDataSource() {
        let dataSource = RxTableViewSectionedAnimatedDataSource<SMSelectAddStockSeasoningTableViewCellSectionOfModel>(
            animationConfiguration: AnimationConfiguration(insertAnimation: .middle, reloadAnimation: .top, deleteAnimation: .top),
            configureCell: { dataSource, tableView, indexPath, item in
                let selectAddSeasoningTableViewCell = tableView.dequeueReusableCell(withIdentifier: SMCommonConst.SMSelectAddStockSeasoningTableViewCellIdentifier, for: indexPath) as! SMSelectAddSeasoningTableViewCell
                let model: SMSelectAddStockSeasoningTableViewCellModel = dataSource[indexPath]
                self.setupSelectAddSeasoningTableViewCell(cell: selectAddSeasoningTableViewCell, seasoningData: model.seasoningData)
                return selectAddSeasoningTableViewCell
            },
            titleForHeaderInSection: { dataSource, index in
                return dataSource[index].header
            }
        )
        
        self.dataSource = dataSource
        
        self.dataSource?.canEditRowAtIndexPath = { dataSource, indexPath  in
            return true
        }
    }
    
    private func setupSelectAddSeasoningTableViewCell(cell: SMSelectAddSeasoningTableViewCell, seasoningData: SeasoningData) {
        
       cell.imageView?.contentMode = .scaleAspectFit
       // 画像
       if let imageData = seasoningData.image {
           let image = UIImage(data: imageData)
           if image?.imageOrientation == .up {
               cell.seasoningImageView.image = UIImage(data: imageData)
           }
       }
       
       // 名前
       cell.seasoningNameLabel.text = seasoningData.name
    }
}
