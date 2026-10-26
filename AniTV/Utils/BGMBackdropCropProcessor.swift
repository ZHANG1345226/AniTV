//
//  BGMBackdropCropProcessor.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/10/24.
//

import UIKit
import Kingfisher
import CoreGraphics

/// ImageProcessor that crops portrait Bangumi covers into a 16:9 backdrop
/// using the height range from 1/4 to 2/4 (top to bottom).
public struct BGMBackdropCropProcessor: ImageProcessor {
    public static let `default` = BGMBackdropCropProcessor()

    public let identifier = "xyz.moyuwang.AniTV.BGMBackdropCropProcessor"

    public init() {}

    public func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .image(let image):
            return crop(image: image)
        case .data:
            guard let image = DefaultImageProcessor.default.process(item: item, options: options) else {
                return nil
            }
            return crop(image: image)
        }
    }

    private func crop(image: KFCrossPlatformImage) -> KFCrossPlatformImage? {
        let normalized = image.kf.normalized
        guard let cgImage = normalized.cgImage else { return image }

        let totalW = CGFloat(cgImage.width)
        let totalH = CGFloat(cgImage.height)
        guard totalW > 0, totalH > 0 else { return image }

        // Crop height spans from 1/4 to 2/4 (0.25 * H to 0.50 * H)
        var cropH = totalH * 0.25
        var cropW = cropH * (16.0 / 9.0)
        var cropY = totalH * 0.25
        var cropX = (totalW - cropW) / 2.0

        // If the original image is narrower than 16:9 for this slice, constrain width
        if cropW > totalW {
            cropW = totalW
            cropH = cropW * (9.0 / 16.0)
            let segmentCenterY = totalH * (0.25 + 0.125)
            cropY = segmentCenterY - (cropH / 2.0)
            cropX = 0
        }

        let cropRect = CGRect(
            x: max(0, cropX.rounded()),
            y: max(0, cropY.rounded()),
            width: min(totalW, cropW.rounded()),
            height: min(totalH, cropH.rounded())
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return KFCrossPlatformImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}
