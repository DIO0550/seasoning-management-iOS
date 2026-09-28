//
//  SMAddSeasoningViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/23.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

class SMSeasoningDataListViewController: UIViewController {
    @IBOutlet weak var addDataBarButton: UIBarButtonItem!
    
    // データソース
    var dataSource: RxTableViewSectionedAnimatedDataSource<SMSeasoningDataListTableViewCellSectionOfModel>?
    // ビューモデル
    var viewModel: SMSeasoningDataListTableViewModel = SMSeasoningDataListTableViewModel()
    // 調味料データ
    var seasoningData: SeasoningData?;
    
    // 定数
    // テーブルビューの高さ
    static let SeasoningDataListTableViewRowHegiht: CGFloat = 150.0
    // テーブルビューのヘッダの高さ
    static let SeasoningDataListTableViewHeaderHegiht: CGFloat = 45.0
    
    @IBOutlet weak var dataListSeasoningTableView: UITableView! {
        didSet {
            let nib = UINib(nibName: SMCommonConst.SMSeasoningDataListTableViewCellIdentifier, bundle: nil)
            self.dataListSeasoningTableView.register(nib,
                                                  forCellReuseIdentifier: SMCommonConst.SMSeasoningDataListTableViewCellIdentifier);
        }
    }
    
    let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.dataListSeasoningTableView.allowsMultipleSelectionDuringEditing = true
        
        self.dataListSeasoningTableView.register(UINib.init(nibName: "SMSeasoningDataListHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SMSeasoningDataListHeaderViewIdentifier")

        self.addDataBarButton.rx.tap.asDriver().drive(onNext: { [weak self] in
            self?.performSegue(withIdentifier: "SMInputAddSeasoningDataViewControllerShowIdentifier",
                               sender: nil)
            })
            .disposed(by: disposeBag)
        
        self.setupDataSource()
        
        self.dataListSeasoningTableView.rx.setDelegate(self).disposed(by: self.disposeBag)
        
        self.viewModel.sectionsObservable()
            .bind(to: self.dataListSeasoningTableView.rx.items(dataSource: self.dataSource!))
            .disposed(by: disposeBag)
        
        self.dataListSeasoningTableView.rx
            .modelSelected(SMSeasoningDataListTableViewCellModel.self)
            .subscribe(onNext: { [weak self] model in
                self?.seasoningData = model.seasoningData
                self?.performSegue(withIdentifier: SMCommonConst.SMSeasoningDataEditViewControllerIdentifier, sender: nil)
        }).disposed(by: disposeBag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.viewModel.updateItems()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == SMCommonConst.SMSeasoningDataEditViewControllerIdentifier {
            guard let seasoningData = self.seasoningData else {
                return
            }
            let destVC = segue.destination as! SMSeasoningDataEditViewController
            destVC.seasoningData = seasoningData;
        }
    }
    
    private func setupSeasoningDataListTableViewCell(cell: SMSeasoningDataListTableViewCell, seasoningData: SeasoningData) {
        
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
        
        // 種類
        cell.seasoningTypeLabel.text = seasoningData.type
    }
    
    private func setupDataSource() {
        let dataSource = RxTableViewSectionedAnimatedDataSource<SMSeasoningDataListTableViewCellSectionOfModel>(
            animationConfiguration: AnimationConfiguration(insertAnimation: .middle, reloadAnimation: .top, deleteAnimation: .top),
            configureCell: { dataSource, tableView, indexPath, item in
                let seasoningDataListTableViewCell = tableView.dequeueReusableCell(withIdentifier: SMCommonConst.SMSeasoningDataListTableViewCellIdentifier, for: indexPath) as! SMSeasoningDataListTableViewCell
                let model: SMSeasoningDataListTableViewCellModel = dataSource[indexPath]
                self.setupSeasoningDataListTableViewCell(cell: seasoningDataListTableViewCell, seasoningData: model.seasoningData)
                return seasoningDataListTableViewCell
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
}

extension SMSeasoningDataListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = SMAssetsColor.seasoningManagementColor
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.backgroundColor = SMAssetsColor.seasoningDataEditTableSectionHeaderColor
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SMSeasoningDataListViewController.SeasoningDataListTableViewHeaderHegiht
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SMSeasoningDataListHeaderViewIdentifier") as? SMSeasoningDataListHeaderView
        headerView?.contentView.backgroundColor = SMAssetsColor.seasoningDataEditTableSectionHeaderColor
        headerView?.textLabel?.textColor = UIColor.white
        headerView?.contentView.layer.borderWidth = 2.0
        return headerView
    }
    
    func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        
        let deleteAction = UIContextualAction(style: .destructive, title:  "削除") { [weak self] (action: UIContextualAction, view: UIView, completion :(Bool) -> Void) in
                                                self?.viewModel.remove(indexPath: indexPath)
                                                completion(true)
        }
        deleteAction.image = UIImage.init(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
