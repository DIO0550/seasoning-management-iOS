//
//  DatePickerKeyboardTextField.swift
//  SeasoningManagerCommon
//
//  Created by DIO on 2020/06/28.
//  Copyright © 2020 DIO0550. All rights reserved.
//

import UIKit

public class DatePickerKeyboardTextField: UITextField {
    
    var dateFormatterString = "yyyy年MM月dd日"

    private lazy var datePicker: UIDatePicker = {
        var picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.locale = Locale(identifier: "ja")
        return picker
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }
    
    private func commonInit() {
        self.inputView = self.datePicker
        self.inputAccessoryView = self.keyboardToolbar()
        self.applyPickerValueToText()
    }
    
    private func keyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: 44))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonAction))
        // 右寄せにする
        toolbar.setItems([flexibleSpace, doneButton], animated: true)
        return toolbar
    }
    
    public func dateValue() -> Date {
        return self.datePicker.date
    }
    
    @objc private func doneButtonAction() {
        self.applyPickerValueToText()
        self.resignFirstResponder()
    }
    
    private func applyPickerValueToText() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = self.dateFormatterString
        self.text = dateFormatter.string(from: self.datePicker.date)
    }
    
    override public func caretRect(for position: UITextPosition) -> CGRect {
        return CGRect.zero
    }
    
    override public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        return []
    }

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }
}
