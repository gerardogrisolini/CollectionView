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
@MainActor
public struct CollectionView<T>: UIViewRepresentable where T: Hashable, T: Sendable {
    
    /// Edit mode
    @Environment(\.editMode) var editMode
    /// Animating differences
    @Environment(\.animatingDifferences) var animatingDifferences
    /// Visual style/configuration of the collection view.
    @Environment(\.style) var style
    /// Content inset
    @Environment(\.contentInset) var contentInset
    /// Selected IndexPaths
    @Environment(\.selectedIndexPaths) var selectedIndexPaths
    /// Subject used to receive programmatic scroll commands.
    @Environment(\.scrollTo) var scrollTo
    /// Callback invoked on each `scrollViewDidScroll` with current content offset.
    @Environment(\.onScroll) var onScroll
    /// Async handler called on pull-to-refresh.
    @Environment(\.pullToRefresh) var pullToRefresh
    /// Async handler called when approaching the end of content (infinite scroll).
    @Environment(\.loadMoreData) var loadMoreData
    /// Callback invoked on item tapped
    @Environment(\.onItemTap) var onItemTap
    /// Query to decide if a section can be expanded or collapsed; `nil` disables expandable sections.
    @Environment(\.canExpandSectionAt) var canExpandSectionAt
    /// Predicate allowing the start of a drag from a given index.
    @Environment(\.canMoveItemFrom) var canMoveItemFrom
    /// Policy to determine if a proposed drop is allowed and with what intent.
    @Environment(\.canMoveItemAt) var canMoveItemAt
    /// Callback called after a move has been successfully applied in the datasource.
    @Environment(\.moveItemAt) var moveItemAt

    /// Data organized as an array of sections. The single-section initializer wraps automatically.
    let data: [[T]]
    /// It has sections.
    let hasSections: Bool
    /// Builder returning the SwiftUI view to display in each cell.
    let content: (T) -> any View
    
    /// Creates a single-section collection view.
    /// - Parameters:
    ///   - items: Items for the single section.
    ///   - content: SwiftUI builder for each cell.
    public init(_ items: [T], @ViewBuilder content: @escaping (T) -> any View) {
        hasSections = false
        self.data = [items]
        self.content = content
    }
    
    /// Creates a multi-section collection view.
    /// - Parameters:
    ///   - items: Items for the multiple section.
    ///   - content: SwiftUI builder for each cell.
    public init(_ items: [[T]], @ViewBuilder content: @escaping (T) -> any View) {
        hasSections = true
        self.data = items
        self.content = content
    }
    
    /// Builds and configures the underlying `UICollectionView`.
    /// Sets delegate, optional drag & drop, refresh control, and initial layout.
    public func makeUIView(context: Context) -> UICollectionView {
        
        // Selects the appropriate compositional layout based on the requested style.
        let collectionViewLayout = context.coordinator.makeLayout(style: style)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.allowsSelection = onItemTap != nil
        collectionView.allowsMultipleSelection = selectedIndexPaths != nil
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
        
        let mode = editMode?.wrappedValue.isEditing ?? false
        collectionView.delegate = context.coordinator
        if moveItemAt != nil {
            collectionView.dragDelegate = context.coordinator
            collectionView.dropDelegate = context.coordinator
            collectionView.dragInteractionEnabled = mode
        }
        
        context.coordinator.editMode = mode
        context.coordinator.configure(collectionView)

        return collectionView
    }
    
    /// Applies the current data by rebuilding the diffable snapshot.
    public func updateUIView(_ uiView: UICollectionView, context: Context) {
        let mode = editMode?.wrappedValue.isEditing ?? false
        uiView.dragInteractionEnabled = mode

        guard context.coordinator.editMode == mode else {
            context.coordinator.editMode = mode
            context.coordinator.reloadSnapshot()
            return
        }
        context.coordinator.makeSnapshot(items: data)
    }
    
    /// Creates the coordinator responsible for datasource, delegate, and subscriptions.
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}


//MARK: - Preview

@available(iOS 17.0, *)
#Preview("List") {
    struct Item: Identifiable, Hashable, Equatable {
        let id: Int
        var isSelected: Bool
        let isSection: Bool
    }
    struct ListView: View {
        @State var items: [[Item]] = Dictionary(grouping: 0..<100) { $0 / 10 }
            .sorted { $0.key < $1.key }
            .map { v in
                v.value.map { i in
                    Item(id: i, isSelected: false, isSection: v.value.first == i)
                }
            }
        let scrollTo = PassthroughSubject<CollectionViewScrollTo, Never>()
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
                
                CollectionView(items) { model in
                    
                    if model == items.first?.first {
                        CollectionView(Array(0...11)) { i in
                            Text("Item \(i)")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).fill(.orange))
                        }
                        .style(.carousel(layout: .three, spacing: 4))
                        .frame(height: 300)
                    } else if model.isSection {
                        Text("Section \(model.id.description)")
                            .bold()
                            .padding(10)
                    } else {
                        Text("Item \(model.id.description)")
                            .foregroundStyle(model.isSelected ? .yellow : .black)
                            .padding(10)
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
                    
                }
                .scrollTo(scrollTo)
                .pullToRefresh {
                    
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    
                }
                .loadMoreData {
                    
                    await loadMore()
                    
                }
                .onScroll { offset, contentHeight in
                    
                    print(abs(offset.y), contentHeight.height)
                    
                }
                .canExpandSectionAt { section in
                    
                    section == 0 ? .none : section < 5 ? .expanded : .collapsed
                    
                }
                .canMoveItemFrom { from in
                    
                    !(from.section == 0 && from.row == 1)
                    
                }
                .canMoveItemAt { from, to in
                    
                    guard to.section == 1 else {
                        return .init(operation: .forbidden)
                    }
                    return .init(operation: .move, intent: .insertAtDestinationIndexPath)
                    
                }
                .moveItemAt { from, to in
                    
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
        
        func getIndex(_ item: Item) -> IndexPath? {
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
                .map { v in v.value.map { i in Item(id: i, isSelected: false, isSection: v.value.first == i) } }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isBusy = false
            
            items.append(contentsOf: data)
        }
    }
    return ListView().tint(.orange)
}

#Preview("Collection") {
    let data: [String] = [
        "Uno", "Dueeeee", "Tre", "Quattroo", "Cinque", "Sei", "Sette", "Ottooooooo", "Nove", "Dieci"
    ]
    
    VStack(spacing: 50) {
        CollectionView(data) { model in
            Text(model.description)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
        }
        .style(.collection(size: .init(width: 120, height: 50), spacing: 8, direction: .horizontal))
        .contentInset(.init(top: 0, left: 16, bottom: 0, right: 16))
        .frame(height: 60)

        CollectionView(data) { model in
            Text(model)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: 50)
                .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
        }
        .style(.collection(size: .init(width: 120, height: 50), spacing: 8))
        .padding()
    }
}

#Preview("Carousel") {
    CollectionView(Array(1...9)) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .style(.carousel(layout: .three, spacing: 10, padding: 16, pageControl: .minimal(.orange)))
    .frame(height: 300)
}

#Preview("Grid") {
    CollectionView(Array(1...30)) { model in
        Text("Item \(model)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerSize: .init(width: 8, height: 8)).fill(.orange))
    }
    .style(.grid(numOfColumns: 3, heightOfRow: 50, spacing: 8))
    .padding()
}

