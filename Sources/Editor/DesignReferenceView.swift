import AppKit
import SwiftUI

struct DesignReferenceView: View {
    let page: DesignPage
    let offset: CGPoint?
    let palette: WorkbenchPalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let reference = page.referenceImage, !reference.isHidden {
                ReferenceBitmap(data: reference.data)
                    .frame(width: page.size.width, height: page.size.height)
                    .offset(x: (offset ?? reference.offset).x, y: (offset ?? reference.offset).y)
                    .opacity(reference.opacity)
            }
            if let reference = page.reference {
                Canvas { context, _ in
                    for guide in reference.guides(in: page) {
                        context.stroke(Path(roundedRect: guide, cornerRadius: 6),
                                       with: .color(palette.measure.opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                    for x in [reference.inset, page.size.width - reference.inset] {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: page.safeTop))
                        path.addLine(to: CGPoint(x: x, y: page.size.height - page.safeBottom))
                        context.stroke(path, with: .color(palette.measure.opacity(0.42)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReferenceBitmap: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
        }
        .onChange(of: data, initial: true) { _, data in image = NSImage(data: data) }
    }
}
