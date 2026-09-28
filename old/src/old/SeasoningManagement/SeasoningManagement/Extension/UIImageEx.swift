//
//  UIImageEx.swift
//  SeasoningManagement
//
//  Created by DIO on 2020/06/15.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit

extension UIImage {
    
    /**
     上下反転している画像を修正する
     
     @return 修正した画像
     */
    func fixedFlipImage() -> UIImage? {
        if self.imageOrientation == .up {
            return self;
        }

        UIGraphicsBeginImageContext(self.size)
        guard let context = UIGraphicsGetCurrentContext() else {
            return self;
        }
        
        context.translateBy(x: self.size.width / 2.0, y: self.size.height / 2)
        context.scaleBy(x: 1.0, y: -1.0)
        context.rotate(by: CGFloat.pi)
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height / 2, width: self.size.width, height: self.size.height))

        let fixedFlipImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return fixedFlipImage
    }
}
