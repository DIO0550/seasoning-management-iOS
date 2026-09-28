//
//  SMStockSeaoningTableViewCell.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/21.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit

class SMStockSeaoningTableViewCell: UITableViewCell {
    
    @IBOutlet weak var seaoningImage: UIImageView!
    @IBOutlet weak var seaoningName: UILabel!
    @IBOutlet weak var seaoningCount: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setupLayer()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    private func setupLayer() {
        self.layer.borderWidth = 2.0
        self.layer.backgroundColor = UIColor.black.cgColor
    }
}
