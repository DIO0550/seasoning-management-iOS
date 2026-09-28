//
//  FirstViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/09.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

class SMUsingSeasoningViewController: UIViewController, UICollectionViewDelegate {
    
    struct SMUsingSeasoningListCollectionViewMergin {
        static let Left: CGFloat = 10.0
        static let Right: CGFloat = 10.0
    }
    
    static let SMUsingSeasoningListCollectionViewItemHeight: CGFloat = 150.0
    
    let disposeBag = DisposeBag()
    
    var dataSource: RxCollectionViewSectionedAnimatedDataSource<SMUsingSeasoningCollectionViewCellSectionOfModel>?
    var viewModel: SMUsingSeasoningCollectionViewModel = SMUsingSeasoningCollectionViewModel()

    @IBOutlet weak var usingSeasoningListCollectionView: UICollectionView! {
        didSet {
            self.usingSeasoningListCollectionView.register(UINib(nibName: SMCommonConst.SMUsingSeasoningCollectionViewCellIndentifier, bundle: nil),
                                                    forCellWithReuseIdentifier: SMCommonConst.SMUsingSeasoningCollectionViewCellIndentifier)
        }
    }
    @IBOutlet weak var addUsingSeasoningButton: UIButton!
    
    override func viewDidLoad() {
        self.setupFlowLayout()
        
        let dataSource = RxCollectionViewSectionedAnimatedDataSource<SMUsingSeasoningCollectionViewCellSectionOfModel>(
          configureCell: { dataSource, collectionView, indexPath, item in
            let usingSeasoningCollectionViewCell = collectionView.dequeueReusableCell(withReuseIdentifier: SMCommonConst.SMUsingSeasoningCollectionViewCellIndentifier, for: indexPath) as! SMUsingSeasoningCollectionViewCell
            let model: SMUsingSeasoningCollectionViewCellModel = dataSource[indexPath]
            usingSeasoningCollectionViewCell.seasoningNameLabel.text = model.seasoningName
            usingSeasoningCollectionViewCell.expirationDateLabel.text = model.expirationDate
            return usingSeasoningCollectionViewCell
        })
        
        self.addUsingSeasoningButton.rx.tap
            .asDriver().drive(onNext: { [weak self] in
                self?.performSegue(withIdentifier: "SMAddUsingSeasoingViewControllerShowIndentifier",
                                   sender: nil)
            })
            .disposed(by: disposeBag)
        
        self.dataSource = dataSource
        
        self.usingSeasoningListCollectionView.rx.setDelegate(self)
            .disposed(by: disposeBag)
        
        self.viewModel.sectionsObservable()
            .bind(to: self.usingSeasoningListCollectionView.rx.items(dataSource: self.dataSource!))
            .disposed(by: disposeBag)
        
        self.usingSeasoningListCollectionView.rx
            .modelSelected(SMUsingSeasoningCollectionViewCellModel.self)
            .subscribe(onNext: { [weak self] model in
                self?.performSegue(withIdentifier: "SMDetailUsingSeasoningViewControllerScene",
                sender: nil)
            }).disposed(by: disposeBag)
    }
    
    
    private func setupFlowLayout() {
        let layout = UICollectionViewFlowLayout()
        let sideMargin = SMUsingSeasoningListCollectionViewMergin.Left + SMUsingSeasoningListCollectionViewMergin.Right
        layout.itemSize = CGSize(width: self.usingSeasoningListCollectionView.frame.width - sideMargin,
                                 height: SMUsingSeasoningViewController.SMUsingSeasoningListCollectionViewItemHeight)
        layout.sectionInset = UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        layout.minimumLineSpacing = 20
        self.usingSeasoningListCollectionView.collectionViewLayout = layout
    }
}
