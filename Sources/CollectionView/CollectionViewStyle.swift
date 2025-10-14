//
//  CollectionViewStyle.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

import UIKit

public enum CollectionViewStyle {
    /// A plain list layout using `UICollectionLayoutListConfiguration`.
    case list
    /// A collection layout with fixed item size and inter-item spacing.
    case collection(size: CGSize, spacing: CGFloat, direction: UICollectionView.ScrollDirection = .vertical)
    /// A grid layout with the specified number of columns, row height, and spacing.
    case grid(numOfColumns: Int, heightOfRow: CGFloat, spacing: CGFloat)
    /// A horizontally scrolling carousel with a preset layout and custom spacing.
    case carousel(layout: CarouselLayout, spacing: CGFloat, padding: CGFloat = 0, pageControl: PageControlStyle? = nil, ignoreSafeArea: Bool = false)
    /// Use a fully custom `UICollectionViewLayout` instance provided by the caller.
    case custom(UICollectionViewLayout)
    
    /// Predefined carousel grid presets. The layout adapts to container size and orientation.
    public enum CarouselLayout: Int {
        /// One item per page.
        case one = 1
        /// Two items per page (layout adapts to orientation).
        case two = 2
        /// Three items per page as a 1+2 grid.
        case three = 3
        /// Four items per page (2x2 grid).
        case four = 4
    }
    
    public enum PageControlStyle {
        case minimal(UIColor? = nil)
        case prominent(UIColor? = nil)
    }
}
