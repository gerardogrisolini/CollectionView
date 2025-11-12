# CollectionView

This library provides a seamless integration of UIKit's powerful UICollectionView into SwiftUI, enabling developers to leverage advanced collection view features within SwiftUI applications. It bridges the gap between the two frameworks, offering flexibility and performance.

## Features

- List, grid, carousel, and custom layouts  
- Diffable data source support  
- Drag & drop support  
- Programmatic scrolling  
- Pull-to-refresh functionality  
- Infinite scroll loading  
- Expandable sections  
- Swipe actions

## Dependencies:

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/CollectionView.git", from: "2.0.1")
]
```

## Integration with SwiftUI:

```swift
CollectionView(Array(1...20)) { model in
    Text("Item \(model)")
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray))
        .padding(8)
}
```

### Style: (list / collection / grid / carousel, custom layout)

```swift
CollectionView(Array(0...11)) { model in
    Text("Item \(model)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(.orange))
}
.style(.carousel(layout: .three, spacing: 4, padding: 8))
.frame(height: 300)
```

### Expandable sections:

```swift
struct ItemModel: Identifiable, Hashable, Equatable {
    let id: Int
    let isSection: Bool
}

@State private var items: [[ItemModel]] = Dictionary(grouping: 0..<30) { $0 / 10 }
    .sorted { $0.key < $1.key }
    .map { v in v.value.map { i in ItemModel(id: i, isSection: v.value.first == i) } }

CollectionView(items) { model in
    Text(model.isSection ? "Header \(model.id)" : "Item \(model.id)")
        .font(model.isSection ? .headline : .body)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 8)
}
.canExpandSectionAt { section in
    // first 2 sections expanded, then collapsed, then no rule
    section < 2 ? .expanded : section < 4 ? .collapsed : .none
}
```

### Scroll:

```swift
let scrollTo = PassthroughSubject<CollectionViewScrollTo, Never>()

VStack(spacing: 8) {
    HStack {
        Button("Scroll top") { scrollTo.send(.offset(.zero)) }
        Button("Scroll item 25 top") {
            scrollTo.send(.item(IndexPath(row: 24, section: 0), position: .top))
        }
    }
    CollectionView(Array(1...50)) { item in
        Text("Item \(item)")
            .frame(maxWidth: .infinity, minHeight: 44)

    }
    .scrollTo(scrollTo)
    .onScroll { offset, contentHeight in
        print(abs(offset.y), contentHeight.height)
    }
}
```

### Pull-to-refresh and infinite scroll:

```swift
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

CollectionView(data) { item in
    Text("Riga #\(item)").frame(maxWidth: .infinity, minHeight: 48)
}
.pullToRefresh {
    try? await Task.sleep(nanoseconds: 1_000_000_000)
}
.loadMoreData {
    await loadMore()
}
.overlay(Group { if isBusy { ProgressView() } })
```

### Drag & drop:

```swift
@State private var items = (0..<20).map { $0 }

CollectionView([items]) { item in
    Text("Item \(item)")
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 8)
}
.canMoveItemFrom { from in
    // block moving the first element
    !(from.section == 0 && from.row == 0)
}
.canMoveItemAt { _, to in
    // allow drop only in the same section
    .init(operation: to.section == 0 ? .move : .forbidden)
}
.moveItemAt { from, to in
    // update the local model
    let item = items.remove(at: from.row)
    items.insert(item, at: min(to.row, items.count))
}
.environment(\.editMode, .constant(.active))
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
            
            CollectionView(items) { model in
                
                if model == items.first?.first {
                    CollectionView(Array(0...11)) { i in
                        Text("Item \(i)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).fill(.orange))
                    }
                    .style(.carousel(layout: .three, spacing: 4))
                    .scrollTo(nil)
                    .canMoveItemFrom(nil)
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
                
                from.row > 0
                
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
```
