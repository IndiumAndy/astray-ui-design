import SwiftUI

struct RuntimeScreen: View {
    let page: RuntimePage
    let runtime: ContactRuntime
    let route: ContactRuntime.Route
    let isLive: Bool
    let isPushed: Bool
    let inPanel: Bool
    let onSaveContact: (ContactSave) -> Void
    let onAction: (DesignEvent) -> DesignActionResult
    @FocusState private var focusedField: String?
    @State private var scrollTarget: String?

    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = page.adaptive == true ? proxy.size.width : min(page.width, proxy.size.width)
            let top = (page.contentTop ?? 56) + (route.contact != nil && page.adaptive != true ? 48 : 0)
            let measured = measuredPage(width: width)
            let layout = ScreenLayout(page: measured, width: width, height: proxy.size.height + top, top: top,
                                      device: UIDevice.current.userInterfaceIdiom == .phone ? .phone : DeviceLayout(width: width),
                                      textScale: textScale)
            let lookup = Dictionary(uniqueKeysWithValues: page.layers.map { ($0.id, $0) })
            let layers = layout.renderOrder.compactMap { lookup[$0] }
            let components = RuntimeComponents(runtime: runtime, route: route, layout: layout,
                                               inPanel: inPanel, focus: $focusedField,
                                               onSaveContact: onSaveContact, onAction: onAction) { id in
                if let id { scrollTarget = id }
            }
            VStack(spacing: 0) {
                if layout.headerHeight > 0 {
                    band(.header, height: layout.headerHeight, width: width, layers: layers, components: components)
                        .background(.background)
                        .zIndex(1)
                }
                ScrollViewReader { scrolling in
                    ScrollView {
                        band(.body, height: layout.bodyHeight, width: width, layers: layers, components: components)
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: scrollTarget) { _, id in
                        guard let id else { return }
                        scrolling.scrollTo(id, anchor: .center)
                        focusedField = id
                        scrollTarget = nil
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                if layout.footerHeight > 0 {
                    band(.footer, height: layout.footerHeight, width: width, layers: layers, components: components)
                        .background(.background)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle((isPushed || inPanel) && page.layers.contains(where: { $0.kind == "title" }) ? "" : page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(isPushed || inPanel ? .visible : .hidden, for: .navigationBar)
    }

    private func measuredPage(width: CGFloat) -> RuntimePage {
        var measured = page
        measured.layers = page.layers.map { layer in
            var layer = layer
            if layer.kind == "contactList" {
                let content = runtime.content(layer)
                layer.contentMinimum = content.resolvedState == .ready ? CGFloat(content.rows.count * (layer.behavior?.list?.rowHeight ?? 56)) * max(1, textScale) : nil
                if content.resolvedState == .empty && layer.behavior?.list?.emptyAction != nil { layer.contentMinimum = 88 }
            }
            if layer.kind == "input", let message = runtime.error(layer, route) {
                layer.fieldHint = message
                let rowHeight = max(44, ceil(16 * 1.3 * textScale) + 16)
                let length = CGFloat(message.count) * 12 * textScale
                layer.contentMinimum = rowHeight + 4 + max(1, ceil(length / max(1, min(width, layer.width)))) * 16 * textScale
            }
            return layer
        }
        return measured
    }

    private func band(_ region: LayoutRegion, height: CGFloat, width: CGFloat, layers: [RuntimeLayer],
                      components: RuntimeComponents) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(layers.filter { components.layout.items[$0.id]?.region == region && (!$0.isContainer || $0.isActionRow) }) { layer in
                Group {
                    if isLive { components.layer(layer) }
                    else { GeneratedPages.control(layer, components: components) }
                }
                .id(layer.id)
                .zIndex(layer.kind == "listRow" ? 1 : 0)
            }
        }
        .frame(width: width, height: height)
    }
}

@MainActor struct RuntimeComponents {
    let runtime: ContactRuntime
    let route: ContactRuntime.Route
    let layout: ScreenLayout
    let inPanel: Bool
    let focus: FocusState<String?>.Binding
    let onSaveContact: (ContactSave) -> Void
    let onAction: (DesignEvent) -> DesignActionResult
    let requestFocus: (String?) -> Void

    private var errorColor: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 1, green: 172 / 255, blue: 168 / 255, alpha: 1)
            }
            return UIColor(red: 163 / 255, green: 36 / 255, blue: 32 / 255, alpha: 1)
        })
    }

    @ViewBuilder func layer(_ layer: RuntimeLayer) -> some View {
        switch layer.kind {
        case "title": title(layer)
        case "input": field(layer)
        case "button": button(layer)
        case "contactList": contacts(layer)
        case "listRow": row(layer)
        case "setting": setting(layer)
        case "label": label(layer)
        case "toggle": toggle(layer)
        case "divider": divider(layer)
        case "image": image(layer)
        default: EmptyView()
        }
    }

    func title(_ layer: RuntimeLayer) -> some View {
        place(layer) {
            if layer.field == .phone {
                Text(runtime.display(layer, route: route)).font(.body).foregroundStyle(Color.primary.opacity(0.72))
            } else {
                Text(runtime.display(layer, route: route)).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
        }
    }

    func field(_ layer: RuntimeLayer) -> some View {
        place(layer) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if layer.field != nil || layer.behavior?.binding != nil && layer.inputLabel == nil {
                        Text(layer.text).font(.body).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    let accessName = layer.inputLabel ?? (layer.text.isEmpty ? layer.field?.title ?? "输入框" : layer.text)
                    let prompt = layer.field == nil && layer.behavior?.binding == nil ? Text(layer.text) : Text("")
                    let binding = runtime.value(layer, route: route, onAction: onAction)
                    Group {
                        if layer.inputType == "password" {
                            SecureField(accessName, text: binding, prompt: prompt)
                        } else {
                            TextField(accessName, text: binding, prompt: prompt)
                                .keyboardType(layer.inputType == "email" ? .emailAddress : .default)
                                .textInputAutocapitalization(layer.inputType == "email" ? .never : .sentences)
                        }
                    }
                    .focused(focus, equals: layer.id)
                    .disabled(runtime.state(layer).blocksInput)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(
                            focus.wrappedValue == layer.id ? .accentColor : runtime.error(layer, route) != nil ? errorColor : Color(uiColor: .separator),
                            lineWidth: focus.wrappedValue == layer.id ? 1.5 : 1)
                    }
                    .accessibilityLabel(accessName)
                    .accessibilityHint(runtime.error(layer, route) ?? layer.fieldHint ?? "")
                    .accessibilityIdentifier(layer.field?.rawValue ?? layer.id)
                    .onSubmit {
                        guard let form = layer.behavior?.form,
                              let button = runtime.design?.pages.first(where: { $0.id == route.page })?.layers.first(where: {
                                  $0.behavior?.action?.kind == .submit && $0.behavior?.action?.form == form
                                      && !runtime.state($0).blocksInput
                              }), let action = button.behavior?.action else { return }
                        invoke(action, layer: button)
                    }
                }
                if let hint = runtime.error(layer, route) ?? layer.fieldHint, !hint.isEmpty {
                    Text(hint).font(.caption).foregroundStyle(runtime.error(layer, route) == nil ? Color.secondary : errorColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func invoke(_ action: DesignAction, layer: RuntimeLayer) {
        requestFocus(runtime.perform(action, layer: layer, route: route, inPanel: inPanel, order: layout.renderOrder, onAction: onAction))
    }

    func saveContact() { runtime.save(route, onSave: onSaveContact) }

    func button(_ layer: RuntimeLayer, legacy: (() -> Void)? = nil) -> some View {
        let state = runtime.state(layer)
        return place(layer) {
            Button {
                if let action = layer.behavior?.action { invoke(action, layer: layer) }
                else if let legacy { legacy() }
                else if layer.savesContact == true { saveContact() }
            } label: {
                HStack(spacing: 8) {
                    if state == .busy { ProgressView().tint(layer.secondaryButton == true ? .primary : .white) }
                    if state == .error { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                    Text((state == .busy || state == .error ? layer.behavior?.stateMessage : nil) ?? layer.text)
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(ContactButtonStyle(radius: layer.cornerRadius ?? 8, isSecondary: layer.secondaryButton == true))
            .disabled(state.blocksInput)
            .opacity(state == .disabled ? 0.5 : 1)
            .accessibilityValue(state == .busy || state == .error ? state.title : "")
            .accessibilityIdentifier(layer.savesContact == true ? "save-contact" : layer.id)
        }
    }

    func row(_ layer: RuntimeLayer) -> some View {
        let title = runtime.design?.pages.first { $0.id == route.page }?.layers
            .first { $0.parent == layer.id && $0.kind == "label" }?.text
        return place(layer) {
            Button {
                if let action = layer.behavior?.action { invoke(action, layer: layer) }
            } label: {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(runtime.state(layer).blocksInput)
            .accessibilityLabel(title ?? "列表行")
        }
    }

    func contacts(_ layer: RuntimeLayer) -> some View {
        let list = layer.behavior?.list ?? ListDesign()
        let content = runtime.content(layer)
        let connected = layer.behavior?.action != nil || layer.destination != nil
        return place(layer) {
            if content.resolvedState == .ready {
                VStack(spacing: 0) {
                    ForEach(content.rows) { record in
                        let row = HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.fields[list.titleKey]?.text ?? "").font(.body.weight(.medium))
                                if let detail = record.fields[list.detailKey]?.text, !detail.isEmpty {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if connected { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true) }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: CGFloat(list.rowHeight ?? 56) - 1)
                        .contentShape(Rectangle())
                        if connected {
                            Button { runtime.select(layer, row: record, route: route, inPanel: inPanel, onAction: onAction) } label: { row }
                                .buttonStyle(.plain)
                                .disabled(runtime.state(layer).blocksInput)
                                .accessibilityIdentifier("contact-\(record.id)")
                        } else {
                            row.accessibilityElement(children: .combine)
                        }
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 1).accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if content.resolvedState == .loading { ProgressView() }
                        if content.resolvedState == .failed {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(errorColor).accessibilityHidden(true)
                        }
                        Text(list.message(for: content)).foregroundStyle(.secondary)
                    }
                    if content.resolvedState == .empty, let action = list.emptyAction, !list.emptyButton.isEmpty {
                        Button(list.emptyButton) { invoke(action, layer: layer) }.frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    func setting(_ layer: RuntimeLayer) -> some View {
        place(layer) {
            Toggle(layer.text, isOn: runtime.toggle(layer, route: route, onAction: onAction))
                .disabled(runtime.state(layer).blocksInput)
                .padding(.horizontal, 12)
        }
    }

    func label(_ layer: RuntimeLayer) -> some View {
        place(layer) { Text(runtime.display(layer, route: route)).font(.body) }
    }

    func toggle(_ layer: RuntimeLayer) -> some View {
        place(layer) {
            Toggle(layer.text.isEmpty ? "开关" : layer.text, isOn: runtime.toggle(layer, route: route, onAction: onAction))
                .labelsHidden()
                .disabled(runtime.state(layer).blocksInput)
                .accessibilityHint(runtime.error(layer, route) ?? "")
        }
    }

    func divider(_ layer: RuntimeLayer) -> some View {
        place(layer) { Rectangle().fill(Color(uiColor: .separator)).accessibilityHidden(true) }
    }

    func image(_ layer: RuntimeLayer) -> some View {
        place(layer) {
            if let data = layer.image, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel(layer.text)
                    .accessibilityHidden(layer.text.isEmpty)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func place<Content: View>(_ layer: RuntimeLayer, @ViewBuilder content: () -> Content) -> some View {
        if let frame = layout.items[layer.id]?.frame {
            content()
                .frame(width: frame.width, height: frame.height, alignment: .leading)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}

private struct ContactButtonStyle: ButtonStyle {
    let radius: CGFloat
    let isSecondary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let fill = isSecondary ? Color(uiColor: .secondarySystemBackground) : Color(red: 0, green: 0.35, blue: 0.78)
        configuration.label
            .foregroundStyle(isSecondary ? Color.primary : .white)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: shape)
            .overlay {
                if isSecondary { shape.strokeBorder(Color(uiColor: .separator)) }
            }
    }
}
