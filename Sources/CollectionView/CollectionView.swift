//
//  CollectionView.swift
//
//  Created by Gerardo Grisolini on 25/07/25.
//


import UIKit
import SwiftUI
import Combine

/// A programmatic scroll command for `CollectionView`.
/// - `offset`: Scroll to a content offset.
/// - `item`: Scroll to a specific `IndexPath` with a given `UICollectionView.ScrollPosition`.
public enum CollectionViewScrollTo {
    case offset(CGPoint)
    case item(IndexPath, position: UICollectionView.ScrollPosition)
}

/// A SwiftUI wrapper around `UICollectionView` that exposes a simple, type-safe API.
///
/// `CollectionView` supports:
/// - list/grid/carousel/custom layouts
/// - diffable data source with optional expandable sections
/// - pull-to-refresh and incremental loading (infinite scroll)
/// - programmatic scrolling
/// - selection, scrolling callbacks, and drag & drop
///
/// Provide your items and a SwiftUI content builder to render each cell.
public struct CollectionView<T>: UIViewRepresentable where T: Sendable, T: Hashable {
    
    public enum CollectionViewStyle {
        /// A plain list layout using `UICollectionLayoutListConfiguration`.
        case list
        /// A grid-like compositional layout. Each item has a fixed `size` and the layout auto-derives the number of columns based on container width.
        case collection(size: CGSize, spacing: CGFloat)
        /// A horizontally scrolling carousel with a preset layout and spacing.
        case carousel(layout: CarouselLayout, spacing: CGFloat)
        /// Provide your own `UICollectionViewLayout` instance.
        case custom(UICollectionViewLayout)
        
        /// Predefined carousel grid presets. The layout adapts to container size and orientation.
        public enum CarouselLayout {
            case one
            case two
            case three
            case four
        }
    }

    /// Controls the expand/collapse behavior of a section when using section snapshots.
    /// Use `.none` to disable expandability for a section.
    public enum ExpandableSection {
        case none
        case expanded
        case collapsed
    }
    
    /// Backing data organized as array of sections. Single-section initializer wraps the array for you.
    let data: [[T]]
    /// Visual style/configuration for the collection view.
    let style: CollectionViewStyle
    /// Builder that returns the SwiftUI view to render inside each cell.
    let content: (T) -> any View
    /// Async handler invoked on pull-to-refresh.
    let pullToRefresh: (() async -> Void)?
    /// Async handler invoked while approaching the end of the content (infinite scroll).
    let loadMoreData: (() async -> Void)?
    /// Callback invoked on every `scrollViewDidScroll` with current content offset.
    let onScroll: ((CGPoint) -> Void)?
    /// Query to decide whether a section can be expanded/collapsed; `nil` means no expandable sections.
    let canExpandSectionAt: ((Int) -> ExpandableSection)?
    /// Predicate to allow starting a drag from a specific index path.
    let canMoveItemFrom: ((IndexPath) -> Bool)?
    /// Policy to determine if a proposed drop is allowed and with what intent.
    let canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)?
    /// Callback fired after a successful move within the data source.
    let moveItemAt: ((IndexPath, IndexPath) -> Void)?
    /// Subject used to receive programmatic scroll commands.
    let scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>?
    /// Lazily created refresh control (present only if `pullToRefresh` is provided).
    private var refreshControl: UIRefreshControl!

    /// Creates a single-section collection view.
    /// - Parameters:
    ///   - items: Items for the only section.
    ///   - style: Collection style; defaults to `.list`.
    ///   - scrollTo: Optional subject to perform programmatic scroll.
    ///   - content: SwiftUI builder for each cell.
    ///   - pullToRefresh: Async refresh handler (shows a `UIRefreshControl`).
    ///   - loadMoreData: Async load-more handler invoked near the bottom.
    ///   - onScroll: Callback for scrolling updates.
    ///   - canMoveItemFrom: Predicate to allow starting a drag.
    ///   - canMoveItemAt: Drop policy for drag & drop operations.
    ///   - moveItemAt: Called after the snapshot move is applied.
    public init(
        _ items: [T],
        style: CollectionViewStyle = .list,
        scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>? = nil,
        @ViewBuilder content: @escaping (T) -> any View,
        pullToRefresh: (() async -> Void)? = nil,
        loadMoreData: (() async -> Void)? = nil,
        onScroll: ((CGPoint) -> Void)? = nil,
        canMoveItemFrom: ((IndexPath) -> Bool)? = nil,
        canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)? = nil,
        moveItemAt: ((IndexPath, IndexPath) -> Void)? = nil)
    {
        self.data = [items]
        self.style = style
        self.scrollTo = scrollTo
        self.content = content
        self.pullToRefresh = pullToRefresh
        self.loadMoreData = loadMoreData
        self.onScroll = onScroll
        self.canExpandSectionAt = nil
        self.canMoveItemFrom = canMoveItemFrom
        self.canMoveItemAt = canMoveItemAt
        self.moveItemAt = moveItemAt
        if pullToRefresh != nil {
            refreshControl = UIRefreshControl()
        }
    }

    /// Creates a multi-section collection view.
    /// - Parameters are the same as the single-section initializer, but `items` are provided per section.
    public init(
        _ items: [[T]],
        style: CollectionViewStyle = .list,
        scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>? = nil,
        @ViewBuilder content: @escaping (T) -> any View,
        pullToRefresh: (() async -> Void)? = nil,
        loadMoreData: (() async -> Void)? = nil,
        onScroll: ((CGPoint) -> Void)? = nil,
        canExpandSectionAt: ((Int) -> ExpandableSection)? = nil,
        canMoveItemFrom: ((IndexPath) -> Bool)? = nil,
        canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)? = nil,
        moveItemAt: ((IndexPath, IndexPath) -> Void)? = nil)
    {
        self.data = items
        self.style = style
        self.scrollTo = scrollTo
        self.content = content
        self.pullToRefresh = pullToRefresh
        self.loadMoreData = loadMoreData
        self.onScroll = onScroll
        self.canExpandSectionAt = canExpandSectionAt
        self.canMoveItemFrom = canMoveItemFrom
        self.canMoveItemAt = canMoveItemAt
        self.moveItemAt = moveItemAt
        if pullToRefresh != nil {
            refreshControl = UIRefreshControl()
        }
    }
    
    /// Builds and configures the underlying `UICollectionView`.
    /// Sets delegates, optional drag & drop, refresh control, and initial layout.
    public func makeUIView(context: Context) -> UICollectionView {

        // Select the appropriate compositional layout based on the requested style.
        let collectionViewLayout: UICollectionViewLayout
        switch style {
        case .list:
            collectionViewLayout = listLayout
        case .collection(let size, let spacing):
            collectionViewLayout = collectionLayout(size: size, spacing: spacing)
        case .carousel(let layout, let spacing):
            collectionViewLayout = carouselLayout(layout: layout, spacing: spacing)
        case .custom(let layout):
            collectionViewLayout = layout
        }
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.allowsSelection = false
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.delegate = context.coordinator
        if moveItemAt != nil {
            collectionView.dragDelegate = context.coordinator
            collectionView.dropDelegate = context.coordinator
            collectionView.dragInteractionEnabled = true
        }
        
        if pullToRefresh != nil {
            refreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.reloadData), for: .valueChanged)
            collectionView.addSubview(refreshControl)
        }
        
        context.coordinator.configure(collectionView)
        
        return collectionView
    }

    /// Applies the latest data by rebuilding the diffable snapshot.
    public func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.makeSnapshot(items: data)
    }

    /// Triggers the pull-to-refresh handler (if available) and manages the control state.
    func refresh() {
        guard let pullToRefresh else { return }
        Task { @MainActor in
            refreshControl.beginRefreshing()
            await pullToRefresh()
            refreshControl.endRefreshing()
        }
    }
    
    /// Creates the coordinator responsible for data source, delegate and subscriptions.
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    
    /// Coordinator bridging UIKit delegates, diffable data source, and Combine subscriptions.
    public class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
        
        /// Combine disposables. Subscriptions auto-cancel on deinit; manual cancel is not required.
        private var cancellables: Set<AnyCancellable> = []
        private let parent: CollectionView
        
        init(_ parent: CollectionView) {
            self.parent = parent
        }
        
        /// Sets up data source, supplementary views, and subscribes to `scrollTo` commands.
        func configure(_ collectionView: UICollectionView) {
            configureDataSource(collectionView)
            
            // Subscribe to programmatic scroll commands.
            if let scrollTo = parent.scrollTo {
                scrollTo
                    .receive(on: DispatchQueue.main)
                    .sink { value in
                        switch value {
                        case .offset(let contentOffset):
                            collectionView.contentOffset = contentOffset
                        case .item(let indexPath, let position):
                            collectionView.scrollToItem(at: indexPath, at: position, animated: true)
                        }
                    }
                    .store(in: &cancellables)
            }
        }
        
        /// Diffable data source and registrations.
        // MARK: DiffableDataSource
        
        private var dataSource: UICollectionViewDiffableDataSource<T,T>!
        
        /// Creates cell and supplementary registrations and sets the supplementary provider when needed.
        private func configureDataSource(_ collectionView: UICollectionView) {
            
            // Cell Registrations
            let cellRegistration = makeCellRegistration()
            dataSource = UICollectionViewDiffableDataSource<T, T>(collectionView: collectionView, cellProvider: { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            })
            
            guard parent.canExpandSectionAt == nil && parent.data.count > 1 else { return }
            
            // Supplementary registrations
            let headerCellRegistration = makeSectionHeaderRegistration()
            dataSource.supplementaryViewProvider = { (collectionView, elementKind, indexPath) -> UICollectionReusableView? in
                if elementKind == UICollectionView.elementKindSectionHeader {
                    return collectionView.dequeueConfiguredReusableSupplementary(using: headerCellRegistration, for: indexPath)
                } else {
                    return nil
                }
            }
        }
        
        private func makeCellRegistration() -> UICollectionView.CellRegistration<FullWidthCollectionViewCell, T> {
            UICollectionView.CellRegistration<FullWidthCollectionViewCell, T> { [weak self] (cell, indexPath, item) in
                guard let self else { return }
                // Render the SwiftUI content into the cell using `UIHostingConfiguration` (iOS 16+) or a hosting controller.
                let view = parent.content(item)
                cellContentConfiguration(cell, view)
                
                // Configure accessories: disclosure for expandable nodes, reorder handle if drag is allowed.
                let section: T
                if #available(iOS 15.0, *) {
                    guard let s = dataSource.sectionIdentifier(for: indexPath.section) else { return }
                    section = s
                } else {
                    let snapshot = dataSource.snapshot()
                    guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return }
                    section = snapshot.sectionIdentifiers[indexPath.section]
                }
                
                let snap = dataSource.snapshot(for: section)
                let snap2 = snap.snapshot(of: item, includingParent: false)
                let hasChildren = snap2.items.count > 0
                cell.accessories = hasChildren ? [.outlineDisclosure()] : parent.canMoveItemFrom?(indexPath) == true ? [.reorder(displayed: .always)] : []
            }
        }
        
        private func makeSectionHeaderRegistration() -> UICollectionView.SupplementaryRegistration<FullWidthCollectionViewCell> {
            UICollectionView.SupplementaryRegistration<FullWidthCollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] (cell, _, indexPath) in
                guard let self else { return }
                let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
                let view = parent.content(section)
                cellContentConfiguration(cell, view)
            }
        }
        
        private func cellContentConfiguration(_ cell: UICollectionViewListCell, _ item: some View) {
            cell.indentationLevel = 0

            if #available(iOS 16.0, *) {
                cell.contentConfiguration = UIHostingConfiguration { item }.margins(.all, 0)
            } else {
                let controller = UIHostingController(rootView: item)
                cell.contentView.addSubview(controller.view)
                controller.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    controller.view.leftAnchor.constraint(equalTo: cell.contentView.leftAnchor, constant: 0),
                    controller.view.rightAnchor.constraint(equalTo: cell.contentView.rightAnchor, constant: 0),
                    controller.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 0),
                    controller.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: 0),
                ])
                controller.view.layer.masksToBounds = true
            }
        }
        
        /// Rebuilds and applies a snapshot for the current items.
        /// If `canExpandSectionAt` is provided, uses `NSDiffableDataSourceSectionSnapshot` per section to manage headers and children.
        func makeSnapshot(items: [[T]]) {
            // Section identifiers are the first element of each section.
            let sectionData = items.map { $0.first! }
            
            if let canExpandSectionAt = parent.canExpandSectionAt {
                                
                let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
                for i in sectionData.indices {
                    var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<T>()
                    let expandableSection = canExpandSectionAt(i)
                    switch expandableSection {
                    case .none:
                        sectionSnapshot.append(items[i])

                    default:
                        let header = sectionData[i]
                        sectionSnapshot.append([header])
                        sectionSnapshot.append(Array(items[i][1...]), to: header)

                        if sectionIdentifiers.indices.contains(i) {
                            let snapshot = dataSource.snapshot(for: sectionIdentifiers[i])
                            if snapshot.isExpanded(header) {
                                sectionSnapshot.expand([header])
                            }
                        } else if case .expanded = expandableSection {
                            sectionSnapshot.expand([header])
                        }
                    }

                    dataSource.apply(sectionSnapshot, to: sectionData[i])
                }
                
            } else {
                
                var snapshot = NSDiffableDataSourceSnapshot<T, T>()
                snapshot.appendSections(sectionData)
                // Single section: append all items; multi-section: skip the first element which is used as the section identifier.
                if sectionData.count == 1 {
                    snapshot.appendItems(items[0], toSection: sectionData[0])
                } else {
                    for i in sectionData.indices {
                        snapshot.appendItems(Array(items[i][1...]), toSection: sectionData[i])
                    }
                }
                dataSource.apply(snapshot)
                
            }
            print("makeSnapshot", Date())
        }
        
        /// Prefetch-like trigger: when near the end, call `loadMoreData` to implement infinite scrolling.
        public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            guard let loadMoreData = parent.loadMoreData else { return }
            let snapshot = dataSource.snapshot()
            let section = snapshot.sectionIdentifiers[indexPath.section]
            let rowsCount = snapshot.numberOfItems(inSection: section)
            guard indexPath.section == snapshot.numberOfSections - 1 && (rowsCount > 5 && indexPath.row == rowsCount - 5 || rowsCount == 1) else { return }
            Task {
                await loadMoreData()
            }
        }

        // MARK: PullToRefresh

        /// Called by the refresh control to execute the async refresh handler.
        @objc func reloadData() {
            parent.refresh()
        }

        // MARK: Scroll

        /// Forwards scrolling updates to the SwiftUI closure.
        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll?(scrollView.contentOffset)
        }

        // MARK: Drag & Drop

        /// Provides a local `UIDragItem` and guards the origin with `canMoveItemFrom`.
        public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            if let canMoveItemFrom = parent.canMoveItemFrom {
                guard canMoveItemFrom(indexPath) else { return [] }
            }

            let itemProvider = NSItemProvider(object: indexPath.row.description as NSString)
            let dragItem = UIDragItem(itemProvider: itemProvider)
            dragItem.localObject = indexPath
            return [dragItem]
        }

        /// Only allow local sessions.
        public func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil
        }

        /// Validates the proposed drop with `canMoveItemAt`.
        public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            guard let canMoveItemAt = parent.canMoveItemAt else {
                return .init(operation: .move, intent: .insertAtDestinationIndexPath)
            }
            
            guard let destinationIndexPath,
                  let sourceDestination = session.items.first?.localObject as? IndexPath else {
                return .init(operation: .cancel)
            }
            return canMoveItemAt(sourceDestination, destinationIndexPath)
        }

        /// Applies a move in the snapshot and notifies `moveItemAt`.
        public func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard
                let destinationIndexPath = coordinator.destinationIndexPath,
                let item = coordinator.items.first,
                let sourceIndexPath = item.sourceIndexPath
            else {
                return
            }

            if let sourceId = dataSource.itemIdentifier(for: sourceIndexPath) {
                if let destinationId = dataSource.itemIdentifier(for: destinationIndexPath) {

                    var snapshot = dataSource.snapshot()
                    guard sourceId != destinationId else {
                        return // destination is same as source, no move.
                    }
                    // valid source and destination
                    if sourceIndexPath.row > destinationIndexPath.row {
                        snapshot.moveItem(sourceId, beforeItem: destinationId)
                    } else {
                        snapshot.moveItem(sourceId, afterItem: destinationId)
                    }
                    dataSource.apply(snapshot)

                } else {

                    // no valid destination, eg. moving to the last row of a section
                    var snapshot = dataSource.snapshot()
                    snapshot.deleteItems([sourceId])
                    let toSection = snapshot.sectionIdentifiers[destinationIndexPath.section]
                    snapshot.appendItems([sourceId], toSection: toSection)
                    snapshot.reloadItems([sourceId])
                    dataSource.apply(snapshot)
                }
            }

            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
            parent.moveItemAt?(sourceIndexPath, destinationIndexPath)
        }
    }

    /// A list cell that expands vertically to fit its SwiftUI hosted content.
    class FullWidthCollectionViewCell: UICollectionViewListCell {
        override func systemLayoutSizeFitting(
            _ targetSize: CGSize,
            withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
            verticalFittingPriority: UILayoutPriority
        ) -> CGSize {

            // Allow Auto Layout to compute an unconstrained height based on hosted SwiftUI view.
            // Replace the height in the target size to
            // allow the cell to flexibly compute its height
            var targetSize = targetSize
            targetSize.height = CGFloat.greatestFiniteMagnitude

            // The .required horizontal fitting priority means
            // the desired cell width (targetSize.width) will be
            // preserved. However, the vertical fitting priority is
            // .fittingSizeLevel meaning the cell will find the
            // height that best fits the content
            let size = super.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )

            return size
        }
    }
}

//MARK: - CompositionalLayout

extension CollectionView {

    /// List appearance using `UICollectionLayoutListConfiguration`.
    private var listLayout: UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        if #available(iOS 15.0, *) {
            config.headerTopPadding = 0
        }
        // Show section headers only when multiple sections and expand/collapse are disabled.
        config.headerMode = canExpandSectionAt == nil && data.count > 1 ? .supplementary : .none
        return UICollectionViewCompositionalLayout.list(using: config)
    }

    /// Grid-like compositional layout. Calculates the number of columns from container width and item width.
    private func collectionLayout(size: CGSize, spacing: CGFloat) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            // Compute how many columns can fit while keeping the requested item width.
            let availableWidth = environment.container.effectiveContentSize.width
            let minItemWidth: CGFloat = size.width
            let columns = max(Int(availableWidth / minItemWidth), 1)
            
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .absolute(size.height)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(size.height + spacing + spacing)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitems: [item]
            )
            group.interItemSpacing = .fixed(spacing)
            group.contentInsets = .init(top: spacing, leading: spacing, bottom: spacing, trailing: spacing)

            return NSCollectionLayoutSection(group: group)
        }
    }
    
    /// Horizontally paged carousel with presets that adapt to orientation/size class.
    private func carouselLayout(layout: CollectionViewStyle.CarouselLayout, spacing: CGFloat) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            // Choose preset and derive row/column configuration.
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
                    rowsHeight = .fractionalHeight(0.5)
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
                let isVertical = environment.container.effectiveContentSize.width < environment.container.effectiveContentSize.height
                return threeLayout(spacing: spacing, isVertical: isVertical)

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
            group.contentInsets = .init(top: spacing, leading: spacing, bottom: spacing, trailing: spacing)
          
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPagingCentered

            return section
        }
    }
    
    /// Specialized helper for the `.three` carousel to present a 2+1 grid that adapts to orientation.
    private func threeLayout(spacing: CGFloat, isVertical: Bool) -> NSCollectionLayoutSection {
        // In portrait we stack a large item on top and two items horizontally below; in landscape we place them side by side.
        let mainWidth: NSCollectionLayoutDimension
        let trailingWidth: NSCollectionLayoutDimension
        let height: NSCollectionLayoutDimension
        let trailingGroup: NSCollectionLayoutGroup
        let mainGroup: NSCollectionLayoutGroup

        if isVertical {
            mainWidth = .fractionalWidth(1)
            trailingWidth = .fractionalWidth(0.5)
            height = .fractionalHeight(0.5)
        } else {
            mainWidth = .fractionalWidth(2/3)
            trailingWidth = .fractionalWidth(1/3)
            height = .fractionalHeight(1.0)
        }
        
        let mainItem = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: mainWidth,
                heightDimension: height))
        mainItem.contentInsets = NSDirectionalEdgeInsets(
            top: spacing,
            leading: spacing,
            bottom: spacing,
            trailing: spacing)

        let pairItem = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalHeight(isVertical ? 1.0 : 0.5)))
        pairItem.contentInsets = NSDirectionalEdgeInsets(
            top: spacing,
            leading: spacing,
            bottom: spacing,
            trailing: spacing)

        if isVertical {
            trailingGroup = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: trailingWidth,
                    heightDimension: height),
                subitem: pairItem,
                count: 2)
            
            mainGroup = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalHeight(1.0)),
                subitems: [mainItem, trailingGroup])
        } else {
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
        }

        mainGroup.contentInsets = NSDirectionalEdgeInsets(
            top: spacing,
            leading: spacing,
            bottom: spacing,
            trailing: spacing)

        let section = NSCollectionLayoutSection(group: mainGroup)
        section.orthogonalScrollingBehavior = .groupPagingCentered

        return section
    }
}


//MARK: - Preview

fileprivate struct ItemModel: Identifiable, Hashable, Equatable {
    let id: Int
    var isSelected: Bool
    let isSection: Bool
}

fileprivate struct ListItemView: View {
    let item: ItemModel

    var body: some View {
        Group {
            if item.isSection {
                Text("Header \(item.id)")
                    .font(.headline)
                    .bold()
            } else {
                Text("Item \(item.id)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundColor(item.isSelected ? Color.yellow : Color.black)
    }
}

fileprivate struct CarouselView: View {
    var body: some View {
        CollectionView(Array(0...11), style: .carousel(layout: .three, spacing: 4)) { model in
            Text("Item \(model)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).fill(.orange))
        }
        .frame(height: 300)
    }
}

@available(iOS 17.0, *)
fileprivate struct ListView: View {
    @State var items: [[ItemModel]] = Dictionary(grouping: 0..<100) { $0 / 10 }
        .sorted { $0.key < $1.key }
        .map { v in v.value.map { i in ItemModel(id: i, isSelected: false, isSection: v.value.first == i) } }
    let scrollTo = PassthroughSubject<CollectionViewScrollTo, Never>()
    @State var isBusy = false

    func getIndex(_ item: ItemModel) -> IndexPath? {
        guard let section = items.firstIndex(where: { $0.firstIndex(where: { item.id == $0.id }) != nil }) else { return nil }
            guard let row = items[section].firstIndex(where: { item.id == $0.id }) else { return nil }
            return .init(row: row, section: section)
    }
    
    func loadMore() async {
        guard !isBusy else { return }
        isBusy = true

        let count = items.count * 10
        print(items.count, "-->", count)
        let data = Dictionary(grouping: count..<count+100) { $0 / 10 }
            .sorted { $0.key < $1.key }
            .map { v in v.value.map { i in ItemModel(id: i, isSelected: false, isSection: v.value.first == i) } }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isBusy = false
        
        items.append(contentsOf: data)
    }
    
    var body: some View {
        VStack {
            Menu("Scroll to") {
                Button("Top") { scrollTo.send(.offset(.zero)) }
                ForEach(items.indices, id: \.self) { i in
                    Button("Header \(items[i][0].id)") {
                        scrollTo.send(.item(IndexPath(row: 0, section: i), position: .top))
                    }
                }
            }

            CollectionView(items, scrollTo: scrollTo) { model in
                
                if model.id == 1 {
                    CarouselView()
                } else {
                    ListItemView(item: model)
                        .swipeActions(allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                guard let index = getIndex(model) else { return }
                                items[index.section].remove(at: index.row)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                guard let index = getIndex(model) else { return }
                                items[index.section][index.row].isSelected.toggle()
                            } label: {
                                Label("Pin", systemImage: "pin.fill")
                            }
                            .tint(.yellow)
                        }
                }
                
            } pullToRefresh: {
                
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
            } loadMoreData: {

                await loadMore()
                
            } onScroll: { offset in

                print(abs(offset.y))
                
            } canExpandSectionAt: { section in

                section < 10 ? .expanded : section < 20 ? .collapsed : .none

            } canMoveItemFrom: { from in

                !(from.section == 0 && from.row == 1)
                
            } canMoveItemAt: { from, to in
                
                guard to.section == 1 else {
                    return .init(operation: .forbidden)
                }
                return .init(operation: .move, intent: .insertAtDestinationIndexPath)
                
            } moveItemAt: { from, to in
                
                print("moveItemAt:", from, to)
                
            }
        }
        .listRowInsets(.init())
        .overlay(
            Group {
                if isBusy {
                    ProgressView().controlSize(.extraLarge)
                }
            }
        )
        .edgesIgnoringSafeArea(.bottom)
    }
}

@available(iOS 17.0, *)
#Preview {
    ListView()
}
