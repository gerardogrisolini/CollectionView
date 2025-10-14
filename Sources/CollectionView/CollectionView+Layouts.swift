//
//  CollectionView+Layouts.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

import UIKit

extension CollectionView.Coordinator {
    
    func makeLayout(style: CollectionViewStyle) -> UICollectionViewLayout {
        switch style {
        case .list:
            return listLayout
        case .collection(let size, let spacing, let direction):
            return collectionLayout(size: size, spacing: spacing, direction: direction)
        case .grid(let numOfColumns, let heightOfRow, let spacing):
            return gridLayout(numOfColumns: numOfColumns, heightOfRow: heightOfRow, spacing: spacing)
        case .carousel(let layout, let spacing, _, _):
            return carouselLayout(layout: layout, spacing: spacing)
        case .custom(let layout):
            return layout
        }
    }

    /// List appearance using `UICollectionLayoutListConfiguration`.
    private var listLayout: UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        if #available(iOS 15.0, *) {
            config.headerTopPadding = 0
        }
        // Shows section header only if there are multiple sections and expansion is disabled.
        config.headerMode = parent.canExpandSectionAt == nil && parent.hasSections ? parent.moveItemAt == nil ? .supplementary : .firstItemInSection : .none
        return UICollectionViewCompositionalLayout.list(using: config)
    }
    
    /// Compositional layout of collection type.
    private func collectionLayout(size: CGSize, spacing: CGFloat, direction: UICollectionView.ScrollDirection) -> UICollectionViewLayout {
        guard direction == .vertical else {
            let flow = UICollectionViewFlowLayout()
            flow.scrollDirection = .horizontal
            flow.estimatedItemSize = size
            flow.minimumInteritemSpacing = spacing
            flow.minimumLineSpacing = spacing
            return flow
        }

        return UICollectionViewCompositionalLayout { _, environment in
            let layoutSize = NSCollectionLayoutSize(
                widthDimension: .estimated(size.width),
                heightDimension: .absolute(size.height)
            )

            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: layoutSize.heightDimension
                ),
                subitems: [.init(layoutSize: layoutSize)]
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing

            return section
        }
    }
    
    /// Compositional grid layout.
    private func gridLayout(numOfColumns: Int, heightOfRow: CGFloat, spacing: CGFloat) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(numOfColumns)),
                heightDimension: .absolute(heightOfRow)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(heightOfRow)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitems: [item]
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .zero
            section.interGroupSpacing = spacing + 2

            return section
        }
    }
    
    /// Horizontal carousel with paging and presets that adapt to orientation and size.
    private func carouselLayout(layout: CollectionViewStyle.CarouselLayout, spacing: CGFloat) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let rowsWidth: NSCollectionLayoutDimension
            let rowsHeight: NSCollectionLayoutDimension
            let rowsCount: Int
            let columnsWidth: NSCollectionLayoutDimension
            let columnsHeight: NSCollectionLayoutDimension
            let columnsCount: Int
            
            switch layout {
            case .one:
                rowsCount = 1
                columnsCount = 1
                rowsWidth = .fractionalWidth(1.0)
                rowsHeight = .fractionalHeight(1.0)
                columnsWidth = .fractionalWidth(1.0)
                columnsHeight = .fractionalHeight(1.0)
            
            case .two:
                let isVertical = environment.container.effectiveContentSize.width < environment.container.effectiveContentSize.height
                if isVertical {
                    rowsCount = 2
                    columnsCount = 1
                    rowsWidth = .fractionalWidth(1.0)
                    rowsHeight = .fractionalHeight(1.0)
                    columnsWidth = .fractionalWidth(1.0)
                    columnsHeight = .fractionalHeight(1.0)
                } else {
                    rowsCount = 1
                    columnsCount = 2
                    rowsWidth = .fractionalWidth(0.5)
                    rowsHeight = .fractionalHeight(1.0)
                    columnsWidth = .fractionalWidth(1.0)
                    columnsHeight = .fractionalHeight(1.0)
                }
            
            case .three:
                return self.threeLayout(spacing: spacing, environment: environment)

            case .four:
                rowsCount = 2
                columnsCount = 2
                rowsWidth = .fractionalWidth(0.5)
                rowsHeight = .fractionalHeight(1.0)
                columnsWidth = .fractionalWidth(1.0)
                columnsHeight = .fractionalHeight(0.5)
            }
            let itemSize = NSCollectionLayoutSize(
                widthDimension: columnsWidth,
                heightDimension: columnsHeight
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let rowColumnSize = NSCollectionLayoutSize(
                widthDimension: rowsWidth,
                heightDimension: rowsHeight
            )
            let rowColumn = NSCollectionLayoutGroup.vertical(
                layoutSize: rowColumnSize,
                subitem: item,
                count: rowsCount
            )
            rowColumn.interItemSpacing = .fixed(spacing)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalHeight(1.0)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: rowColumn,
                count: columnsCount
            )
            group.interItemSpacing = .fixed(spacing)
          
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPagingCentered
            section.visibleItemsInvalidationHandler = { [weak self] (_, offset, env) -> Void in
                let page = round(offset.x / env.container.effectiveContentSize.width)
                self?.pageControl?.currentPage = Int(page)
                self?.parent.onScroll?(offset)
            }
            
            return section
        }
    }
    
    /// Specialized helper for the `.three` carousel presenting a 1+2 grid.
    private func threeLayout(spacing: CGFloat, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let mainWidth: NSCollectionLayoutDimension
        let trailingWidth: NSCollectionLayoutDimension
        let height: NSCollectionLayoutDimension
        let trailingGroup: NSCollectionLayoutGroup
        let mainGroup: NSCollectionLayoutGroup

        mainWidth = .fractionalWidth(2/3)
        trailingWidth = .fractionalWidth(1/3)
        height = .fractionalHeight(1.0)

        let mainItem = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: mainWidth,
                heightDimension: height))
        mainItem.contentInsets = NSDirectionalEdgeInsets(
            top: spacing,
            leading: 0,
            bottom: 0,
            trailing: spacing)

        let pairItem = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalHeight(0.5)))
        pairItem.contentInsets = NSDirectionalEdgeInsets(
            top: spacing,
            leading: 0,
            bottom: 0,
            trailing: 0)

        trailingGroup = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: trailingWidth,
                heightDimension: height),
            subitem: pairItem,
            count: 2)

        mainGroup = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalHeight(1.0)),
            subitems: [mainItem, trailingGroup])
        
        let section = NSCollectionLayoutSection(group: mainGroup)
        section.orthogonalScrollingBehavior = .groupPagingCentered
        section.interGroupSpacing = spacing
        section.visibleItemsInvalidationHandler = { [weak self] (_, offset, env) -> Void in
            let page = round(offset.x / env.container.effectiveContentSize.width)
            self?.pageControl?.currentPage = Int(page)
            self?.parent.onScroll?(offset)
        }

        return section
    }
}
