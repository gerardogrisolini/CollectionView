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

@MainActor
@Test func layoutSignatureChangesAcrossStylesAndParameters() {
    let sut = CollectionView([1]) { value in
        Text("\(value)")
    }

    let list = sut.layoutSignature(for: .list)
    let grid = sut.layoutSignature(for: .grid(numOfColumns: 2, heightOfRow: 44, spacing: 8))
    let carouselA = sut.layoutSignature(for: .carousel(layout: .three, spacing: 8, padding: 8, pageControl: .minimal(.orange), ignoreSafeArea: false))
    let carouselB = sut.layoutSignature(for: .carousel(layout: .three, spacing: 10, padding: 8, pageControl: .minimal(.orange), ignoreSafeArea: false))

    #expect(list != grid)
    #expect(carouselA != carouselB)
}

@MainActor
@Test func adjustedInsetOnlyChangesForCarouselIgnoringSafeArea() {
    let sut = CollectionView([1]) { value in
        Text("\(value)")
    }
    let base = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)

    let unchanged = sut.adjustedContentInset(base: base, style: .list, safeAreaTop: 10)
    #expect(unchanged == base)

    let adjusted = sut.adjustedContentInset(
        base: base,
        style: .carousel(layout: .one, spacing: 8, padding: 0, pageControl: nil, ignoreSafeArea: true),
        safeAreaTop: 12
    )
    #expect(adjusted.top == -12)
    #expect(adjusted.bottom == -12)
    #expect(adjusted.left == base.left)
    #expect(adjusted.right == base.right)
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
#endif
