//
//  CollectionViewEntry.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 09/11/25.
//

import SwiftUI
import Combine

extension EnvironmentValues {
    @Entry var animatingDifferences: Bool = true
    @Entry var style: CollectionViewStyle = .list
    @Entry var contentInset: UIEdgeInsets = .zero
    @Entry var scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>? = nil
    @Entry var onScroll: ((_ value: CGPoint, _ contentSize: CGSize) -> Void)? = nil
    @Entry var pullToRefresh: (() async -> Void)? = nil
    @Entry var loadMoreData: (() async -> Void)? = nil
    @Entry var onItemTap: ((any Hashable) -> Void)? = nil
    @Entry var canExpandSectionAt: ((Int) -> ExpandableSection)? = nil
    @Entry var canMoveItemFrom: ((IndexPath) -> Bool)? = nil
    @Entry var canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)? = nil
    @Entry var moveItemAt: ((IndexPath, IndexPath) -> Void)? = nil
    @Entry var selectedIndexPaths: Binding<[IndexPath]>? = nil
}

extension View {
    
    func animatingDifferences(_ enabled: Bool) -> some View {
        environment(\.animatingDifferences, enabled)
    }

    ///   - style: Visual style/configuration of the collection view.
    func style(_ style: CollectionViewStyle) -> some View {
        environment(\.style, style)
    }
    
    ///   - contentInset: Content inset
    func contentInset(_ inset: UIEdgeInsets) -> some View {
        environment(\.contentInset, inset)
    }
    
    ///   - scrollTo: Optional subject for performing programmatic scrolling.
    func scrollTo(_ action: PassthroughSubject<CollectionViewScrollTo, Never>?) -> some View {
        environment(\.scrollTo, action)
    }
    
    ///   - onScroll: Callback for scroll updates.
    func onScroll(_ action: ((_ value: CGPoint, _ contentSize: CGSize) -> Void)?) -> some View {
        environment(\.onScroll, action)
    }
    
    ///   - pullToRefresh: Async handler for refresh (shows a `UIRefreshControl`).
    func pullToRefresh(_ action: (() async -> Void)?) -> some View {
        environment(\.pullToRefresh, action)
    }
    
    ///   - loadMoreData: Async handler for incremental loading near the bottom.
    func loadMoreData(_ action: (() async -> Void)?) -> some View {
        environment(\.loadMoreData, action)
    }
    
    /// - onItemTap: Callback invoked on item tapped.
    func onItemTap(_ action: ((any Hashable) -> Void)?) -> some View {
        environment(\.onItemTap, action)
    }
    
    /// - canExpandSectionAt: Query to decide if a section can be expanded or collapsed
    func canExpandSectionAt(_ action: ((Int) -> ExpandableSection)?) -> some View {
        environment(\.canExpandSectionAt, action)
    }
    
    ///   - canMoveItemFrom: Predicate to allow drag start.
    func canMoveItemFrom(_ action: ((IndexPath) -> Bool)?) -> some View {
        environment(\.canMoveItemFrom, action)
    }
    
    ///   - canMoveItemAt: Drag & drop policy.
    func canMoveItemAt(_ action: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)?) -> some View {
        environment(\.canMoveItemAt, action)
    }
    
    ///   - moveItemAt: Called after moving in snapshot.
    func moveItemAt(_ action: ((IndexPath, IndexPath) -> Void)?) -> some View {
        environment(\.moveItemAt, action)
    }
    
    func selectedIndexPaths(_ value: Binding<[IndexPath]>?) -> some View {
        environment(\.selectedIndexPaths, value)
    }
}
