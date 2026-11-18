import AppKit
import SwiftUI

struct ComponentLibrary: View {
    let palette: WorkbenchPalette
    @Bindable var session: ReviewSession

    @State private var query = ""
    @State private var selected: LayerKind?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigatorTabs(selection: $session.navigatorTab, showsPages: session.editor != nil)
                .id(session.editor != nil)
                .frame(height: 24)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            switch session.navigatorTab {
            case .components:
                searchField
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                catalog
            case .layers:
                if let editor = session.editor {
                    DesignLayerNavigator(editor: editor, palette: palette)
                        .padding(.top, 8)
                } else {
                    LayerNavigator(state: session.state, palette: palette)
                        .padding(.top, 8)
                }
            case .pages:
                if let editor = session.editor {
                    PageNavigator(editor: editor, palette: palette)
                }
            case .personal:
                if let editor = session.editor { PersonalLibraryView(editor: editor, palette: palette) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作台侧栏")
        .task(id: session.searchRequest) {
            guard session.searchRequest > 0, session.navigatorTab == .components else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            TextField("搜索组件", text: $query, prompt: Text("搜索组件").foregroundStyle(palette.muted))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 12))
                .accessibilityIdentifier("library-search")
                .onChange(of: query) { selected = nil }
                .onSubmit {
                    if let item = selected ?? matches.first { insert(item) }
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard !matches.isEmpty else { return .ignored }
                    let index = selected.flatMap { matches.firstIndex(of: $0) }
                    let next = press.key == .downArrow ? (index ?? -1) + 1 : (index ?? matches.count) - 1
                    selected = matches[min(max(next, 0), matches.count - 1)]
                    return .handled
                }
                .onExitCommand {
                    if !query.isEmpty { query = "" }
                    else { session.editor?.focusCanvas() }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(searchFocused ? palette.field : palette.searchFill, in: .rect(cornerRadius: 6))
        .overlay {
            if searchFocused {
                RoundedRectangle(cornerRadius: 7.5)
                    .strokeBorder(palette.focusHalo, lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }

    private var catalog: some View {
        ScrollView {
            if matches.isEmpty {
                Text("没有匹配的组件")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(LayerKind.sections, id: \.0) { title, kinds in
                        section(title, items: kinds.filter { matches.contains($0) })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .scrollIndicators(.never)
    }

    private var matches: [LayerKind] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return LayerKind.catalog.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }

    private func insert(_ item: LayerKind) {
        selected = item
        session.editor?.insert(item)
    }

    @ViewBuilder
    private func section(_ title: String, items: [LayerKind]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    Button {
                        insert(item)
                    } label: {
                        NavigatorRow(
                            title: item.name, symbol: item.symbol, selected: searchFocused && selected == item.id,
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(searchFocused && selected == item.id ? .isSelected : [])
                    .accessibilityIdentifier("library-\(item.rawValue)")
                    .help(session.editor == nil ? item.name : "插入\(item.name)，也可拖到画板")
                    .overlay {
                        if session.editor != nil {
                            ComponentDragSource(kind: item) { insert(item) }
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.top, 14)
        }
    }
}

private struct NavigatorTabs: NSViewRepresentable {
    @Binding var selection: NavigatorTab
    let showsPages: Bool

    private var tabs: [NavigatorTab] { showsPages ? [.components, .layers, .pages, .personal] : [.components, .layers] }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, tabs: tabs) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: tabs.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectSegment(_:))
        )
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .rounded
        control.setAccessibilityLabel("侧栏视图")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = tabs.firstIndex(of: selection) ?? 0
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 24)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<NavigatorTab>
        let tabs: [NavigatorTab]

        init(selection: Binding<NavigatorTab>, tabs: [NavigatorTab]) {
            self.selection = selection
            self.tabs = tabs
        }

        @objc func selectSegment(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard tabs.indices.contains(index) else { return }
            selection.wrappedValue = tabs[index]
        }
    }
}

struct NavigatorRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let palette: WorkbenchPalette
    var depth = 0
    var showsDisclosureColumn = false
    var isBranch = false
    var expanded = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            if showsDisclosureColumn {
                Group {
                    if isBranch {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(selected ? .white : palette.muted)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(selected ? .white : palette.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(selected ? .white : palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8 + CGFloat(depth) * 16)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? palette.selection : hovered ? palette.rowHover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct LayerNavigator: View {
    let state: ReviewState
    let palette: WorkbenchPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(LayerSample.pages(for: state)) { node in
                    LayerBranch(node: node, palette: palette, depth: 0)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.never)
        .id(state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图层")
    }
}

private struct LayerBranch: View {
    let node: LayerSample
    let palette: WorkbenchPalette
    let depth: Int

    @State private var expanded = true

    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            Button {
                expanded.toggle()
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")
            .accessibilityAddTraits(node.selected ? .isSelected : [])

            if expanded {
                ForEach(node.children) { child in
                    LayerBranch(node: child, palette: palette, depth: depth + 1)
                }
            }
        }
    }

    private var row: some View {
        NavigatorRow(
            title: node.title, symbol: node.symbol, selected: node.selected, palette: palette,
            depth: depth, showsDisclosureColumn: true, isBranch: !node.children.isEmpty, expanded: expanded
        )
    }
}

private struct LayerSample: Identifiable {
    let title: String
    let symbol: String
    var selected = false
    var children: [Self] = []

    var id: String { title }

    static func pages(for state: ReviewState) -> [Self] {
        switch state {
        case .blank:
            [Self(title: "页面 1", symbol: "iphone")]
        case .selection:
            [Self(title: "设置", symbol: "iphone", children: [
                Self(title: "消息通知", symbol: "square.stack", selected: true, children: [
                    Self(title: "图标", symbol: "bell"),
                    Self(title: "消息通知", symbol: "textformat"),
                    Self(title: "开关", symbol: "switch.2")
                ]),
                Self(title: "邮件摘要", symbol: "square.stack"),
                Self(title: "个人资料", symbol: "square.stack"),
                Self(title: "隐私与安全", symbol: "square.stack")
            ])]
        case .flow:
            [
                Self(title: "联系人列表", symbol: "iphone", children: [
                    Self(title: "列表行", symbol: "list.bullet")
                ]),
                Self(title: "联系人详情", symbol: "iphone", children: [
                    Self(title: "联系方式", symbol: "square.stack")
                ])
            ]
        }
    }
}

private struct DesignLayerNavigator: View {
    let editor: DesignEditing
    let palette: WorkbenchPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigatorRow(title: editor.page.title, symbol: "iphone", selected: false, palette: palette,
                             showsDisclosureColumn: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(editor.page.layers) { layer in
                    DesignLayerBranch(layer: layer, editor: editor, palette: palette)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图层")
    }
}

private struct DesignLayerBranch: View {
    let layer: DesignLayer
    let editor: DesignEditing
    let palette: WorkbenchPalette
    var depth = 1
    @State private var expanded = true

    var body: some View {
        if layer.children.isEmpty {
            row(layer, depth: depth)
        } else {
            HStack(spacing: 0) {
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "折叠" : "展开")
                row(layer, depth: depth - 1, disclosureColumn: false)
            }
            if expanded {
                ForEach(editor.siblings(of: layer)) { child in
                    DesignLayerBranch(layer: child, editor: editor, palette: palette, depth: depth + 1)
                }
            }
        }
    }

    private func row(_ item: DesignLayer, depth: Int, disclosureColumn: Bool = true) -> some View {
        let selected = editor.selectedIDs.contains(item.id)
        return Button {
            if NSEvent.modifierFlags.contains(.shift), depth == 1 {
                editor.toggleSelection(item.id)
            } else {
                editor.select(item.id)
            }
        } label: {
            NavigatorRow(title: item.name, symbol: item.kind.symbol, selected: selected, palette: palette,
                         depth: depth, showsDisclosureColumn: disclosureColumn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("layer-\(item.kind.rawValue)")
        .contextMenu {
            if editor.page.selection(item.id)?.parent == nil {
                Button(selected ? "取消加入选区" : "加入选区") { editor.toggleSelection(item.id) }
            }
            Button("复制图层") {
                editor.select(item.id)
                editor.duplicateSelection()
            }
        }
    }
}
