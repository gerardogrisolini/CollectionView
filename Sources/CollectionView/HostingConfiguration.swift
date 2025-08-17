//
//  HostingConfiguration.swift
//  EsselungaIST
//
//  Created by Gerardo Grisolini on 14/08/25.
//


import UIKit
import SwiftUI

/// iOS 15-compatible replacement for UIHostingConfiguration.
/// Usage:
/// cell.contentConfiguration = HostingConfiguration { MyRow(model: model) }
@available(iOS 14.0, *)
public struct HostingConfiguration<Content: View>: UIContentConfiguration {
    public var makeView: (UIConfigurationState) -> Content
    public var backgroundColor: UIColor?
    public var margins: NSDirectionalEdgeInsets = .zero

    public init(_ makeView: @escaping () -> Content) {
        self.makeView = { _ in makeView() }
    }

    /// State-aware init, e.g. to react to selection/highlight.
    public init(stateAware: @escaping (UIConfigurationState) -> Content) {
        self.makeView = stateAware
    }

    public func makeContentView() -> UIView & UIContentView {
        HostingContentView(configuration: self)
    }

    public func updated(for state: UIConfigurationState) -> HostingConfiguration {
        // Nothing to mutate by default; callers can create state-aware views using `stateAware` init.
        self
    }

    // Convenience modifiers (mimic UIHostingConfiguration API style)
    public func background(_ color: UIColor?) -> HostingConfiguration {
        var copy = self
        copy.backgroundColor = color
        return copy
    }

    public func margins(_ insets: NSDirectionalEdgeInsets) -> HostingConfiguration {
        var copy = self
        copy.margins = insets
        return copy
    }
}

// MARK: - ContentView

@available(iOS 14.0, *)
final class HostingContentView<Content: View>: UIView, UIContentView {

    // Required by UIContentView
    var configuration: UIContentConfiguration {
        didSet {
            guard let config = configuration as? HostingConfiguration<Content> else { return }
            apply(configuration: config)
        }
    }

    private var hostingController: UIHostingController<AnyView>!
    private var hostingView: UIView { hostingController.view }
    private var currentState = UICellConfigurationState(traitCollection: UITraitCollection.current)

    init(configuration: HostingConfiguration<Content>) {
        self.configuration = configuration
        super.init(frame: .zero)
        isOpaque = false
        setupHostingController()
        apply(configuration: configuration)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupHostingController() {
        hostingController = UIHostingController(rootView: AnyView(EmptyView()))
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.backgroundColor = .clear
        addSubview(hostingController.view)
    }

    private func apply(configuration: HostingConfiguration<Content>) {
        directionalLayoutMargins = configuration.margins
        backgroundColor = configuration.backgroundColor

        // Build the SwiftUI view (optionally state-aware)
        let view = configuration.makeView(currentState)
        hostingController.rootView = AnyView(view)
        setNeedsLayout()
    }

    // MARK: - State propagation

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachToNearestViewControllerIfNeeded()
    }

    private func attachToNearestViewControllerIfNeeded() {
        // Embed HC into nearest parent VC so SwiftUI environment gets lifecycle.
        guard hostingController.parent == nil else { return }
        guard let vc = nearestViewController() else { return }
        vc.addChild(hostingController)
        hostingController.didMove(toParent: vc)
    }

    private func nearestViewController() -> UIViewController? {
        sequence(first: next, next: { $0?.next })
            .compactMap { $0 as? UIViewController }
            .first
    }

    // Let the cell tell us about selection/highlight state
    func apply(cellState: UICellConfigurationState) {
        currentState = cellState
        if let config = configuration as? HostingConfiguration<Content> {
            apply(configuration: config)
        }
    }

    // MARK: - Sizing

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        // Let SwiftUI size itself.
        let size = hostingController.sizeThatFits(in: targetSize)
        // Fallback in case SwiftUI returns zero
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        systemLayoutSizeFitting(size)
    }
}

