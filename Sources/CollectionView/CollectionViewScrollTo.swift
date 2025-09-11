//
//  CollectionViewScrollTo.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

import UIKit

/// A programmatic scroll command for `CollectionView`.
/// - `offset`: Scroll to a content offset.
/// - `item`: Scroll to a specific `IndexPath` with a given `UICollectionView.ScrollPosition`.
public enum CollectionViewScrollTo {
    case offset(CGPoint)
    case item(IndexPath, position: UICollectionView.ScrollPosition)
}
