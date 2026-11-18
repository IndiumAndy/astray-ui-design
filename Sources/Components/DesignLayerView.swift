import AppKit
import SwiftUI

struct DesignLayerView: View {
    let layer: DesignLayer
    let size: CGSize
    let palette: IOSSamplePalette
    var spacing: CGFloat?
    var contacts: [DesignContact] = []
    var radius: CGFloat = 8

    private var appearance: ControlState { layer.behavior?.state ?? .normal }
    private var sample: DesignValue? {
        layer.behavior?.binding?.sample ?? layer.field.flatMap { field in contacts.first.map { .text($0[field]) } }
    }
    private var error: String? {
        appearance == .error ? layer.behavior?.stateMessage ?? "请检查此字段" : nil
    }
    private var toggleValue: Bool { sample?.flag ?? layer.isOn }

    var body: some View {
        let rect = CGRect(origin: .zero, size: size)
        Group {
            switch layer.kind {
            case .title:
                Text(sample?.text ?? layer.text)
                    .font(layer.field == .phone ? .system(size: 16) : .system(size: 28, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .input:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        if !layer.text.isEmpty && (layer.field != nil || layer.behavior?.binding != nil) {
                            Text(layer.text)
                        }
                        Text(layer.inputType == .password && sample?.text.isEmpty == false ? "••••••" :
                                sample?.text ?? (layer.behavior?.binding != nil ? "" : layer.text))
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .background(palette.cell, in: shape)
                            .overlay { shape.strokeBorder(error == nil ? palette.separator : palette.error) }
                    }
                    .font(.system(size: 16))
                    .lineLimit(1)
                    if let hint = error ?? layer.fieldHint, !hint.isEmpty {
                        Text(hint).foregroundStyle(error == nil ? palette.secondary : palette.error)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(palette.secondary)
            case .button:
                HStack(spacing: 8) {
                    if appearance == .busy { ProgressView().controlSize(.small).tint(.white) }
                    if appearance == .error { Image(systemName: "exclamationmark.circle") }
                    Text((appearance == .busy || appearance == .error ? layer.behavior?.stateMessage : nil) ?? layer.text)
                }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(layer.secondaryButton == true ? palette.label : .white)
                    .background(layer.secondaryButton == true ? palette.cell : Color(workbenchHex: 0x005AC7), in: shape)
                    .overlay { if layer.secondaryButton == true { shape.strokeBorder(palette.separator) } }
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
                Text(sample?.text ?? layer.text)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .toggle:
                Capsule()
                    .fill(toggleValue ? palette.switchOn : palette.separator)
                    .frame(width: 48, height: 28)
                    .overlay(alignment: toggleValue ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                    }
                    .accessibilityLabel(layer.kind.name)
                    .accessibilityValue(toggleValue ? "开启" : "关闭")
            case .layout, .labeledInput, .listRow, .actionBar:
                Color.clear.overlay {
                    if layer.children.isEmpty {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(palette.separator, style: StrokeStyle(dash: [4, 4]))
                        Text("拖入组件").font(.system(size: 13)).foregroundStyle(palette.secondary)
                    }
                }
            case .divider:
                palette.separator
            case .image:
                if let data = layer.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().accessibilityLabel(layer.text)
                } else {
                    Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(palette.cell, in: shape)
                }
            case .contactList:
                listPreview
            }
        }
        .foregroundStyle(palette.label)
        .opacity(appearance == .disabled ? 0.55 : 1)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder private var listPreview: some View {
        let list = layer.behavior?.list ?? ListDesign()
        let legacy = contacts.map { DesignRecord(id: $0.id, fields: ["name": .text($0.name), "phone": .text($0.phone)]) }
        let content = layer.behavior?.list?.sample ?? ListContent(rows: legacy)
        if content.resolvedState == .ready {
            VStack(spacing: 0) {
                let height = CGFloat(list.rowHeight ?? 56)
                ForEach(content.rows.prefix(max(1, Int(ceil(size.height / height))))) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.fields[list.titleKey]?.text ?? "").font(.system(size: 16, weight: .medium))
                            if let detail = record.fields[list.detailKey]?.text, !detail.isEmpty {
                                Text(detail).font(.system(size: 13)).foregroundStyle(palette.secondary)
                            }
                        }
                        Spacer()
                        if layer.behavior?.action != nil || layer.destination != nil {
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(palette.secondary)
                        }
                    }
                    .frame(height: height)
                    .overlay(alignment: .bottom) { palette.separator.frame(height: 1) }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if content.resolvedState == .loading { ProgressView().controlSize(.small) }
                    if content.resolvedState == .failed { Image(systemName: "exclamationmark.circle").foregroundStyle(palette.error) }
                    Text(list.message(for: content)).foregroundStyle(palette.secondary)
                }
                if content.resolvedState == .empty, list.emptyAction != nil, !list.emptyButton.isEmpty {
                    Text(list.emptyButton).foregroundStyle(Color(workbenchHex: 0x005AC7))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius) }
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
