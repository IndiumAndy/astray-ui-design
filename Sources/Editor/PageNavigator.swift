import SwiftUI

struct PageNavigator: View {
    let editor: DesignEditing
    let palette: WorkbenchPalette
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button("添加页面", systemImage: "plus", action: editor.addPage)
                    .labelStyle(.iconOnly)
                Menu("页面操作", systemImage: "ellipsis") {
                    Button("重命名页面") {
                        name = editor.page.title
                        renaming = true
                    }
                    Button("删除页面", role: .destructive, action: editor.removePage)
                        .disabled(editor.project.pages.count < 2)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(editor.project.pages, id: \.id) { page in
                        Button { editor.showPage(page.id) } label: {
                            NavigatorRow(title: page.title, symbol: "rectangle.portrait",
                                         selected: editor.page.id == page.id, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(editor.page.id == page.id ? .isSelected : [])
                    }
                }
            }
        }
        .padding(8)
        .alert("重命名页面", isPresented: $renaming) {
            TextField("页面名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("重命名") {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { editor.renamePage(title) }
            }
        }
    }
}
