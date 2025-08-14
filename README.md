# CollectionView

This library provides a seamless integration of UIKit's powerful UICollectionView into SwiftUI, enabling developers to leverage advanced collection view features within SwiftUI applications. It bridges the gap between the two frameworks, offering flexibility and performance.


## Dependencies:

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/CollectionView.git", from: "1.0.3")
]
```

## Integration with SwiftUI:

```swift
import SwiftUI

struct BasicExampleView: View {
    @State private var items = Array(1...20)

    var body: some View {
        CollectionView(items) { item in
            Text("Elemento \(item)")
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary))
                .padding(.horizontal, 8)
        }
    }
}
```

### Style: (list / collection / carousel, custom layout)

```swift
import SwiftUI

/// Horizontal 3-up carousel
fileprivate struct CarouselView: View {
    var body: some View {
        CollectionView(Array(0...11), style: .carousel(layout: .three, spacing: 4)) { model in
            Text("Item \(model)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(.orange))
        }
        .frame(height: 300)
    }
}
```

### Expandable sections:

```swift
import SwiftUI
import Combine

/// Example of sections + expandable headers
struct ItemModel: Identifiable, Hashable, Equatable {
    let id: Int
    let isSection: Bool
}

struct ExpandabletExampleView: View {
    @State private var items: [[ItemModel]] = Dictionary(grouping: 0..<30) { $0 / 10 }
        .sorted { $0.key < $1.key }
        .map { v in v.value.map { i in ItemModel(id: i, isSection: v.value.first == i) } }

    var body: some View {
        CollectionView(items) { model in
            Text(model.isSection ? "Header \(model.id)" : "Item \(model.id)")
                .font(model.isSection ? .headline : .body)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 8)
        } canExpandSectionAt: { section in
            // first 2 sections expanded, then collapsed, then no rule
            section < 2 ? .expanded : section < 4 ? .collapsed : .none
        }
    }
}
```

### Scroll:

```swift
import SwiftUI
import Combine

struct EventsExampleView: View {
    @State private var items = Array(1...50)
    private let scrollTo = PassthroughSubject<CollectionViewScrollTo, Never>()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Scroll top") { scrollTo.send(.offset(.zero)) }
                Button("Scroll item 25 top") {
                    scrollTo.send(.item(IndexPath(row: 24, section: 0), position: .top))
                }
            }
            CollectionView(items, scrollTo: scrollTo) { item in
                Text("Item \(item)")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } onScroll: { offset in
                print(abs(offset.y))
            }
        }
    }
}
```

### Pull-to-refresh and infinite scroll:

```swift
import SwiftUI

struct RefreshLoadMoreView: View {
    @State private var data = Array(1...40)
    @State private var isBusy = false

    private func loadMore() async {
        guard !isBusy else { return }
        isBusy = true
        let start = (data.last ?? 0) + 1
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        data.append(contentsOf: start..<(start+20))
        isBusy = false
    }

    var body: some View {
        CollectionView(data) { item in
            Text("Riga #\(item)").frame(maxWidth: .infinity, minHeight: 48)
        } pullToRefresh: {
            // fake refresh
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        } loadMoreData: {
            await loadMore()
        }
        .overlay(Group { if isBusy { ProgressView() } })
    }
}
```

### Drag & drop:

```swift
import SwiftUI

struct DragDropExampleView: View {
    @State private var items = (0..<20).map { $0 }

    var body: some View {
        CollectionView([items]) { item in
            Text("Item \(item)")
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
        } canMoveItemFrom: { from in
            // block moving the first element
            !(from.section == 0 && from.row == 0)
        } canMoveItemAt: { _, to in
            // allow drop only in the same section
            .init(operation: to.section == 0 ? .move : .forbidden)
        } moveItemAt: { from, to in
            // update the local model
            let item = items.remove(at: from.row)
            items.insert(item, at: min(to.row, items.count))
        }
    }
}
```


### Example:

```swift
import SwiftUI
import Combine
import CollectionView


struct Item: Identifiable, Hashable, Equatable {
    let id: Int
    var isSelected: Bool
    let isSection: Bool
}

struct ContentView: View {
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

            CollectionView(items, scrollTo: scrollTo) { model in
                
                if model.id == 1 {
                    CollectionView(Array(0...11), style: .carousel(layout: .three, spacing: 4)) { model in
                        Text("Item \(model)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).fill(.orange))
                    }
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
```
