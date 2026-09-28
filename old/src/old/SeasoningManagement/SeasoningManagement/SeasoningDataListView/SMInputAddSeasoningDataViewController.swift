//
//  SMInputAddSeasoningDataViewController.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/23.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxDataSources
import RxGesture

class SMInputAddSeasoningDataViewController: UITableViewController {
    /// テーブルビュー
    @IBOutlet var seasoningDataEditTableView: UITableView!
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
    /// イメージビュー
    @IBOutlet weak var seasoningImageView: UIImageView!
    // Doneボタン
    @IBOutlet weak var doneBarButton: UIBarButtonItem!
    
    // 定数
    // disposeBag
    let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib.init(nibName: "SMSeasoningEditViewHeader", bundle: nil),
                                forHeaderFooterViewReuseIdentifier: "SMSeasoningEditViewHeaderIndentifier")
        
        self.doneBarButton.rx.tap.asDriver().drive(onNext: { [weak self] in
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            self?.createSeasoningDataFromInputData()
            appDelegate.saveContext()
            self?.navigationController?.popViewController(animated: true)
        })
        .disposed(by: self.disposeBag)
        
    self.seasoningImageView.rx.tapGesture().when(.recognized).subscribe(onNext: {[weak self] _ in
            self?.presentImagePickerController()
        })
        .disposed(by: self.disposeBag)
    }
    
    private func createSeasoningDataFromInputData() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let seasoningData = appDelegate.createSeasoningData()
        seasoningData.identifier = UUID();
        seasoningData.nutrients = appDelegate.createSeasoningNutrients()
        
        if let fixedImage = self.seasoningImageView.image?.fixedFlipImage() {
            if let imageData = fixedImage.pngData() {
                seasoningData.image = imageData;
            }
        }
        
        // 名前
        if let name = self.nameLabel.text {
            seasoningData.name = name
        } else {
            seasoningData.name = ""
        }
        
        // 種類
        if let type = self.typeLabel.text {
            seasoningData.type = type
        } else {
            seasoningData.type = ""
        }
        
        // 価格
        if let price = self.priceLabel.text {
            seasoningData.price = Int64(price) ?? 0
        } else {
            seasoningData.price = 0
        }
        
        // カロリー
        if let calorie = self.calorieLabel.text {
            seasoningData.nutrients?.calorie = Int64(calorie) ?? 0
        } else {
            seasoningData.nutrients?.calorie = 0
        }
        
        // タンパク質
        if let protein = self.proteinLabel.text {
            seasoningData.nutrients?.protein = Int64(protein) ?? 0
        } else {
            seasoningData.nutrients?.protein = 0
        }
        
        // 脂質
        if let lipid = self.lipidLabel.text {
            seasoningData.nutrients?.lipid = Int64(lipid) ?? 0
        } else {
            seasoningData.nutrients?.lipid = 0
        }
        
        // 糖質
        if let sugar = self.sugarLabel.text {
            seasoningData.nutrients?.sugar = Int64(sugar) ?? 0
        } else {
            seasoningData.nutrients?.sugar = 0
        }
        
        // 炭水化物
        if let carbohydrate = self.carbohydrateLabel.text {
            seasoningData.nutrients?.carbohydrate = Int64(carbohydrate) ?? 0
        } else {
            seasoningData.nutrients?.carbohydrate = 0
        }
    }
}

extension SMInputAddSeasoningDataViewController {
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SMSeasoningEditViewHeaderIndentifier") as? SMSeasoningDataEditTableViewHeader
        headerView?.contentView.backgroundColor = UIColor.init(named: "SMSeasoningDataEditTableSectionHeaderColor")
        headerView?.textLabel?.textColor = UIColor.white
        return headerView
    }
}

extension SMInputAddSeasoningDataViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private func presentImagePickerController() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    // キャンセル時の処理
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    // 画像選択時の処理
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let selectImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            return
        }
        
        self.seasoningImageView.image = selectImage
        self.dismiss(animated: true, completion: nil)
    }
}
