//
//  ViewController.swift
//  SeasoningManager
//
//  Created by DIO on 2020/11/14.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

class SMSeasoningListViewController: UIViewController {
    typealias Section = SMSeasoningListTableViewCellSectionOfModel
    
    let disposeBag = DisposeBag()
    
    // dataSource
    var dataSeource: RxTableViewSectionedAnimatedDataSource<Section> = {
        let dataSource = RxTableViewSectionedAnimatedDataSource<Section>(
            animationConfiguration: AnimationConfiguration(insertAnimation: .middle, reloadAnimation: .top, deleteAnimation: .top),
            configureCell: { dataSource, tableView, indexPath, item in
                let selectAddSeasoningTableViewCell = tableView.dequeueReusableCell(withIdentifier: SMCommonConst.Identifier.SMSeasoningListIdentifier, for: indexPath) as! SMSeasoningListTableViewCell
                let model: SMSeasoningListTableViewCellModel = dataSource[indexPath]
                
                return selectAddSeasoningTableViewCell
            },
            titleForHeaderInSection: { dataSource, index in
                return dataSource[index].header
            }
        )
        return dataSource
    }()
    
    // ViewModel
    var viewModel: SMSeasoningListViewModel = SMSeasoningListViewModel()
    
    /// 調味料テーブルビュー
    @IBOutlet weak var seasoningListTableView: UITableView! {
        didSet {
            let nib = UINib(nibName: SMNibName.SMSeasoningListCellView, bundle: Bundle.main)
            self.seasoningListTableView.register(nib, forCellReuseIdentifier: SMCommonConst.Identifier.SMSeasoningListIdentifier)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.viewModel.updateItems();
        
        self.viewModel.sectionsObservable()
            .bind(to: self.seasoningListTableView.rx.items(dataSource: self.dataSeource))
            .disposed(by: self.disposeBag)
    }

}

