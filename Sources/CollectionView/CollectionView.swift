//
//  CollectionView.swift
//
//  Created by Gerardo Grisolini on 25/07/25.
//


import UIKit
import SwiftUI
import Combine


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
@MainActor public struct CollectionView<T>: UIViewRepresentable where T: Hashable, T: Sendable {
    
    /// Data organized as an array of sections. The single-section initializer wraps automatically.
    let data: [[T]]
    /// It has sections.
    let hasSections: Bool
    /// Visual style/configuration of the collection view.
    let style: CollectionViewStyle
    /// Content inset
    let contentInset: UIEdgeInsets
    /// Animating differences
    let animatingDifferences: Bool
    /// Builder returning the SwiftUI view to display in each cell.
    let content: (T) -> any View
    /// Async handler called on pull-to-refresh.
    let pullToRefresh: (() async -> Void)?
    /// Async handler called when approaching the end of content (infinite scroll).
    let loadMoreData: (() async -> Void)?
    /// Callback invoked on item tapped
    let onItemTap: ((T) -> Void)?
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
        contentInset: UIEdgeInsets = .zero,
        animatingDifferences: Bool = true,
        scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>? = nil,
        @ViewBuilder content: @escaping (T) -> any View,
        pullToRefresh: (() async -> Void)? = nil,
        loadMoreData: (() async -> Void)? = nil,
        onItemTap: ((T) -> Void)? = nil,
        onScroll: ((CGPoint) -> Void)? = nil,
        canMoveItemFrom: ((IndexPath) -> Bool)? = nil,
        canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)? = nil,
        moveItemAt: ((IndexPath, IndexPath) -> Void)? = nil)
    {
        hasSections = false
        self.data = [items]
        self.style = style
        self.contentInset = contentInset
        self.animatingDifferences = animatingDifferences
        self.scrollTo = scrollTo
        self.content = content
        self.pullToRefresh = pullToRefresh
        self.loadMoreData = loadMoreData
        self.onItemTap = onItemTap
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
        contentInset: UIEdgeInsets = .zero,
        animatingDifferences: Bool = true,
        scrollTo: PassthroughSubject<CollectionViewScrollTo, Never>? = nil,
        @ViewBuilder content: @escaping (T) -> any View,
        pullToRefresh: (() async -> Void)? = nil,
        loadMoreData: (() async -> Void)? = nil,
        onItemTap: ((T) -> Void)? = nil,
        onScroll: ((CGPoint) -> Void)? = nil,
        canExpandSectionAt: ((Int) -> ExpandableSection)? = nil,
        canMoveItemFrom: ((IndexPath) -> Bool)? = nil,
        canMoveItemAt: ((IndexPath, IndexPath) -> UICollectionViewDropProposal)? = nil,
        moveItemAt: ((IndexPath, IndexPath) -> Void)? = nil)
    {
        hasSections = true
        self.data = items
        self.style = style
        self.contentInset = contentInset
        self.animatingDifferences = animatingDifferences
        self.scrollTo = scrollTo
        self.content = content
        self.pullToRefresh = pullToRefresh
        self.loadMoreData = loadMoreData
        self.onItemTap = onItemTap
        self.onScroll = onScroll
        self.canExpandSectionAt = canExpandSectionAt
        self.canMoveItemFrom = canMoveItemFrom
        self.canMoveItemAt = canMoveItemAt
        self.moveItemAt = moveItemAt
    }
    
    /// Builds and configures the underlying `UICollectionView`.
    /// Sets delegate, optional drag & drop, refresh control, and initial layout.
    public func makeUIView(context: Context) -> UICollectionView {
        
        // Selects the appropriate compositional layout based on the requested style.
        let collectionViewLayout = context.coordinator.makeLayout(style: style)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.allowsSelection = onItemTap != nil
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.contentInset = contentInset
        
        if case .carousel(_, _, _, _, let ignoreSafeArea) = style, ignoreSafeArea, let top = UIApplication.shared.windows.first?.safeAreaInsets.top
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
        
        if pullToRefresh != nil {
            context.coordinator.refreshControl = .init()
        }
        
        context.coordinator.configure(collectionView)

        return collectionView
    }
    
    /// Applies the current data by rebuilding the diffable snapshot.
    public func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.makeSnapshot(items: data)
        uiView.contentInset = contentInset
    }
    
    /// Creates the coordinator responsible for datasource, delegate, and subscriptions.
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
    
    VStack(spacing: 50) {
        CollectionView(data, style: .collection(size: .init(width: 100, height: 50), spacing: 8, direction: .horizontal), contentInset: .init(top: 0, left: 16, bottom: 0, right: 16)) { model in
            Text(model.description)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: 50)
                .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
        }
        .frame(height: 60)

        CollectionView(data, style: .collection(size: .init(width: 100, height: 50), spacing: 8)) { model in
            Text(model)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: 50)
                .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
        }
        .padding()
    }
}

#Preview("Carousel") {
    CollectionView(Array(1...9), style: .carousel(layout: .three, spacing: 10, padding: 16, pageControl: .minimal(.blue))) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .frame(height: 300)
}

#Preview("Grid") {
    CollectionView(Array(1...30), style: .grid(numOfColumns: 3, heightOfRow: 50, spacing: 8)) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: 50)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .padding()
}

