//
//  SMSesoningListTableViewCell.swift
//  SeasoningManager
//
//  Created by DIO on 2020/12/05.
//

import UIKit

class SMSeasoningListTableViewCell: UITableViewCell {
    
    
    /// 画像
    @IBOutlet weak var seasoningImageView: UIImageView!
    
    /// 名前
    @IBOutlet weak var seasoningNameLabel: UILabel!
    
    /// 賞味期限
    @IBOutlet weak var expirationDate: UILabel!
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    public func setupCell(seasoning: Seasoning) {
        self.seasoningNameLabel.text = seasoning.name;
    }

}
