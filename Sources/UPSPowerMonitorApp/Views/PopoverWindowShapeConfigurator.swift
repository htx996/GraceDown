import AppKit
import SwiftUI

struct PopoverWindowShapeConfigurator: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        guard let contentView = window.contentView else {
            return
        }

        configureClearHierarchy(contentView)

        var parent = contentView.superview
        while let view = parent {
            configureClearContainer(view)
            parent = view.superview
        }
    }

    private func configureClearHierarchy(_ view: NSView) {
        configureClearContainer(view)
        for subview in view.subviews {
            configureClearHierarchy(subview)
        }
    }

    private func configureClearContainer(_ view: NSView) {
        if let visualEffectView = view as? NSVisualEffectView {
            visualEffectView.state = .inactive
            visualEffectView.material = .windowBackground
        }

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
