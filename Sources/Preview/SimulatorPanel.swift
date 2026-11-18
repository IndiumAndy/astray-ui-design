import AppKit
import SwiftUI

struct SimulatorPanel: View {
    let simulator: SimulatorPreview
    let width: CGFloat
    let height: CGFloat
    let palette: WorkbenchPalette
    let close: () -> Void

    var body: some View {
        let device = SimulatorPreview.screen
        let scale = max(0.1, min((width - 24) / device.width, (height - 52) / device.height))
        VStack(spacing: 0) {
            HStack {
                Text("iPhone 17 Pro").font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("收起 iPhone 模拟器")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 32)
            .overlay(alignment: .bottom) { palette.groupSeam.frame(height: 1) }
            SimulatorScreen(simulator: simulator, palette: palette)
                .frame(width: device.width * scale, height: device.height * scale)
                .clipShape(.rect(cornerRadius: 16))
                .padding(2)
                .background(palette.ink, in: .rect(cornerRadius: 18))
                .padding(8)
        }
        .frame(width: width)
        .background(palette.panel, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.fieldSeam).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iPhone 模拟器")
    }
}

private struct SimulatorScreen: View {
    let simulator: SimulatorPreview
    let palette: WorkbenchPalette

    var body: some View {
        ZStack {
            palette.field
            if let frame = simulator.frame {
                SimulatorInput(simulator: simulator, image: frame)
                if let issue = simulator.issue {
                    Text(issue.text.components(separatedBy: "\n")[0])
                        .font(.system(size: 12)).padding(8)
                        .background(palette.panel, in: .rect(cornerRadius: 8))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: 12) {
                    if let issue = simulator.issue {
                        Text(issue.text)
                            .font(.system(size: 12)).lineLimit(6).multilineTextAlignment(.center)
                        Button("重试") { Task { await simulator.retry() } }
                    } else if let status = simulator.status {
                        ProgressView().controlSize(.small)
                        Text(status).font(.system(size: 12))
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct SimulatorInput: NSViewRepresentable {
    let simulator: SimulatorPreview
    let image: CGImage

    func makeNSView(context: Context) -> InputView { InputView(simulator: simulator) }

    func updateNSView(_ view: InputView, context: Context) {
        view.image = NSImage(cgImage: image, size: SimulatorPreview.screen)
        view.needsDisplay = true
    }

    final class InputView: NSView, @preconcurrency NSTextInputClient {
        private let simulator: SimulatorPreview
        private var downPoint: CGPoint?
        private var scrollStart: CGPoint?
        private var scrollDistance: CGFloat = 0
        private var scrollTask: Task<Void, Never>?
        private var marked: NSAttributedString?
        var image: NSImage?

        init(simulator: SimulatorPreview) {
            self.simulator = simulator
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityLabel("模拟器屏幕")
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill() }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            downPoint = point(event)
        }

        override func mouseUp(with event: NSEvent) {
            guard let downPoint else { return }
            simulator.touch(from: downPoint, to: point(event))
            self.downPoint = nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            if scrollStart == nil { scrollStart = point(event) }
            scrollDistance += event.scrollingDeltaY
            scrollTask?.cancel()
            scrollTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(70)) }
                catch { return }
                guard let self, let start = self.scrollStart else { return }
                self.scrollStart = nil
                let distance = self.scrollDistance
                self.scrollDistance = 0
                guard abs(distance) >= 2 else { return }
                let end = CGPoint(x: start.x, y: min(873, max(0, start.y + distance * 3)))
                self.simulator.touch(from: start, to: end)
            }
        }

        override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.modifierFlags.contains(.command) else { return false }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": simulator.shortcut(4)
            case "v": if let text = NSPasteboard.general.string(forType: .string) { simulator.characters(text) }
            case "z": simulator.shortcut(29)
            default: return false
            }
            return true
        }

        override func doCommand(by command: Selector) {
            let usage: UInt16? = switch NSStringFromSelector(command) {
            case "deleteBackward:": 42
            case "deleteForward:": 76
            case "insertNewline:": 40
            case "insertTab:": 43
            case "cancelOperation:": 41
            case "moveLeft:": 80
            case "moveRight:": 79
            case "moveUp:": 82
            case "moveDown:": 81
            default: nil
            }
            if let usage { simulator.key(usage) }
        }

        func insertText(_ string: Any, replacementRange: NSRange) {
            marked = nil
            if let text = string as? String { simulator.characters(text) }
            else if let text = string as? NSAttributedString { simulator.characters(text.string) }
        }

        func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            marked = (string as? NSAttributedString) ?? (string as? String).map(NSAttributedString.init(string:))
        }

        func unmarkText() { marked = nil }
        func hasMarkedText() -> Bool { marked != nil }
        func markedRange() -> NSRange { marked.map { NSRange(location: 0, length: $0.length) } ?? NSRange(location: NSNotFound, length: 0) }
        func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
        func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
        func characterIndex(for point: NSPoint) -> Int { NSNotFound }

        func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
            let anchor = NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 16)
            return window?.convertToScreen(convert(anchor, to: nil)) ?? .zero
        }

        private func point(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            let device = SimulatorPreview.screen
            return CGPoint(x: min(device.width - 1, max(0, local.x / max(1, bounds.width) * device.width)),
                           y: min(device.height - 1, max(0, local.y / max(1, bounds.height) * device.height)))
        }
    }
}
