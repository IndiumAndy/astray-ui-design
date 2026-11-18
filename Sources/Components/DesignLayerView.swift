import SwiftUI

struct DesignLayerView: View {
    let layer: DesignLayer
    let size: CGSize
    let palette: IOSSamplePalette
    var spacing: CGFloat?

    var body: some View {
        let rect = CGRect(origin: .zero, size: size)
        Group {
            switch layer.kind {
            case .title:
                Text(layer.text)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .input:
                Text(layer.text)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(palette.cell, in: shape)
                    .overlay { shape.strokeBorder(palette.separator) }
            case .button:
                Text(layer.text)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(Color(workbenchHex: 0x005AC7), in: shape)
            case .setting:
                ZStack(alignment: .topLeading) {
                    shape.fill(palette.cell)
                    ForEach(layer.children) { child in
                        let frame = layer.childFrame(child, in: rect, spacing: spacing)
                        DesignLayerView(layer: child, size: frame.size, palette: palette)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            case .label:
                Text(layer.text)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .toggle:
                Capsule()
                    .fill(layer.isOn ? palette.switchOn : palette.separator)
                    .frame(width: 48, height: 28)
                    .overlay(alignment: layer.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                    }
                    .accessibilityLabel(layer.kind.name)
                    .accessibilityValue(layer.isOn ? "开启" : "关闭")
            }
        }
        .lineLimit(1)
        .foregroundStyle(palette.label)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8) }
}

struct DesignPagePreview: View {
    let page: DesignPage

    var body: some View {
        ZStack(alignment: .topLeading) {
            IOSArtboard { _ in Color.clear }
            ForEach(page.layers) { layer in
                PreviewLayer(layer: layer)
            }
        }
        .frame(width: page.bounds.width, height: page.bounds.height)
        .clipped()
    }
}

private struct PreviewLayer: View {
    @Environment(\.colorScheme) private var scheme
    let layer: DesignLayer

    var body: some View {
        DesignLayerView(layer: layer, size: layer.frame.size, palette: IOSSamplePalette(scheme: scheme))
            .position(x: layer.frame.midX, y: layer.frame.midY)
    }
}
