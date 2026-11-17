import SwiftUI

struct ReviewCanvas: View {
    let state: ReviewState
    let device: ReviewDevice
    let zoom: CanvasZoom
    let arrangement: ReviewArrangement
    let preview: PreviewPlacement
    let palette: WorkbenchPalette
    let dismissPreview: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let extent = CanvasLayout.extent(
                for: viewport, device: device.size, zoom: zoom, flow: state == .flow,
                trailingClearance: preview.canvasClearance
            )
            let layout = CanvasLayout(
                window: extent, device: device.size, zoom: zoom, flow: state == .flow,
                trailingClearance: preview.canvasClearance
            )
            Group {
                if extent == viewport {
                    contents(using: layout)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        contents(using: layout)
                            .frame(width: extent.width, height: extent.height)
                    }
                }
            }
            .overlay(alignment: preview.isCentered ? .center : .topTrailing) {
                if let width = preview.width {
                    previewWindow(width: width, viewport: viewport)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画布")
    }

    private func previewWindow(width: CGFloat, viewport: CGSize) -> some View {
        let top = preview.isCentered ? 0 : CanvasLayout.boardTop - PhonePreview.screenTop
        let availableHeight = viewport.height - top - PreviewPlacement.edgeInset * 2
        return PhonePreview(
            state: state, device: device, arrangement: arrangement, width: width,
            availableHeight: availableHeight, palette: palette, close: dismissPreview
        )
        .padding(.trailing, preview.isCentered ? 0 : PreviewPlacement.edgeInset)
        .padding(.top, top)
    }

    private func contents(using layout: CanvasLayout) -> some View {
        ZStack(alignment: .topLeading) {
            CanvasRulers(layout: layout, palette: palette)
                .accessibilityHidden(true)

            switch state {
            case .blank:
                board("页面 1", at: layout.first, layout: layout) {
                    DevicePage(size: device.size, scale: layout.scale) {
                        IOSArtboard { _ in Color.clear }
                    }
                    .overlay {
                        BlankArtboard(palette: palette)
                            .padding(.top, (IOSLayout.statusHeight - IOSLayout.homeHeight) * layout.scale)
                    }
                }
            case .selection:
                board("设置", at: layout.first, layout: layout) {
                    DevicePage(size: device.size, scale: layout.scale) {
                        IOSArtboard { SettingsSample(palette: $0, arrangement: arrangement) }
                    }
                    .overlay(alignment: .topLeading) {
                        selection(layout)
                    }
                    .accessibilityRepresentation {
                        Text("设置画板，已选中消息通知组合")
                            .accessibilityAddTraits(.isSelected)
                    }
                }
            case .flow:
                board("联系人列表", at: layout.first, layout: layout) {
                    DevicePage(size: device.size, scale: layout.scale) {
                        IOSArtboard { ContactsSample(palette: $0) }
                    }
                    .accessibilityHidden(true)
                }
                board("联系人详情", at: layout.second, layout: layout) {
                    DevicePage(size: device.size, scale: layout.scale) {
                        IOSArtboard { ContactDetailSample(palette: $0) }
                    }
                    .accessibilityHidden(true)
                }
                FlowLink(layout: layout, palette: palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
        .clipped()
    }

    private func board<Content: View>(
        _ title: String, at origin: CGPoint, layout: CanvasLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    boardTitle(title).fixedSize()
                    Spacer(minLength: 8)
                    boardDimensions.fixedSize()
                }
                VStack(alignment: .leading, spacing: 0) {
                    boardTitle(title)
                    boardDimensions.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: layout.board.width, height: 32)

            content()
                .frame(width: layout.board.width, height: layout.board.height)
                .background {
                    Rectangle()
                        .fill(palette.field)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 2)
                }
                .overlay { Rectangle().strokeBorder(palette.artboardSeam, lineWidth: 0.5).allowsHitTesting(false) }
        }
        .position(x: origin.x + layout.board.width / 2, y: origin.y + (layout.board.height - 32) / 2)
    }

    private func boardTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
    }

    private var boardDimensions: some View {
        Text(device.dimensions)
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(palette.measure)
            .lineLimit(1)
    }

    private func selection(_ layout: CanvasLayout) -> some View {
        let bounds = SettingsSample.selectedBounds(for: device, arrangement: arrangement)
        let outset = SelectionOutline.outset
        let width = bounds.width * layout.scale
        let height = bounds.height * layout.scale
        return SelectionOutline(palette: palette)
            .frame(width: width + outset * 2, height: height + outset * 2)
            .offset(x: bounds.minX * layout.scale - outset, y: bounds.minY * layout.scale - outset)
            .accessibilityHidden(true)
    }
}

struct DevicePage<Content: View>: View {
    let size: CGSize
    let scale: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }
}

private struct BlankArtboard: View {
    let palette: WorkbenchPalette

    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(palette.muted.opacity(0.52), style: StrokeStyle(dash: [3, 4]))
                    }
                    .accessibilityHidden(true)
                Text("从左侧拖入组件")
                    .font(.system(size: 13))
                    .fixedSize()
            }
            .padding(8)

            Text("拖入组件")
                .font(.system(size: 12))
        }
        .foregroundStyle(palette.secondary)
    }
}

private struct SelectionOutline: View {
    let palette: WorkbenchPalette
    static let outset: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: Self.outset, dy: Self.outset)
            context.stroke(Path(rect), with: .color(palette.accent), lineWidth: 1.5)
            for point in [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
            ] {
                let handle = Path(CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                context.fill(handle, with: .color(palette.field))
                context.stroke(handle, with: .color(palette.accent), lineWidth: 1.25)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FlowLink: View {
    let layout: CanvasLayout
    let palette: WorkbenchPalette

    var body: some View {
        let start = CGPoint(
            x: layout.first.x + layout.board.width - IOSLayout.pageInset * layout.scale,
            y: layout.first.y + ContactsSample.firstRowCenter * layout.scale
        )
        let end = CGPoint(x: layout.second.x, y: layout.second.y + 136 * layout.scale)
        let control = (end.x - start.x) * 0.48
        let labelX = (layout.first.x + layout.board.width + end.x) / 2

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var curve = Path()
                curve.move(to: start)
                curve.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + control, y: start.y),
                    control2: CGPoint(x: end.x - control, y: end.y)
                )
                context.stroke(curve, with: .color(palette.accent), lineWidth: 2)

                let port = Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6))
                context.fill(port, with: .color(.white))
                context.stroke(port, with: .color(palette.accent), lineWidth: 1.25)

                var arrow = Path()
                arrow.move(to: CGPoint(x: end.x - 6, y: end.y - 4))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x - 6, y: end.y + 4))
                context.stroke(arrow, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .accessibilityHidden(true)
            Text("点按列表行")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(palette.field, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                .position(x: labelX, y: min(start.y, end.y) - 13)
                .accessibilityLabel("点按列表中的联系人，打开联系人详情")
        }
        .allowsHitTesting(false)
    }
}
