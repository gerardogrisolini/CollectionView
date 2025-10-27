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
        
        private var isLoadingMore = false
        
        /// Combine dispose bag. Subscriptions auto-cancel on dealloc; manual cancellation is unnecessary.
        private var cancellables: Set<AnyCancellable> = []
        /// Parent
        let parent: CollectionView
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
            addPageControl(to: collectionView)
            addRefreshControl(to: collectionView)
            
            // Subscribes to programmatic scroll commands.
            if let scrollTo = parent.scrollTo {
                scrollTo
                    .receive(on: DispatchQueue.main)
                    .sink { [weak collectionView] value in
                        guard let collectionView else { return }
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
            collectionView.refreshControl = refreshControl
        }
        
        private func addPageControl(to collectionView: UICollectionView) {
            guard case let .carousel(_, _, _, pageControlStyle, _) = parent.style, let pageControlStyle else { return }

            let pc = UIPageControl()
            pc.translatesAutoresizingMaskIntoConstraints = false
            pc.isUserInteractionEnabled = false
            pc.hidesForSinglePage = true
            pc.currentPage = 0
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
            collectionView.addSubview(pc)
            collectionView.bringSubviewToFront(pc)
            NSLayoutConstraint.activate([
                pc.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
                pc.bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor)
            ])
            
            pageControl = pc
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
            
            guard parent.hasSections && parent.canExpandSectionAt == nil && parent.moveItemAt == nil else { return }
            
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
            if let i = item as? CollectionViewCellHeightProviding {
                cell.height = i.height
            }
            if #available(iOS 16.0, *) {
                cell.contentConfiguration = UIHostingConfiguration { item }.margins(.all, 0)
            } else {
                cell.contentConfiguration = HostingConfiguration { item }.margins(.zero)
            }
            cell.backgroundConfiguration = .clear()
        }

        /// Rebuilds and applies a snapshot for the current items.
        /// If `canExpandSectionAt` is provided, uses `NSDiffableDataSourceSectionSnapshot` per section to manage headers and children.
        func makeSnapshot(items: [[T]]) {
            let animatingDifferences = parent.animatingDifferences
            
            let sectionData = items.compactMap { $0.first }
            
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

                    dataSource.apply(sectionSnapshot, to: sectionData[i], animatingDifferences: animatingDifferences)
                }

            } else if parent.moveItemAt != nil {
                    
                for i in sectionData.indices {
                    var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<T>()
                    sectionSnapshot.append(items[i])
                    dataSource.apply(sectionSnapshot, to: sectionData[i], animatingDifferences: animatingDifferences)
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
                dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
                
            }
            
            if pageControl != nil {
                updateNumberOfPages(to: items.first)
            }
        }

        /// Prefetch-like action: when near the end, calls `loadMoreData` to implement infinite scroll.
        public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // Require a loadMoreData handler and avoid re-entrancy while a load is in progress
            guard !isLoadingMore, let loadMoreData = parent.loadMoreData else { return }

            let snapshot = dataSource.snapshot()
            // Ensure the indexPath is valid within the current snapshot
            guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return }
            let section = snapshot.sectionIdentifiers[indexPath.section]
            let rowsCount = snapshot.numberOfItems(inSection: section)
            let numberOfSections = snapshot.numberOfSections
            guard numberOfSections > 0, rowsCount > 0 else { return }

            // Trigger when we reach the last item of the last section
            let isLastSection = indexPath.section == numberOfSections - 1
            let isLastRow = indexPath.row == rowsCount - 1
            guard isLastSection && isLastRow else { return }

            // Mark loading to prevent multiple concurrent requests
            isLoadingMore = true
            Task { [weak self] in
                await loadMoreData()
                await MainActor.run {
                    self?.isLoadingMore = false
                }
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
        

        // MARK: ItemTap

        public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let snapshot = dataSource.snapshot()
            let item = snapshot.itemIdentifiers(inSection: snapshot.sectionIdentifiers[indexPath.section])[indexPath.row]
            parent.onItemTap?(item)
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
}

