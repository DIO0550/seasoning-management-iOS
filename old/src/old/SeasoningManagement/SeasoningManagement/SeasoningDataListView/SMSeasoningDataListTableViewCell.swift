//
//  SMSeasoningDataListTableViewCell.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/26.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit

class SMSeasoningDataListTableViewCell: UITableViewCell {
    @IBOutlet weak var seasoningNameLabel: UILabel!
    @IBOutlet weak var seasoningTypeLabel: UILabel!
    @IBOutlet weak var seasoningImageView: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
