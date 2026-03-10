import Testing
@testable import CollectionView
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

@Test func expandableSectionCasesAreDistinct() {
    let values: [ExpandableSection] = [.none, .expanded, .collapsed]
    #expect(values.count == 3)
}

@Test func carouselLayoutRawValuesMatchExpectedSlots() {
    #expect(CollectionViewStyle.CarouselLayout.one.rawValue == 1)
    #expect(CollectionViewStyle.CarouselLayout.two.rawValue == 2)
    #expect(CollectionViewStyle.CarouselLayout.three.rawValue == 3)
    #expect(CollectionViewStyle.CarouselLayout.four.rawValue == 4)
}

@Test func pageControlStyleConstructorsAreAvailable() {
    let minimal = CollectionViewStyle.PageControlStyle.minimal()
    let prominent = CollectionViewStyle.PageControlStyle.prominent()
    #expect({
        if case .minimal = minimal { return true }
        return false
    }())
    #expect({
        if case .prominent = prominent { return true }
        return false
    }())
}

@Test func pageControlStyleCarriesAssociatedColor() {
    let minimal = CollectionViewStyle.PageControlStyle.minimal(.red)
    let prominent = CollectionViewStyle.PageControlStyle.prominent(.blue)

    if case let .minimal(color) = minimal {
        #expect(color == .red)
    } else {
        Issue.record("Expected .minimal case")
    }

    if case let .prominent(color) = prominent {
        #expect(color == .blue)
    } else {
        Issue.record("Expected .prominent case")
    }
}

@Test func collectionAndCarouselDefaultsAreApplied() {
    let collectionStyle = CollectionViewStyle.collection(size: .init(width: 120, height: 50), spacing: 8)
    if case let .collection(size, spacing, direction) = collectionStyle {
        #expect(size == .init(width: 120, height: 50))
        #expect(spacing == 8)
        #expect(direction == .vertical)
    } else {
        Issue.record("Expected .collection case")
    }

    let carouselStyle = CollectionViewStyle.carousel(layout: .two, spacing: 6)
    if case let .carousel(layout, spacing, padding, pageControl, ignoreSafeArea) = carouselStyle {
        #expect(layout == .two)
        #expect(spacing == 6)
        #expect(padding == 0)
        #expect(pageControl == nil)
        #expect(ignoreSafeArea == false)
    } else {
        Issue.record("Expected .carousel case")
    }
}

@MainActor
@Test func adjustedInsetOnlyChangesForCarouselIgnoringSafeArea() {
    let sut = CollectionView([1]) { value in
        Text("\(value)")
    }
    let base = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)

    let unchanged = sut.adjustedContentInset(base: base, style: .list, safeAreaInsets: .init(top: 10, left: 0, bottom: 20, right: 0))
    #expect(unchanged == base)

    let adjusted = sut.adjustedContentInset(
        base: base,
        style: .carousel(layout: .one, spacing: 8, padding: 0, pageControl: nil, ignoreSafeArea: true),
        safeAreaInsets: .init(top: 12, left: 0, bottom: 34, right: 0)
    )
    #expect(adjusted.top == -12)
    #expect(adjusted.bottom == -34)
    #expect(adjusted.left == base.left)
    #expect(adjusted.right == base.right)
}

@MainActor
@Test func singleSectionInitializerWrapsDataAndDisablesSections() {
    let sut = CollectionView([1, 2, 3]) { value in
        Text("\(value)")
    }

    #expect(sut.hasSections == false)
    #expect(sut.data.count == 1)
    #expect(sut.data[0] == [1, 2, 3])
}

@MainActor
@Test func multiSectionInitializerPreservesSections() {
    let sut = CollectionView([[1, 2], [3, 4]]) { value in
        Text("\(value)")
    }

    #expect(sut.hasSections == true)
    #expect(sut.data.count == 2)
    #expect(sut.data[0] == [1, 2])
    #expect(sut.data[1] == [3, 4])
}

@Test func scrollToEnumCarriesOffsetAndItemPayload() {
    let offsetValue = CGPoint(x: 12, y: 34)
    let offsetCommand = CollectionViewScrollTo.offset(offsetValue)
    if case let .offset(value) = offsetCommand {
        #expect(value == offsetValue)
    } else {
        Issue.record("Expected offset command")
    }

    let itemIndexPath = IndexPath(row: 2, section: 1)
    let itemCommand = CollectionViewScrollTo.item(itemIndexPath, position: .centeredVertically)
    if case let .item(indexPath, position) = itemCommand {
        #expect(indexPath == itemIndexPath)
        #expect(position == .centeredVertically)
    } else {
        Issue.record("Expected item command")
    }
}

#if canImport(UIKit)
@MainActor
@Test func customCellPrepareForReuseClearsConfigurationAndAccessories() {
    let cell = CollectionView<Int, Text>.CustomCollectionViewCell()
    cell.contentConfiguration = UIListContentConfiguration.cell()
    cell.accessories = [.disclosureIndicator()]

    cell.prepareForReuse()

    #expect(cell.contentConfiguration == nil)
    #expect(cell.accessories.isEmpty)
}

@Test func hostingConfigurationModifiersPreserveValueSemantics() {
    let original = HostingConfiguration {
        Text("A")
    }
    let withBackground = original.background(.red)
    let withMargins = original.margins(.init(top: 1, leading: 2, bottom: 3, trailing: 4))

    #expect(original.backgroundColor == nil)
    #expect(withBackground.backgroundColor == .red)
    #expect(original.margins == .zero)
    #expect(withMargins.margins == .init(top: 1, leading: 2, bottom: 3, trailing: 4))
}

@MainActor
@Test func hostingConfigurationStateAwareBuilderIsInvoked() {
    var invoked = false
    let config = HostingConfiguration<Text>(stateAware: { _ in
        invoked = true
        return Text("S")
    })

    _ = config.makeContentView()
    #expect(invoked)
}

@MainActor
@Test func hostingContentViewAppliesUpdatedConfigurationValues() {
    let initial = HostingConfiguration {
        Text("A")
    }
    .background(.red)
    .margins(.init(top: 1, leading: 2, bottom: 3, trailing: 4))

    let updated = HostingConfiguration {
        Text("B")
    }
    .background(.blue)
    .margins(.init(top: 5, leading: 6, bottom: 7, trailing: 8))

    let view = HostingContentView(configuration: initial)
    #expect(view.backgroundColor == .red)
    #expect(view.directionalLayoutMargins == .init(top: 1, leading: 2, bottom: 3, trailing: 4))

    view.configuration = updated

    #expect(view.backgroundColor == .blue)
    #expect(view.directionalLayoutMargins == .init(top: 5, leading: 6, bottom: 7, trailing: 8))
}

@MainActor
@Test func hostingContentViewSizeThatFitsNeverReturnsZero() {
    let config = HostingConfiguration {
        Text("")
    }
    let view = HostingContentView(configuration: config)
    let size = view.sizeThatFits(.zero)

    #expect(size.width >= 1)
    #expect(size.height >= 1)
}

@Test func hostingConfigurationUpdatedForStatePreservesValues() {
    let base = HostingConfiguration {
        Text("State")
    }
    .background(.orange)
    .margins(.init(top: 9, leading: 8, bottom: 7, trailing: 6))

    let state = UICellConfigurationState(traitCollection: .current)
    let updated = base.updated(for: state)

    #expect(updated.backgroundColor == .orange)
    #expect(updated.margins == .init(top: 9, leading: 8, bottom: 7, trailing: 6))
}

@MainActor
@Test func hostingContentViewApplyCellStateTriggersRebuild() {
    var renderCount = 0
    let config = HostingConfiguration<Text>(stateAware: { _ in
        renderCount += 1
        return Text("Count \(renderCount)")
    })
    let view = HostingContentView(configuration: config)
    let before = renderCount

    let state = UICellConfigurationState(traitCollection: .current)
    view.apply(cellState: state)

    #expect(renderCount > before)
}

@MainActor
@Test func customStyleStoresProvidedLayoutInstance() {
    let layout = UICollectionViewFlowLayout()
    let style = CollectionViewStyle.custom(layout)

    if case let .custom(stored) = style {
        #expect(stored === layout)
    } else {
        Issue.record("Expected .custom case")
    }
}

#endif
