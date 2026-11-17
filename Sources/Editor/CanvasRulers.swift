import SwiftUI

struct CanvasLayout {
    static let ruler: CGFloat = 32
    static let boardTop: CGFloat = 100
    private static let horizontalMargin: CGFloat = 48
    private static let bottomMargin: CGFloat = 32
    private static let flowGap: CGFloat = 96

    let scale: CGFloat
    let board: CGSize
    let first: CGPoint
    let second: CGPoint

    init(window: CGSize, device: CGSize, zoom: CanvasZoom, flow: Bool) {
        let ruler = Self.ruler
        let area = CGSize(
            width: max(1, window.width - ruler),
            height: max(1, window.height - ruler)
        )
        let gap: CGFloat = flow ? Self.flowGap : 0
        let count: CGFloat = flow ? 2 : 1

        let widthFit = (area.width - gap - Self.horizontalMargin) / (device.width * count)
        let heightFit = (window.height - Self.boardTop - Self.bottomMargin) / device.height
        let fit = max(0.1, min(widthFit, heightFit, flow ? 0.64 : 0.76))
        scale = zoom.factor ?? fit
        board = CGSize(width: device.width * scale, height: device.height * scale)

        first = CGPoint(
            x: ruler + (area.width - board.width * count - gap) / 2,
            y: Self.boardTop
        )
        second = CGPoint(x: first.x + board.width + gap, y: first.y)
    }

    static func extent(for viewport: CGSize, device: CGSize, zoom: CanvasZoom, flow: Bool) -> CGSize {
        guard let scale = zoom.factor else { return viewport }
        let width = device.width * scale * (flow ? 2 : 1) + (flow ? flowGap : 0)
        let height = device.height * scale
        return CGSize(
            width: max(viewport.width, width + ruler + horizontalMargin),
            height: max(viewport.height, height + boardTop + bottomMargin)
        )
    }
}

struct CanvasRulers: View {
    let layout: CanvasLayout
    let palette: WorkbenchPalette

    var body: some View {
        Canvas { context, size in
            let inset = CanvasLayout.ruler
            let tickUnits = layout.scale < 0.33 ? 64 : 32
            let step = CGFloat(tickUnits) * layout.scale
            let horizontalTicks = ticks(origin: layout.first.x, step: step, from: inset, through: size.width)
            let verticalTicks = ticks(origin: layout.first.y, step: step, from: inset, through: size.height)

            for tick in horizontalTicks {
                draw(
                    from: CGPoint(x: tick.value, y: inset),
                    to: CGPoint(x: tick.value, y: size.height),
                    color: tick.index.isMultiple(of: 4) ? palette.majorGrid : palette.grid,
                    in: context
                )
            }
            for tick in verticalTicks {
                draw(
                    from: CGPoint(x: inset, y: tick.value),
                    to: CGPoint(x: size.width, y: tick.value),
                    color: tick.index.isMultiple(of: 4) ? palette.majorGrid : palette.grid,
                    in: context
                )
            }

            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: inset)), with: .color(palette.ruler))
            context.fill(Path(CGRect(x: 0, y: 0, width: inset, height: size.height)), with: .color(palette.ruler))
            draw(
                from: CGPoint(x: inset, y: 0), to: CGPoint(x: inset, y: size.height),
                color: palette.seam, in: context
            )
            draw(
                from: CGPoint(x: 0, y: inset), to: CGPoint(x: size.width, y: inset),
                color: palette.seam, in: context
            )
            let labelCenter: CGFloat = 12
            context.draw(label("pt"), at: CGPoint(x: inset / 2, y: labelCenter))

            for tick in horizontalTicks {
                let major = tick.index.isMultiple(of: 4)
                draw(
                    from: CGPoint(x: tick.value, y: inset - (major ? 9 : 4)),
                    to: CGPoint(x: tick.value, y: inset), color: palette.seam, in: context
                )
                if major && tick.value > inset + 16 && tick.value < size.width - 16 {
                    context.draw(label(String(tick.index * tickUnits)), at: CGPoint(x: tick.value, y: labelCenter))
                }
            }
            for tick in verticalTicks {
                let major = tick.index.isMultiple(of: 4)
                draw(
                    from: CGPoint(x: inset - (major ? 7 : 4), y: tick.value),
                    to: CGPoint(x: inset, y: tick.value), color: palette.seam, in: context
                )
                if major && tick.value > inset + 16 && tick.value < size.height - 16 {
                    var rotated = context
                    rotated.translateBy(x: labelCenter, y: tick.value)
                    rotated.rotate(by: .degrees(-90))
                    rotated.draw(label(String(tick.index * tickUnits)), at: .zero)
                }
            }
        }
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.muted)
    }

    private func ticks(
        origin: CGFloat, step: CGFloat, from lower: CGFloat, through upper: CGFloat
    ) -> [(index: Int, value: CGFloat)] {
        let start = Int(ceil((lower - origin) / step))
        let end = Int(floor((upper - origin) / step))
        guard start <= end else { return [] }
        return (start...end).map { ($0, origin + CGFloat($0) * step) }
    }

    private func draw(from: CGPoint, to: CGPoint, color: Color, in context: GraphicsContext) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: 0.65)
    }
}
