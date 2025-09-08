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
        /// A collection layout with fixed item size and inter-item spacing.
        case collection(size: CGSize, spacing: CGFloat)
        /// A grid layout with the specified number of columns, row height, and spacing.
        case grid(numOfColumns: Int, heightOfRow: CGFloat, spacing: CGFloat)
        /// A horizontally scrolling carousel with a preset layout and custom spacing.
        case carousel(layout: CarouselLayout, spacing: CGFloat, pageControl: UIPageControl.BackgroundStyle? = nil, ignoreSafeArea: Bool = false)
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
    }

    /// Controls the expand/collapse behavior of a section when using section snapshots.
    /// Use `.none` to disable expandability for a section.
    public enum ExpandableSection {
        case none
        case expanded
        case collapsed
    }
    
    /// Data organized as an array of sections. The single-section initializer wraps automatically.
    let data: [[T]]
    /// It has sections.
    let hasSections: Bool
    /// Visual style/configuration of the collection view.
    let style: CollectionViewStyle
    /// Builder returning the SwiftUI view to display in each cell.
    let content: (T) -> any View
    /// Async handler called on pull-to-refresh.
    let pullToRefresh: (() async -> Void)?
    /// Async handler called when approaching the end of content (infinite scroll).
    let loadMoreData: (() async -> Void)?
    /// Callback invoked on each `scrollViewDidScroll` with current content offset.
    let onScroll: ((CGPoint) -> Void)?
    /// Query to decide if a section can be expanded or collapsed; `nil` disables expandable sections.
    let canExpandSectionAt: ((Int) -> ExpandableSection)?
    /// Predicate allowing the start of a drag from a given index.
    let canMoveItemFrom: ((IndexPath) -> Bool)?
    /// Policy to determine if a proposed drop is allowed and with what intent.
    let canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)?
    /// Callback called after a move has been successfully applied in the datasource.
    let moveItemAt: ((IndexPath, IndexPath) -> Void)?
    /// Subject used to receive programmatic scroll commands.
    let scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>?

    /// Creates a single-section collection view.
    /// - Parameters:
    ///   - items: Items for the single section.
    ///   - style: Collection style; default is `.list`.
    ///   - scrollTo: Optional subject for performing programmatic scrolling.
    ///   - content: SwiftUI builder for each cell.
    ///   - pullToRefresh: Async handler for refresh (shows a `UIRefreshControl`).
    ///   - loadMoreData: Async handler for incremental loading near the bottom.
    ///   - onScroll: Callback for scroll updates.
    ///   - canMoveItemFrom: Predicate to allow drag start.
    ///   - canMoveItemAt: Drag & drop policy.
    ///   - moveItemAt: Called after moving in snapshot.
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
        hasSections = false
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
        hasSections = true
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
    }
    
    /// Builds and configures the underlying `UICollectionView`.
    /// Sets delegate, optional drag & drop, refresh control, and initial layout.
    public func makeUIView(context: Context) -> UICollectionView {

        var ignoreSafeArea = false
        // Selects the appropriate compositional layout based on the requested style.
        let collectionViewLayout: UICollectionViewLayout
        switch style {
        case .list:
            collectionViewLayout = context.coordinator.listLayout
        case .collection(let size, let spacing):
            collectionViewLayout = context.coordinator.collectionLayout(size: size, spacing: spacing)
        case .grid(let numOfColumns, let heightOfRow, let spacing):
            collectionViewLayout = context.coordinator.gridLayout(numOfColumns: numOfColumns, heightOfRow: heightOfRow, spacing: spacing)
        case .carousel(let layout, let spacing, _, let safeArea):
            collectionViewLayout = context.coordinator.carouselLayout(layout: layout, spacing: spacing)
            ignoreSafeArea = safeArea
        case .custom(let layout):
            collectionViewLayout = layout
        }

        if pullToRefresh != nil {
            context.coordinator.refreshControl = .init()
        }

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.allowsSelection = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        if ignoreSafeArea, let top = UIApplication.shared.windows.first?.safeAreaInsets.top
        {
            collectionView.contentInset.top = -top
            collectionView.contentInset.bottom = -top
        }

        collectionView.delegate = context.coordinator
        if moveItemAt != nil {
            collectionView.dragDelegate = context.coordinator
            collectionView.dropDelegate = context.coordinator
            collectionView.dragInteractionEnabled = true
        }
        
        context.coordinator.configure(collectionView)
        
        return collectionView
    }
    
    /// Applies the current data by rebuilding the diffable snapshot.
    public func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.makeSnapshot(items: data)
    }
    
    /// Creates the coordinator responsible for datasource, delegate, and subscriptions.
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    
    /// Coordinator bridging UIKit delegate, diffable datasource, and Combine subscriptions.
    public class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
        
        /// Combine dispose bag. Subscriptions auto-cancel on dealloc; manual cancellation is unnecessary.
        private var cancellables: Set<AnyCancellable> = []
        /// Parent
        private let parent: CollectionView
        /// Lazily created refresh control (present only if `pullToRefresh` is provided).
        var refreshControl: UIRefreshControl?
        /// Lazily created page control (present only if `pageControl` is provided).
        var pageControl: UIPageControl?
        
        init(_ parent: CollectionView) {
            self.parent = parent
        }

        /// Configures datasource, supplementary views, and subscribes to programmatic scroll commands.
        func configure(_ collectionView: UICollectionView) {
            configureDataSource(collectionView)
            addRefreshControl(to: collectionView)
            addPageControl(to: collectionView)
            
            // Subscribes to programmatic scroll commands.
            if let scrollTo = parent.scrollTo {
                scrollTo
                    .receive(on: DispatchQueue.main)
                    .sink { value in
                        switch value {
                        case .offset(let contentOffset):
                            collectionView.setContentOffset(contentOffset, animated: true)
                        case .item(let indexPath, let position):
                            collectionView.scrollToItem(at: indexPath, at: position, animated: true)
                        }
                    }
                    .store(in: &cancellables)
            }
        }
        
        private func addRefreshControl(to collectionView: UICollectionView) {
            guard let refreshControl = refreshControl else { return }

            refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
            collectionView.addSubview(refreshControl)
        }
        
        private func addPageControl(to collectionView: UICollectionView) {
            guard case let .carousel(layout, _, pageControlStyle, safeArea) = parent.style, let pageControlStyle else { return }

            let totalItems = parent.data.first?.count ?? 1
            let x = totalItems.isMultiple(of: layout.rawValue) ? 0 : 1
            let pages = max(1, (totalItems / layout.rawValue) + x)

            let pc = UIPageControl()
            pc.translatesAutoresizingMaskIntoConstraints = false
            pc.isUserInteractionEnabled = false
            pc.hidesForSinglePage = true
            pc.numberOfPages = pages
            pc.currentPage = 0
            pc.backgroundStyle = pageControlStyle
            collectionView.addSubview(pc)
            collectionView.bringSubviewToFront(pc)
            NSLayoutConstraint.activate([
                pc.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
                pc.bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor, constant: safeArea ? 0 : -16)
            ])
            
            self.pageControl = pc
        }


        // MARK: DiffableDataSource
        
        private var dataSource: UICollectionViewDiffableDataSource<T,T>!
        
        /// Creates registrations for cells and supplementary views and sets the provider for supplementary views if needed.
        private func configureDataSource(_ collectionView: UICollectionView) {
            
            // Cell registrations
            let cellRegistration = makeCellRegistration()
            dataSource = UICollectionViewDiffableDataSource<T, T>(collectionView: collectionView, cellProvider: { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            })
            
            guard parent.canExpandSectionAt == nil && parent.data.count > 1 else { return }
            
            // Supplementary view registrations
            let headerCellRegistration = makeSectionHeaderRegistration()
            dataSource.supplementaryViewProvider = { (collectionView, elementKind, indexPath) -> UICollectionReusableView? in
                if elementKind == UICollectionView.elementKindSectionHeader {
                    return collectionView.dequeueConfiguredReusableSupplementary(using: headerCellRegistration, for: indexPath)
                } else {
                    return nil
                }
            }
        }
        
        private func makeCellRegistration() -> UICollectionView.CellRegistration<CustomCollectionViewCell, T> {
            UICollectionView.CellRegistration<CustomCollectionViewCell, T> { [weak self] (cell, indexPath, item) in
                guard let self else { return }
                // Renders SwiftUI content in the cell using `UIHostingConfiguration` (iOS 16+) or a hosting controller.
                let view = parent.content(item)
                cellContentConfiguration(cell, view)
                
                // Configures accessories: disclosure for expandable nodes, reorder handle if drag is allowed.
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
        
        private func makeSectionHeaderRegistration() -> UICollectionView.SupplementaryRegistration<CustomCollectionViewCell> {
            UICollectionView.SupplementaryRegistration<CustomCollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] (cell, _, indexPath) in
                guard let self else { return }
                let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
                let view = parent.content(section)
                cellContentConfiguration(cell, view)
            }
        }
        
        private func cellContentConfiguration(_ cell: CustomCollectionViewCell, _ item: some View) {
            cell.indentationLevel = 0
            cell.withPriority = { [parent] in
                if case .collection = parent.style { return .fittingSizeLevel }
                else { return .required }
            }()

            if #available(iOS 16.0, *) {
                cell.contentConfiguration = UIHostingConfiguration { item }.margins(.all, 0)
            } else {
                cell.contentConfiguration = HostingConfiguration { item }
            }
        }
        
        /// Rebuilds and applies a snapshot for the current items.
        /// If `canExpandSectionAt` is provided, uses `NSDiffableDataSourceSectionSnapshot` per section to manage headers and children.
        func makeSnapshot(items: [[T]]) {
            
            // Section identifiers are the first element of each section.
            let sectionData = items.compactMap { $0.first }

            func cleanUp() -> [T] {
                var snapshot = dataSource.snapshot()
                let sectionIdentifiers = snapshot.sectionIdentifiers
                if sectionData != sectionIdentifiers {
                    snapshot.deleteSections(sectionIdentifiers)
                    dataSource.apply(snapshot)
                }
                return sectionIdentifiers
            }
            
            if let canExpandSectionAt = parent.canExpandSectionAt {
                
                let sectionIdentifiers = cleanUp()
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

                        // Check if the header is already expanded in the current snapshot
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

            } else if parent.moveItemAt != nil {
                    
                _ = cleanUp()
                for i in sectionData.indices {
                    var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<T>()
                    sectionSnapshot.append(items[i])
                    dataSource.apply(sectionSnapshot, to: sectionData[i])
                }
                
            } else {
                
                var snapshot = NSDiffableDataSourceSnapshot<T, T>()
                snapshot.appendSections(sectionData)
                if parent.hasSections {
                    for i in sectionData.indices {
                        snapshot.appendItems(Array(items[i][1...]), toSection: sectionData[i])
                    }
                } else {
                    for i in sectionData.indices {
                        snapshot.appendItems(items[i], toSection: sectionData[i])
                    }
                }
                dataSource.apply(snapshot)

            }
        }
        
        /// Prefetch-like action: when near the end, calls `loadMoreData` to implement infinite scroll.
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
            guard let refreshControl = refreshControl else { return }
            Task { @MainActor in
                refreshControl.beginRefreshing()
                await parent.pullToRefresh?()
                refreshControl.endRefreshing()
            }
        }

        
        // MARK: Scroll

        /// Forwards scroll updates to the SwiftUI closure.
        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll?(scrollView.contentOffset)
        }
        

        // MARK: Drag & Drop

        /// Provides a local `UIDragItem` and verifies the source with `canMoveItemFrom`.
        public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            if let canMoveItemFrom = parent.canMoveItemFrom {
                guard canMoveItemFrom(indexPath) else { return [] }
            }

            let itemProvider = NSItemProvider(object: indexPath.row.description as NSString)
            let dragItem = UIDragItem(itemProvider: itemProvider)
            dragItem.localObject = indexPath
            return [dragItem]
        }

        /// Allows only local sessions.
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

        /// Applies the move in the snapshot and notifies `moveItemAt`.
        public func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard
                let destinationIndexPath = coordinator.destinationIndexPath,
                let item = coordinator.items.first,
                let sourceIndexPath = item.sourceIndexPath
            else {
                return
            }

            var indexPath: IndexPath?
            
            if let sourceId = dataSource.itemIdentifier(for: sourceIndexPath) {
                if let destinationId = dataSource.itemIdentifier(for: destinationIndexPath) {

                    guard sourceId != destinationId,
                        !(sourceIndexPath.section == 0 && sourceIndexPath.row == 1 && destinationIndexPath.section == 1 && destinationIndexPath.row == 0) else {
                        return // destination equals source, no move.
                    }

                    // valid source and destination
                    var snapshot = dataSource.snapshot()
                    if sourceIndexPath.row > destinationIndexPath.row || sourceIndexPath.section < destinationIndexPath.section {
                        snapshot.moveItem(sourceId, beforeItem: destinationId)
                    } else {
                        snapshot.moveItem(sourceId, afterItem: destinationId)
                        indexPath = IndexPath(row: destinationIndexPath.row + 1, section: destinationIndexPath.section)
                    }
                    dataSource.apply(snapshot)
                }
            }

            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)

            parent.moveItemAt?(sourceIndexPath, indexPath ?? destinationIndexPath)
        }
    }

    /// A list cell that expands vertically to fit the hosted SwiftUI content.
    class CustomCollectionViewCell: UICollectionViewListCell {
        
        var withPriority: UILayoutPriority = .required
        
        override func systemLayoutSizeFitting(
            _ targetSize: CGSize,
            withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
            verticalFittingPriority: UILayoutPriority
        ) -> CGSize {

            // Allows Auto Layout to calculate an unbounded height based on hosted SwiftUI content.
            // Replaces the height in the target size to enable the cell to calculate flexible height.
            var targetSize = targetSize
            targetSize.height = CGFloat.greatestFiniteMagnitude

            // The horizontal fitting priority .required ensures that
            // the desired cell width (targetSize.width)
            // is preserved. The vertical priority .fittingSizeLevel
            // allows the cell to find the best height for the content.
            let size = super.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: withPriority,
                verticalFittingPriority: .fittingSizeLevel
            )
            
            return size
        }
    }
}

//MARK: - CompositionalLayout

extension CollectionView.Coordinator {

    /// List appearance using `UICollectionLayoutListConfiguration`.
    var listLayout: UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        if #available(iOS 15.0, *) {
            config.headerTopPadding = 0
        }
        // Shows section header only if there are multiple sections and expansion is disabled.
        config.headerMode = parent.canExpandSectionAt == nil && parent.data.count > 1 ? parent.moveItemAt == nil ? .supplementary : .firstItemInSection : .none
        return UICollectionViewCompositionalLayout.list(using: config)
    }
    
    /// Compositional layout of collection type.
    func collectionLayout(size: CGSize, spacing: CGFloat) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
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
            section.contentInsets = .zero
            section.interGroupSpacing = spacing + 2

            return section
        }
    }
    
    /// Compositional grid layout.
    func gridLayout(numOfColumns: Int, heightOfRow: CGFloat, spacing: CGFloat) -> UICollectionViewLayout {
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
    func carouselLayout(layout: CollectionView.CollectionViewStyle.CarouselLayout, spacing: CGFloat) -> UICollectionViewLayout {
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
            group.contentInsets = .init(top: spacing, leading: spacing, bottom: spacing, trailing: spacing)
          
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPagingCentered
            section.visibleItemsInvalidationHandler = { [weak self] (_, offset, env) -> Void in
                let page = round(offset.x / env.container.effectiveContentSize.width)
                self?.pageControl?.currentPage = Int(page)
            }
            
            return section
        }
    }
    
    /// Specialized helper for the `.three` carousel presenting a 1+2 grid.
    func threeLayout(spacing: CGFloat, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
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
        section.contentInsets = .zero
        section.visibleItemsInvalidationHandler = { [weak self] (_, offset, env) -> Void in
            let page = round(offset.x / env.container.effectiveContentSize.width)
            self?.pageControl?.currentPage = Int(page)
        }

        return section
    }
}


//MARK: - Preview

@available(iOS 17.0, *)
#Preview("List") {
    struct ListView: View {
        
        let scrollTo = PassthroughSubject<CollectionViewScrollTo, Never>()
        @State var items: [[ItemModel]] = Dictionary(grouping: 0..<100) { $0 / 10 }
            .sorted { $0.key < $1.key }
            .map { v in v.value.map { i in ItemModel(id: i, isSelected: false, isSection: v.value.first == i) } }
        @State var isBusy = false

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

                } pullToRefresh: {
                    
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    
                } loadMoreData: {

                    await loadMore()
                    
                } onScroll: { offset in

                    print(abs(offset.y))
                    
                } canExpandSectionAt: { section in

                    section < 10 ? .expanded : section < 20 ? .collapsed : .none

                } canMoveItemFrom: { from in

                    from.section < 10
                    
                } canMoveItemAt: { from, to in
                    
                    guard to.section == 1 else {
                        return .init(operation: .forbidden)
                    }
                    return .init(operation: .move, intent: .insertAtDestinationIndexPath)
                    
                } moveItemAt: { from, to in
                    
                    print("moveItemAt:", from, to)

                }
            }
            .overlay(
                Group {
                    if isBusy {
                        ProgressView().controlSize(.extraLarge)
                    }
                }
            )
            .edgesIgnoringSafeArea(.bottom)
        }
        
        //MARK: - Functions

        private func getIndex(_ item: ItemModel) -> IndexPath? {
            guard let section = items.firstIndex(where: { $0.firstIndex(where: { item.id == $0.id }) != nil }) else { return nil }
                guard let row = items[section].firstIndex(where: { item.id == $0.id }) else { return nil }
                return .init(row: row, section: section)
        }
        
        private func loadMore() async {
            guard !isBusy else { return }
            isBusy = true

            let count = items.count * 10
            let data = Dictionary(grouping: count..<count+100) { $0 / 10 }
                .sorted { $0.key < $1.key }
                .map { v in v.value.map { i in ItemModel(id: i, isSelected: false, isSection: v.value.first == i) } }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isBusy = false
            
            items.append(contentsOf: data)
        }
        
        //MARK: - Model

        struct ItemModel: Identifiable, Hashable, Equatable {
            let id: Int
            var isSelected: Bool
            let isSection: Bool
        }

        //MARK: - Cell

        struct ListItemView: View {
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
    }

    return ListView()
}

#Preview("Collection") {
    let data: [String] = [
        "Uno", "Dueeeee", "Tre", "Quattroo", "Cinque", "Sei", "Sette", "Ottooooooo", "Nove", "Dieci"
    ]
    CollectionView(data, style: .collection(size: .init(width: 100, height: 50), spacing: 8)) { model in
        Text(model)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, maxHeight: 50)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .padding()
}

#Preview("Carousel") {
    CollectionView(Array(1...9), style: .carousel(layout: .three, spacing: 10, pageControl: .prominent)) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .frame(height: 300)
    .padding()
}

#Preview("Grid") {
    CollectionView(Array(1...30), style: .grid(numOfColumns: 3, heightOfRow: 50, spacing: 8)) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: 50)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .padding()
}

