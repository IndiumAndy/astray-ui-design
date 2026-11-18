import AppKit
import SwiftUI

struct TemplateSaveRequest: Identifiable {
    let id = UUID()
    let layers: Bool
    let selectedPages: Set<UUID>
    let name: String
    let replacing: UUID?
}

struct TemplateSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: DesignEditing
    let request: TemplateSaveRequest
    @State private var name: String
    @State private var selectedPages: Set<UUID>
    @State private var includeLinkedPages = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(editor: DesignEditing, request: TemplateSaveRequest) {
        self.editor = editor
        self.request = request
        _name = State(initialValue: request.name)
        _selectedPages = State(initialValue: request.selectedPages)
    }

    private var selection: TemplateSelection {
        request.layers ? .layers(page: editor.page.id, layers: editor.selectedTemplateLayers) : .pages(selectedPages)
    }

    var body: some View {
        let outside = PersonalTemplate.linkedPages(in: editor.project, selection: selection)
        VStack(alignment: .leading, spacing: 16) {
            Text(request.replacing == nil ? "存入个人库" : "更新模板").font(.headline)
            TextField("名称", text: $name).focused($focused)
            if !request.layers {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(editor.project.pages, id: \.id) { page in
                            Toggle(page.title, isOn: Binding(get: { selectedPages.contains(page.id) }, set: { selected in
                                if selected { selectedPages.insert(page.id) }
                                else { selectedPages.remove(page.id) }
                            }))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .frame(height: min(220, CGFloat(editor.project.pages.count) * 24 + 4))
                .accessibilityLabel("选择要保存的页面")
            }
            if !outside.isEmpty {
                Picker("选区外的连线", selection: $includeLinkedPages) {
                    Text("留待重连").tag(false)
                    Text("一并带入 \(outside.count) 页").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.replacing == nil ? "存入" : "更新", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!request.layers && selectedPages.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 360)
        .task { focused = true }
    }

    private func save() {
        do {
            let template = try PersonalTemplate.capture(name: name, replacing: request.replacing,
                                                        from: editor.project, selection: selection,
                                                        includeLinkedPages: includeLinkedPages)
            try PersonalLibrary.shared.save(template)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PersonalLibraryView: View {
    let editor: DesignEditing
    let palette: WorkbenchPalette
    @Environment(\.newDocument) private var newDocument
    @State private var library = PersonalLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu("存入个人库", systemImage: "plus") {
                Button("所选图层…") { editor.requestLibrarySave(layers: true) }
                    .disabled(editor.selectedTemplateLayers.isEmpty)
                Button("页面或流程…") { editor.requestLibrarySave(layers: false) }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.horizontal, 8)
            if let issue = library.issue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(palette.secondary).padding(.horizontal, 8)
            }
            if library.templates.isEmpty {
                Text("尚无模板").font(.system(size: 12)).foregroundStyle(palette.secondary)
                    .padding(.horizontal, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(library.templates) { template in
                            Button { editor.insertTemplate(template) } label: {
                                NavigatorRow(title: template.name, symbol: template.kind.symbol,
                                             selected: false, palette: palette)
                            }
                            .buttonStyle(.plain)
                            .overlay {
                                ComponentDragSource(payload: .template(template.id), symbol: template.kind.symbol,
                                                    title: template.name) { editor.insertTemplate(template) }
                                    .accessibilityHidden(true)
                            }
                            .accessibilityLabel("\(template.name)，\(template.kind.title)")
                            .accessibilityHint("插入模板副本")
                            .help("\(template.kind.title) · 插入副本")
                            .contextMenu {
                                Button("插入副本") { editor.insertTemplate(template) }
                                Button("新建项目") { create(template) }
                                Divider()
                                Button("用所选图层更新模板…") { editor.requestLibrarySave(layers: true, replacing: template) }
                                    .disabled(editor.selectedTemplateLayers.isEmpty)
                                Button("用页面或流程更新模板…") { editor.requestLibrarySave(layers: false, replacing: template) }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private func create(_ template: PersonalTemplate) {
        do {
            let project = try template.instantiate().project
            newDocument { DesignFile(project: project) }
        } catch {
            editor.libraryIssue = error.localizedDescription
        }
    }
}
