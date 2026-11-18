import SwiftUI

struct SourceExportRequest: Identifiable {
    let id = UUID()
    let selectedOnly: Bool
    let pageIDs: Set<UUID>
}

struct SourceExportTarget: Sendable {
    let export: SourceExport
    let updating: Bool
}

struct SourceExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: DesignEditing
    let request: SourceExportRequest
    let run: PreviewController
    @State private var pageIDs: Set<UUID>
    @State private var note: String?

    init(editor: DesignEditing, request: SourceExportRequest, run: PreviewController) {
        self.editor = editor
        self.request = request
        self.run = run
        _pageIDs = State(initialValue: request.pageIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.selectedOnly ? "导出选中页面" : "导出完整工程").font(.headline)
            if request.selectedOnly {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(editor.project.pages, id: \.id) { page in
                            Toggle(page.title, isOn: Binding(get: { pageIDs.contains(page.id) }, set: { selected in
                                if selected { pageIDs.insert(page.id) }
                                else { pageIDs.remove(page.id) }
                            }))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .frame(height: min(240, CGFloat(editor.project.pages.count) * 24 + 4))
                .accessibilityLabel("选择要导出的页面")
                Text("指向未选页面的连线会交给宿主处理。").foregroundStyle(.secondary)
            }
            if let note { Label(note, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            HStack {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("更新已有目录…") { finish(updating: true) }.disabled(cannotExport)
                Button("导出到新目录…") { finish(updating: false) }.keyboardShortcut(.defaultAction).disabled(cannotExport)
            }
        }
        .padding(24)
        .frame(width: 468)
    }

    private var cannotExport: Bool { request.selectedOnly && pageIDs.isEmpty }

    private func finish(updating: Bool) {
        do {
            let export = try SourceExport(project: editor.project, scope: request.selectedOnly ? .pages(pageIDs) : .complete)
            let target = SourceExportTarget(export: export, updating: updating)
            let controller = run
            dismiss()
            DispatchQueue.main.async { controller.chooseExportDirectory(target) }
        } catch { note = error.localizedDescription }
    }
}

struct SourceUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let update: ExportUpdate
    let apply: (Set<String>) -> Void
    @State private var selected: String?
    @State private var replacements: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更新导出源码").font(.headline)
            if update.changes.isEmpty {
                Text("源码没有变化")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    List(update.changes, selection: $selected) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.path).lineLimit(1).truncationMode(.middle).help(change.path)
                            Text(status(change)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(change.path)
                    }
                    .frame(width: 244)
                    .accessibilityLabel("受影响的文件")
                    if let change = update.changes.first(where: { $0.path == selected }) {
                        VStack(alignment: .leading, spacing: 8) {
                            if change.state == .conflict {
                                Picker("文件版本", selection: Binding(get: {
                                    replacements.contains(change.path)
                                }, set: { useNew in
                                    if useNew { replacements.insert(change.path) }
                                    else { replacements.remove(change.path) }
                                })) {
                                    Text("保留手改").tag(false)
                                    Text("采用新生成版本").tag(true)
                                }
                                .pickerStyle(.segmented)
                            }
                            if let (before, after) = change.textComparison {
                                HStack(spacing: 8) {
                                    source("当前文件", before)
                                    source("新生成版本", after)
                                }
                            } else {
                                Text(change.state == .added ? "新增文件" : "此文件无法显示文本对照")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 298)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("更新") {
                    dismiss()
                    apply(replacements)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(update.changes.isEmpty)
            }
        }
        .padding(24)
        .frame(width: update.changes.isEmpty ? 340 : 850)
        .onAppear { selected = update.changes.first(where: { $0.state == .conflict })?.path ?? update.changes.first?.path }
    }

    private func source(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "无" : text).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(title)
            .background(.quaternary, in: .rect(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity)
    }

    private func status(_ change: ExportUpdate.Change) -> String {
        switch change.state {
        case .added: "新增"
        case .generated: "更新"
        case .host: "保留宿主文件"
        case .conflict: replacements.contains(change.path) ? "采用新生成版本" : "保留手改"
        }
    }
}
