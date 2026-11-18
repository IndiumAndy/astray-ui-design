import AppKit
import SwiftUI

struct Workbench: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Bindable var session: ReviewSession
    let title: String

    private var palette: WorkbenchPalette { WorkbenchPalette(appearance, contrast) }

    var body: some View {
        GeometryReader { window in
            let layout = WorkbenchLayout(window: window.size, session: session)

            VStack(spacing: 0) {
                WorkbenchToolbar(session: session, layout: layout, palette: palette, title: title)
                    .frame(height: WorkbenchLayout.toolbarHeight)
                palette.seam.frame(height: WorkbenchLayout.separatorWidth)

                HStack(spacing: 0) {
                    if session.libraryVisible {
                        ComponentLibrary(palette: palette, session: session)
                            .frame(width: layout.sidebarWidth)
                        palette.seam.frame(width: WorkbenchLayout.separatorWidth)
                    }

                    Group {
                        if let editor = session.editor {
                            DesignCanvas(editor: editor, zoom: session.zoom, snapEnabled: session.snapEnabled,
                                         preview: layout.preview, palette: palette,
                                         inspectorInset: layout.inspectorWidth == 0 ? 0 : layout.inspectorWidth + WorkbenchLayout.separatorWidth,
                                         dismissPreview: { session.previewVisible = false })
                        } else {
                            ReviewCanvas(
                                state: session.state, device: session.device, zoom: session.zoom,
                                arrangement: session.arrangement, preview: layout.preview, palette: palette,
                                dismissPreview: { session.previewVisible = false }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    if session.trailingPaneVisible {
                        palette.seam.frame(width: WorkbenchLayout.separatorWidth)
                        inspector
                            .frame(width: layout.inspectorWidth)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(alignment: .leading) {
                if session.libraryVisible {
                    sidebarBackground
                        .frame(width: layout.sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(palette.panel)
        }
        .foregroundStyle(palette.ink)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if reduceTransparency {
            palette.panel
        } else {
            SidebarMaterial()
                .overlay(palette.sidebarTint)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let editor = session.editor, let selection = editor.selection {
            DesignInspector(editor: editor, layer: selection.layer, parent: selection.parent, palette: palette)
                .id(selection.layer.id)
        } else if session.state == .selection {
            SelectionInspector(device: session.device, palette: palette, arrangement: $session.arrangement)
        } else {
            Text("未选择图层")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("属性检查器，未选择图层")
        }
    }
}

struct WorkbenchLayout {
    static let toolbarHeight: CGFloat = 40
    static let separatorWidth: CGFloat = 1
    static let navigatorWidth: CGFloat = 228
    static let propertiesWidth: CGFloat = 272
    static let windowControlsClearance: CGFloat = 86
    static let closedNavigatorToolbarWidth: CGFloat = 124
    static let closedInspectorToolbarWidth: CGFloat = 44

    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    let preview: PreviewPlacement
    let canvasScale: CGFloat
    let canvasWidth: CGFloat

    @MainActor
    init(window: CGSize, session: ReviewSession) {
        sidebarWidth = session.libraryVisible ? Self.navigatorWidth : 0
        inspectorWidth = session.trailingPaneVisible ? Self.propertiesWidth : 0
        let sideSeams: CGFloat = (session.libraryVisible ? Self.separatorWidth : 0)
            + (session.trailingPaneVisible ? Self.separatorWidth : 0)
        let viewport = CGSize(
            width: max(1, window.width - sidebarWidth - inspectorWidth - sideSeams),
            height: max(1, window.height - Self.toolbarHeight - Self.separatorWidth)
        )
        canvasWidth = viewport.width
        let flow = session.state == .flow
        preview = PreviewPlacement(viewport: viewport, visible: session.previewVisible, flow: flow)
        canvasScale = CanvasLayout(
            window: viewport, device: session.device.size, zoom: session.zoom,
            flow: flow, trailingClearance: preview.canvasClearance,
            magnification: session.editor?.magnification
        ).scale
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        return material
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
