//
//  CollectionView+Coordinator.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

import UIKit
import SwiftUI
import Combine

extension CollectionView {

    /// A UIKit bridge for `CollectionView` that coordinates:
    /// - UICollectionView delegate callbacks (scrolling, drag & drop)
    /// - Diffable data source and section snapshots (including expandable sections)
    /// - Combine subscriptions for programmatic scrolling
    /// - Optional UI components such as `UIRefreshControl` (pull‑to‑refresh) and `UIPageControl` (carousel pagination)

    public class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
        
        /// Parent
        var parent: CollectionView
        /// Lazily created refresh control (present only if `pullToRefresh` is provided).
        var refreshControl: UIRefreshControl?
        /// Lazily created page control (present only if `pageControl` is provided).
        var pageControl: UIPageControl?
        /// Active scroll subscription.
        private var scrollToCancellable: AnyCancellable?
        /// Identity of the subscribed scroll subject.
        private var scrollToIdentity: ObjectIdentifier?
        /// Last animation flag used by scroll subscription.
        private var scrollToAnimated: Bool?
        /// Edit mode
        var editMode: Bool = false
        /// Signature of the currently applied layout style.
        var layoutSignature: String?
        /// Header registration reused when supplementary headers are enabled.
        private var headerCellRegistration: UICollectionView.SupplementaryRegistration<CustomCollectionViewCell>?
        /// Currently running task for refresh/load-more operations.
        private var activeDataTask: Task<Void, Never>?
        /// Last tail item that triggered incremental loading.
        private var lastLoadMoreTrigger: T?


        init(_ parent: CollectionView) {
            self.parent = parent
        }

        /// Configures datasource, supplementary views, and subscribes to programmatic scroll commands.
        func configure(_ collectionView: UICollectionView) {
            configureDataSource(collectionView)
            syncRuntimeConfiguration(collectionView)
        }
        
        func syncRuntimeConfiguration(_ collectionView: UICollectionView) {
            configureSupplementaryProvider()
            configurePageControl(on: collectionView)
            configureRefreshControl(on: collectionView)
            configureScrollSubscription(on: collectionView)
        }
        
        private func configureScrollSubscription(on collectionView: UICollectionView) {
            guard let scrollTo = parent.scrollTo else {
                scrollToCancellable?.cancel()
                scrollToCancellable = nil
                scrollToIdentity = nil
                scrollToAnimated = nil
                return
            }
            
            let identity = ObjectIdentifier(scrollTo)
            let animated = parent.animatingDifferences
            guard scrollToIdentity != identity || scrollToAnimated != animated else { return }
            
            scrollToCancellable?.cancel()
            scrollToIdentity = identity
            scrollToAnimated = animated
            scrollToCancellable = scrollTo
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak collectionView] value in
                    guard let self, let collectionView else { return }
                    switch value {
                    case .offset(let contentOffset):
                        collectionView.setContentOffset(contentOffset, animated: animated)
                    case .item(let indexPath, let position):
                        guard self.isValid(indexPath: indexPath) else { return }
                        collectionView.scrollToItem(at: indexPath, at: position, animated: animated)
                    }
                }
        }

        private func isValid(indexPath: IndexPath) -> Bool {
            let snapshot = dataSource.snapshot()
            guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return false }
            let section = snapshot.sectionIdentifiers[indexPath.section]
            let rowsCount = snapshot.numberOfItems(inSection: section)
            return indexPath.row >= 0 && indexPath.row < rowsCount
        }
        
        private func configureRefreshControl(on collectionView: UICollectionView) {
            let needsRefreshControl = parent.pullToRefresh != nil || parent.loadMoreData != nil
            guard needsRefreshControl else {
                collectionView.refreshControl = nil
                refreshControl = nil
                return
            }
            
            if refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(reloadData), for: .valueChanged)
                refreshControl = control
            }
            collectionView.refreshControl = refreshControl
        }
        
        private func configurePageControl(on collectionView: UICollectionView) {
            guard case let .carousel(_, _, _, pageControlStyle, _) = parent.style, let pageControlStyle else {
                pageControl?.removeFromSuperview()
                pageControl = nil
                return
            }
            
            let pc = pageControl ?? UIPageControl()
            if pageControl == nil {
                pc.translatesAutoresizingMaskIntoConstraints = false
                pc.isUserInteractionEnabled = false
                pc.hidesForSinglePage = true
                pc.currentPage = 0
                collectionView.addSubview(pc)
                collectionView.bringSubviewToFront(pc)
                NSLayoutConstraint.activate([
                    pc.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
                    pc.bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor)
                ])
                pageControl = pc
            }
            
            switch pageControlStyle {
            case .minimal(let color):
                pc.backgroundStyle = .minimal
                pc.pageIndicatorTintColor = color?.withAlphaComponent(0.25)
                pc.currentPageIndicatorTintColor = color
            case .prominent(let color):
                pc.backgroundStyle = .prominent
                pc.pageIndicatorTintColor = color?.withAlphaComponent(0.25)
                pc.currentPageIndicatorTintColor = color
            }
            updateNumberOfPages(to: parent.data.first)
        }

        private func updateNumberOfPages(to items: [T]?) {
            guard let items, case let .carousel(layout, _, _, _, _) = parent.style else { return }
            let x = items.count.isMultiple(of: layout.rawValue) ? 0 : 1
            let pages = max(0, (items.count / layout.rawValue) + x)
            pageControl?.numberOfPages = pages
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
            configureSupplementaryProvider()
        }
        
        private func configureSupplementaryProvider() {
            guard let dataSource else { return }
            let shouldUseSupplementaryHeaders = parent.hasSections && parent.canExpandSectionAt == nil && parent.moveItemAt == nil
            guard shouldUseSupplementaryHeaders else {
                dataSource.supplementaryViewProvider = nil
                return
            }
            
            let registration = headerCellRegistration ?? makeSectionHeaderRegistration()
            headerCellRegistration = registration
            dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
                guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }
                return collectionView.dequeueConfiguredReusableSupplementary(using: registration, for: indexPath)
            }
        }
        
        private func makeCellRegistration() -> UICollectionView.CellRegistration<CustomCollectionViewCell, T> {
            UICollectionView.CellRegistration<CustomCollectionViewCell, T> { [weak self] (cell, indexPath, item) in
                guard let self else { return }
                
                let view = parent.content(item)
                cellContentConfiguration(cell, view, id: item)
                
                var accessories: [UICellAccessory] = []
                if indexPath.row == 0, let canExpandSectionAt = parent.canExpandSectionAt, canExpandSectionAt(indexPath.section) != .none {
                    accessories.append(.outlineDisclosure())
                } else if editMode {
                    if parent.canMoveItemFrom?(indexPath) == true {
                        accessories.append(.reorder(displayed: .always))
                    }
                    if parent.selectedIndexPaths != nil {
                        accessories.append(.multiselect(displayed: .always))
                    }
                }
                cell.accessories = accessories
            }
        }
        
        private func makeSectionHeaderRegistration() -> UICollectionView.SupplementaryRegistration<CustomCollectionViewCell> {
            UICollectionView.SupplementaryRegistration<CustomCollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] (cell, _, indexPath) in
                guard let self else { return }
                let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
                let view = parent.content(section)
                cellContentConfiguration(cell, view, id: section)
            }
        }
        
        private func cellContentConfiguration<ItemView: View, ID: Hashable>(_ cell: CustomCollectionViewCell, _ item: ItemView, id: ID) {
            cell.indentationLevel = 0
            let hostedView = item.id(id)
            if #available(iOS 16.0, *) {
                cell.contentConfiguration = UIHostingConfiguration { hostedView }.minSize(width: 0, height: 0).margins(.all, 0)
            } else {
                cell.contentConfiguration = HostingConfiguration { hostedView }.margins(.zero)
            }
            cell.backgroundConfiguration = .clear()
        }

        func reloadSnapshot() {
            let snapshot = dataSource.snapshot()
            if #available(iOS 15.0, *) {
                dataSource.applySnapshotUsingReloadData(snapshot)
            } else {
                self.dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
        
        /// Rebuilds and applies a snapshot for the current items.
        /// If `canExpandSectionAt` is provided, uses `NSDiffableDataSourceSectionSnapshot` per section to manage headers and children.
        func makeSnapshot(items: [[T]]) {
            
            let animatingDifferences = parent.animatingDifferences
            let sections = items.compactMap { $0.first }
            var snapshot = dataSource.snapshot()
//            let previousItems = Dictionary(uniqueKeysWithValues: snapshot.itemIdentifiers.map { ($0, $0) })
//            let changedItems = changedItems(in: displayedItems(from: items), previousItems: previousItems)

            if let canExpand = parent.canExpandSectionAt {
//                markChangedItems(changedItems, on: &snapshot)

                let expandedSections = Dictionary(uniqueKeysWithValues: snapshot.sectionIdentifiers.map { item in
                    let sectionSnapshot = dataSource.snapshot(for: item)
                    return (item, sectionSnapshot.isExpanded(item))
                })
                let currentSections = Set(sections)
                
                let deletedSections = snapshot.sectionIdentifiers.filter { !currentSections.contains($0) }
                if !deletedSections.isEmpty {
                    snapshot.deleteSections(deletedSections)
                    dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
                }

                for i in sections.indices {
                    let section = sections[i]
                    let expandableSection = canExpand(i)
                    var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<T>()
                    
                    switch expandableSection {
                    case .none:
                        sectionSnapshot.append(items[i])
                    default:
                        sectionSnapshot.append([section])
                        sectionSnapshot.append(Array(items[i].dropFirst()), to: section)
                        
                        if let wasExpanded = expandedSections[section] {
                            if wasExpanded {
                                sectionSnapshot.expand([section])
                            } else {
                                sectionSnapshot.collapse([section])
                            }
                        } else if case .expanded = expandableSection {
                            sectionSnapshot.expand([section])
                        }
                    }
                    dataSource.apply(sectionSnapshot, to: section, animatingDifferences: animatingDifferences)
                }
                
            } else {
                
                var main = NSDiffableDataSourceSnapshot<T, T>()
                main.appendSections(sections)
                for i in sections.indices {
                    if parent.hasSections && parent.moveItemAt == nil {
                        main.appendItems(Array(items[i].dropFirst()), toSection: sections[i])
                    } else {
                        main.appendItems(items[i], toSection: sections[i])
                    }
                }
//                markChangedItems(changedItems, on: &main)
                dataSource.apply(main, animatingDifferences: animatingDifferences)
                
            }

            if pageControl != nil {
                updateNumberOfPages(to: items.first)
            }
        }

//        private func displayedItems(from items: [[T]]) -> [T] {
//            items.flatMap { sectionItems in
//                if parent.hasSections && parent.moveItemAt == nil {
//                    return Array(sectionItems.dropFirst())
//                } else {
//                    return sectionItems
//                }
//            }
//        }
//
//        private func changedItems(in items: [T], previousItems: [T: T]) -> [T] {
//            items.filter { item in
//                guard let previousItem = previousItems[item] else { return false }
//                return contentHasChanged(from: previousItem, to: item)
//            }
//        }
//
//        private func contentHasChanged(from previousItem: T, to currentItem: T) -> Bool {
//            guard let previousItem = previousItem as? any CollectionViewComparable else {
//                return false
//            }
//            return !previousItem.hasSameContent(comparedTo: AnyHashable(currentItem))
//        }
//
//        private func markChangedItems(_ items: [T], on snapshot: inout NSDiffableDataSourceSnapshot<T, T>) {
//            guard !items.isEmpty else { return }
//            if #available(iOS 15.0, *) {
//                snapshot.reconfigureItems(items)
//            } else {
//                snapshot.reloadItems(items)
//            }
//        }

        /// Prefetch-like action: when near the end, calls `loadMoreData` to implement infinite scroll.
        public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            guard let loadMoreData = parent.loadMoreData, activeDataTask == nil else { return }
            
            let lastSection = collectionView.numberOfSections - 1
            guard lastSection >= 0, indexPath.section == lastSection else { return }
            
            let lastRow = collectionView.numberOfItems(inSection: lastSection) - 1
            guard lastRow >= 0, indexPath.row == lastRow else { return }
            
            guard let tailItem = dataSource.itemIdentifier(for: indexPath), lastLoadMoreTrigger != tailItem else {
                return
            }
            lastLoadMoreTrigger = tailItem
            
            let refreshControl = refreshControl
            activeDataTask = Task { @MainActor [weak self, weak refreshControl] in
                refreshControl?.beginRefreshing()
                defer {
                    refreshControl?.endRefreshing()
                    self?.activeDataTask = nil
                }
                
                // Mark loading to prevent multiple concurrent requests
                guard !Task.isCancelled else { return }
                await loadMoreData()
            }
        }

        
        // MARK: PullToRefresh

        /// Called by the refresh control to execute the async refresh handler.
        @objc func reloadData() {
            guard activeDataTask == nil, let pullToRefresh = parent.pullToRefresh else { return }

            activeDataTask = Task { @MainActor [weak self, weak refreshControl] in
                refreshControl?.beginRefreshing()
                defer {
                    refreshControl?.endRefreshing()
                    self?.activeDataTask = nil
                }

                guard !Task.isCancelled else { return }
                await pullToRefresh()
                refreshControl?.endRefreshing()
            }
        }

        
        // MARK: Scroll

        /// Forwards scroll updates to the SwiftUI closure.
        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll?(scrollView.contentOffset, scrollView.contentSize)
        }
        

        // MARK: ItemTap and Selection

        public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            selection(collectionView, indexPath)
        }
        
        public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            selection(collectionView, indexPath)
        }
        
        private func selection(_ collectionView: UICollectionView, _ indexPath: IndexPath) {
            guard editMode else { return }
            parent.selectedIndexPaths?.wrappedValue = collectionView.indexPathsForSelectedItems ?? []
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

                    guard sourceId != destinationId else {
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
}
