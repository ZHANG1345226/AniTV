//
//  DanmakuTextCell.swift
//  DanmakuKit_Example
//
//  Created by Q YiZhong on 2020/8/29.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import UIKit

class DanmakuTextCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willDisplay() {}

    override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuTextCellModel else { return }
        let text = NSString(string: model.text)
        context.setAlpha(1.0)
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        context.saveGState()
        context.setTextDrawingMode(.stroke)

        let strokeColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.8)
        let attributes: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: strokeColor]
        context.setStrokeColor(strokeColor.cgColor)
        text.draw(at: .zero, withAttributes: attributes)
        context.restoreGState()

        let attributes1: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        context.setTextDrawingMode(.fill)
        context.setStrokeColor(UIColor.white.cgColor)
        text.draw(at: .zero, withAttributes: attributes1)
    }

    override func didDisplay(_ finished: Bool) {}
}
