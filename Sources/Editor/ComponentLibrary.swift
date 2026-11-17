import AppKit
import SwiftUI

struct ComponentLibrary: View {
    let palette: WorkbenchPalette
    @Bindable var session: ReviewSession

    @State private var query = ""
    @State private var selected: LibrarySample.ID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigatorTabs(selection: $session.navigatorTab)
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
                LayerNavigator(state: session.state, palette: palette)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("组件与图层")
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
                    section("基础", items: matches.filter { !$0.isGroup })
                    section("组合", items: matches.filter(\.isGroup))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .scrollIndicators(.never)
    }

    private var matches: [LibrarySample] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return LibrarySample.all.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }

    @ViewBuilder
    private func section(_ title: String, items: [LibrarySample]) -> some View {
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
                        selected = item.id
                    } label: {
                        NavigatorRow(
                            title: item.name, symbol: item.symbol, selected: selected == item.id,
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == item.id ? .isSelected : [])
                }
            }
            .padding(.top, 14)
        }
    }
}

private struct NavigatorTabs: NSViewRepresentable {
    @Binding var selection: NavigatorTab

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: NavigatorTab.allCases.map(\.title),
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
        control.selectedSegment = NavigatorTab.allCases.firstIndex(of: selection) ?? 0
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 24)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<NavigatorTab>

        init(selection: Binding<NavigatorTab>) { self.selection = selection }

        @objc func selectSegment(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard NavigatorTab.allCases.indices.contains(index) else { return }
            selection.wrappedValue = NavigatorTab.allCases[index]
        }
    }
}

private struct NavigatorRow: View {
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

private struct LibrarySample: Identifiable {
    let name: String
    let symbol: String
    var isGroup = false
    var id: String { name }

    static let all = [
        Self(name: "标题", symbol: "textformat.size"),
        Self(name: "正文", symbol: "text.alignleft"),
        Self(name: "输入框", symbol: "character.textbox"),
        Self(name: "按钮", symbol: "rectangle"),
        Self(name: "开关", symbol: "switch.2"),
        Self(name: "带标签输入框", symbol: "text.and.command.macwindow", isGroup: true),
        Self(name: "设置项", symbol: "slider.horizontal.3", isGroup: true),
        Self(name: "列表行", symbol: "list.bullet", isGroup: true)
    ]
}
