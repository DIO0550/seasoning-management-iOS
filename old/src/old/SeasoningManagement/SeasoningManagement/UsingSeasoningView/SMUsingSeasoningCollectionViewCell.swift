//
//  SMUsingSeasoningCollectionViewCell.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/05/13.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit
import QuartzCore

class SMUsingSeasoningCollectionViewCell: UICollectionViewCell {

    @IBOutlet weak var seasoningNameLabel: UILabel!
    @IBOutlet weak var expirationDateLabel: UILabel!
    
    static let ChangeSize = 10.0
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setupLayer()
    }
    
    private func setupLayer() {
        self.backgroundColor = UIColor.white
        self.layer.borderWidth = 5.0
        self.layer.cornerRadius = 10.0
        self.layer.masksToBounds = false;
        self.layer.shadowRadius = 8.0
        self.layer.shadowOpacity = 1.0
        self.layer.shadowOffset = CGSize(width: 0, height: 0)
        self.layer.borderColor = UIColor.init(named: "SMUsingSeasoningCollectionViewCellTouchBackgroundColor")?.cgColor
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.decreaseViewSize(size: CGSize(width: SMUsingSeasoningCollectionViewCell.ChangeSize, height: SMUsingSeasoningCollectionViewCell.ChangeSize))
        self.backgroundColor = UIColor.init(named: "SMUsingSeasoningCollectionViewCellTouchBackgroundColor")
        
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.increaseViewSize(size: CGSize(width: SMUsingSeasoningCollectionViewCell.ChangeSize, height: SMUsingSeasoningCollectionViewCell.ChangeSize))
        self.backgroundColor = UIColor.white
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.increaseViewSize(size: CGSize(width: SMUsingSeasoningCollectionViewCell.ChangeSize, height: SMUsingSeasoningCollectionViewCell.ChangeSize))
        self.backgroundColor = UIColor.white
    }
    
    private func decreaseViewSize(size: CGSize) {
        let newFrame: CGRect = self.frame.inset(by: UIEdgeInsets(top: size.height / 2.0, left: size.width / 2.0, bottom: size.height / 2.0, right: size.width / 2.0))
        
        let scaleX = newFrame.width / self.frame.width
        let scaleY = newFrame.height / self.frame.height
        
        UIView.animate(withDuration: 0.1, delay: 0.0, options: [], animations: {
            self.transform = self.transform.scaledBy(x: scaleX, y: scaleY)
        }, completion: nil)
    }
    
    private func increaseViewSize(size: CGSize) {
        UIView.animate(withDuration: 0.1, delay: 0.0, options: [], animations: {
            self.transform = CGAffineTransform.identity
        }, completion: nil)
    }
}
