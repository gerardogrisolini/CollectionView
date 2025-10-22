//
//  CustomCollectionViewCell.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

import UIKit

extension CollectionView {

    /// A list cell that expands vertically to fit the hosted SwiftUI content.
    class CustomCollectionViewCell: UICollectionViewListCell {
        
        //var withPriority: UILayoutPriority = .required
        var height: CGFloat? = nil

        override func prepareForReuse() {
            super.prepareForReuse()
            backgroundColor = .clear
        }
        
        override func systemLayoutSizeFitting(
            _ targetSize: CGSize,
            withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
            verticalFittingPriority: UILayoutPriority
        ) -> CGSize {

            // Allows Auto Layout to calculate an unbounded height based on hosted SwiftUI content.
            // Replaces the height in the target size to enable the cell to calculate flexible height.
            var targetSize = targetSize
            targetSize.height = CGFloat.greatestFiniteMagnitude

            if let height {
                return .init(width: targetSize.width, height:  height)
            }
            
            // The horizontal fitting priority .required ensures that
            // the desired cell width (targetSize.width)
            // is preserved. The vertical priority .fittingSizeLevel
            // allows the cell to find the best height for the content.
            return super.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: horizontalFittingPriority,
                verticalFittingPriority: .fittingSizeLevel
            )
        }
    }
}

public protocol CollectionViewCellHeightProviding {
    @MainActor @preconcurrency var height: CGFloat? { get }
}
