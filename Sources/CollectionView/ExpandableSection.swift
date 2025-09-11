//
//  ExpandableSection.swift
//  CollectionView
//
//  Created by Gerardo Grisolini on 11/09/25.
//

/// Controls the expand/collapse behavior of a section when using section snapshots.
/// Use `.none` to disable expandability for a section.
public enum ExpandableSection {
    case none
    case expanded
    case collapsed
}
