import AppKit
import SwiftUI

// Align the existing NSWindow buttons with the workbench toolbar.
struct WindowControlsAlignment: NSViewRepresentable {
    let attachDocument: (NSDocument) -> Void

    func makeNSView(context: Context) -> Anchor { Anchor(attachDocument: attachDocument) }
    func updateNSView(_ view: Anchor, context: Context) { view.attachDocument = attachDocument }

    final class Anchor: NSView {
        var attachDocument: (NSDocument) -> Void

        init(attachDocument: @escaping (NSDocument) -> Void) {
            self.attachDocument = attachDocument
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self)
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(alignControls), name: NSWindow.didResizeNotification, object: window)
            center.addObserver(self, selector: #selector(alignControls), name: NSWindow.didExitFullScreenNotification, object: window)
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.alignControls()
                if let document = window.windowController?.document as? NSDocument {
                    self.attachDocument(document)
                }
            }
        }

        @objc private func alignControls() {
            guard let window, let content = window.contentView,
                  !window.styleMask.contains(.fullScreen) else { return }

            let toolbarCenter = WorkbenchLayout.toolbarHeight / 2
            let y = content.isFlipped ? content.bounds.minY + toolbarCenter : content.bounds.maxY - toolbarCenter
            var x = content.bounds.minX + 16
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type), let container = button.superview else { continue }
                let size = button.frame.size
                let target = container.convert(CGPoint(x: x + size.width / 2, y: y), from: content)
                button.setFrameOrigin(CGPoint(x: target.x - size.width / 2, y: target.y - size.height / 2))
                x += size.width + 8
            }
        }
    }
}
