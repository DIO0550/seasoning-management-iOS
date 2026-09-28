//
//  SMSeasoningDataInfoViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/30.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxDataSources
import RxSwift
import RxCocoa

class SMSeasoningDataEditViewController: UITableViewController {
    
    /// disposeBag
    let disposeBag = DisposeBag()
    
    let sectionTitles: [String] = ["基本情報", "価格", "栄養素"];
    
    /// テーブルビュー
    @IBOutlet var seasoningDataEditTableView: UITableView!
    
    /// 画像
    @IBOutlet weak var seasoningImageView: UIImageView!
    /// 名前
    @IBOutlet weak var nameLabel: UITextField!
    /// 種類
    @IBOutlet weak var typeLabel: UITextField!
    /// 価格
    @IBOutlet weak var priceLabel: UITextField!
    /// カロリー
    @IBOutlet weak var calorieLabel: UITextField!
    /// タンパク質
    @IBOutlet weak var proteinLabel: UITextField!
    /// 脂質
    @IBOutlet weak var lipidLabel: UITextField!
    /// 糖質
    @IBOutlet weak var sugarLabel: UITextField!
    /// 炭水化物
    @IBOutlet weak var carbohydrateLabel: UITextField!
    
    /// 調味料データ
    var seasoningData: SeasoningData?
    var seasonign: SeasoningNutrients?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupSeaoningData()
        self.tableView.register(UINib.init(nibName: "SMSeasoningEditViewHeader", bundle: nil),
                                forHeaderFooterViewReuseIdentifier: "SMSeasoningEditViewHeaderIndentifier")
    }
    
    private func setupSeaoningData() {
        // 名前
        self.nameLabel.text = self.seasoningData?.name
        // 種類
        self.typeLabel.text = self.seasoningData?.type
        
        if let price = self.seasoningData?.price {
            self.priceLabel.text = String(price)
        } else {
            self.priceLabel.text = String(0)
        }
        
        // カロリー
        if let carorie = self.seasoningData?.nutrients?.calorie {
            self.calorieLabel.text = String(carorie)
        } else {
            self.calorieLabel.text = String(0)
        }
        
        // タンパク質
        if let protein = self.seasoningData?.nutrients?.protein {
            self.proteinLabel.text = String(protein)
        } else {
            self.proteinLabel.text = String(0)
        }
        
        // 脂質
        if let lipid = self.seasoningData?.nutrients?.lipid {
            self.lipidLabel.text = String(lipid)
        } else {
            self.lipidLabel.text = String(0)
        }
        
        // 糖質
        if let sugar = self.seasoningData?.nutrients?.lipid {
            self.sugarLabel.text = String(sugar)
        } else {
            self.sugarLabel.text = String(0)
        }
        
        // 炭水化物
        if let carbohydrate = self.seasoningData?.nutrients?.carbohydrate {
            self.carbohydrateLabel.text = String(carbohydrate)
        } else {
            self.carbohydrateLabel.text = String(0)
        }
        
        guard let data = self.seasoningData?.image else {
            return
        }
        
        self.seasoningImageView.image = UIImage(data: data)
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SMSeasoningEditViewHeaderIndentifier") as? SMSeasoningDataEditTableViewHeader
        headerView?.contentView.backgroundColor = SMAssetsColor.seasoningDataEditTableSectionHeaderColor
        headerView?.textLabel?.textColor = UIColor.white
        return headerView
    }
    
    
}
