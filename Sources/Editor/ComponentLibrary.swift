import SwiftUI

struct ComponentLibrary: View {
    let palette: WorkbenchPalette
    let focusOnLaunch: Bool
    let searchRequest: Int
    let searchRevealsLibrary: Bool

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("组件库")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                WorkbenchSymbol(name: "magnifyingglass")
                    .foregroundStyle(palette.muted)
                TextField("搜索组件", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("library-search")
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchFocused = true
                    } label: {
                        WorkbenchSymbol(name: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .workbenchSurface(palette)
            .overlay {
                if searchFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.accent.opacity(0.28), lineWidth: 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(palette.accent, lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                }
            }

            if matches.isEmpty {
                Text("没有匹配的组件")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("基础", items: matches.filter { !$0.isGroup })
                        section("组合", items: matches.filter(\.isGroup))
                    }
                    .padding(.top, 20)
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: searchRequest) {
            guard focusOnLaunch || searchRequest > 0 else { return }
            if searchRevealsLibrary {
                // Give the native split view time to restore the sidebar to the focus chain.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
            searchFocused = true
        }
    }

    private var matches: [LibrarySample] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return LibrarySample.all.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }

    @ViewBuilder
    private func section(_ title: String, items: [LibrarySample]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        WorkbenchSymbol(name: item.symbol)
                            .foregroundStyle(palette.secondary)
                            .frame(width: 32, height: 28)
                            .workbenchSurface(palette, radius: 6)
                        Text(item.name)
                            .font(.system(size: 13))
                    }
                    .frame(height: 36)
                }
            }
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
