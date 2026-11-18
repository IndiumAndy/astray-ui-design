import Foundation

enum ProjectExport {
    static func write(_ design: RuntimeDesign, to destination: URL) throws {
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent().appending(path: ".uidesign-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let phone = staging.appending(path: "iPhone")
        let web = staging.appending(path: "Web")
        try files.copyItem(at: RuntimeAssets.folder("Phone"), to: phone)
        try files.copyItem(at: RuntimeAssets.folder("Web"), to: web)

        let json = try RuntimeAssets.encode(design, pretty: true)
        try json.write(to: phone.appending(path: "Sources/Design.json"), options: .atomic)
        try json.write(to: web.appending(path: "src/Design.json"), options: .atomic)
        try swiftPages(design).write(to: phone.appending(path: "Sources/GeneratedPages.swift"), atomically: true, encoding: .utf8)
        try webPages(design).write(to: web.appending(path: "src/GeneratedPages.jsx"), atomically: true, encoding: .utf8)
        try instructions.write(to: staging.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try files.moveItem(at: staging, to: destination)
    }

    private static func swiftPages(_ design: RuntimeDesign) -> String {
        let cases = design.pages.flatMap(\.layers).compactMap { layer -> String? in
            let control = switch layer.kind {
            case "title": "components.title(layer)"
            case "input": "components.field(layer)"
            case "contactList": "components.contacts(layer)"
            case "listRow": "components.row(layer)"
            case "button": layer.savesContact == true && layer.behavior?.action == nil
                ? "components.button(layer) { components.saveContact() }" : "components.button(layer)"
            case "setting", "label", "toggle", "divider", "image": "components.\(layer.kind)(layer)"
            default: ""
            }
            return control.isEmpty ? nil : "        case \(String(reflecting: layer.id)): \(control)"
        }
        return """
        import SwiftUI

        @MainActor enum GeneratedPages {
            @ViewBuilder static func control(_ layer: RuntimeLayer, components: RuntimeComponents) -> some View {
                switch layer.id {
        \(cases.joined(separator: "\n"))
                default: EmptyView()
                }
            }
        }

        """
    }

    private static func webPages(_ design: RuntimeDesign) -> String {
        let pages = design.pages.enumerated().map { index, page in
            let controls = page.layers.compactMap { layer -> String? in
                let control = switch layer.kind {
                case "title": "<Title layer={layer} context={context} />"
                case "input": "<Field layer={layer} context={context} />"
                case "contactList": "<ContactList layer={layer} context={context} />"
                case "listRow": "<ListRow layer={layer} context={context} />"
                case "button": "<Action layer={layer} context={context}\(layer.savesContact == true && layer.behavior?.action == nil ? " onClick={context.save}" : "") />"
                case "setting": "<Setting layer={layer} context={context} />"
                case "label": "<DesignLabel layer={layer} context={context} />"
                case "toggle": "<DesignToggle layer={layer} context={context} />"
                case "divider": "<DesignDivider />"
                case "image": "<DesignImage layer={layer} />"
                default: ""
                }
                return control.isEmpty ? nil : "    case '\(layer.id)': return \(control);"
            }
            return """
            function Page\(index + 1)({ layer, context }) {
              switch (layer.id) {
            \(controls.joined(separator: "\n"))
                default: return null;
              }
            }
            """
        }
        let mapping = design.pages.enumerated().map { "  '\($0.element.id)': Page\($0.offset + 1)" }
        return """
        import React from 'react';
        import { Action, ContactList, DesignDivider, DesignImage, DesignLabel, DesignToggle, Field, ListRow, Setting, Title } from './Controls.jsx';

        \(pages.joined(separator: "\n\n"))

        export const generatedPages = {
        \(mapping.joined(separator: ",\n"))
        };

        """
    }

    private static let instructions = """
    # 运行导出工程

    ## iPhone

    在 Xcode 打开 `iPhone/DesignApp.xcodeproj`。选择任意已安装的 iPhone 模拟器，按 ⌘R。
    `Sources/GeneratedPages.swift` 包含每个页面的控件和点按入口，`Sources/Design.json` 保存布局、文字与示例数据。
    在 `Sources/ContactActions.swift` 的 `onAction` 接收具名动作。需要宿主数据时，在入口创建
    `RuntimeRoot(data: RuntimeData(values: ... , lists: ...), onAction: ...)`，数据变化后重新提供 `data`。
    返回 `DesignActionResult(fieldErrors: ["email": "邮箱已被使用"])` 可在对应提交键的字段下显示错误。

    ## Web

    在 `Web` 目录使用 Node.js 22.12 或更新版本运行以下命令。

    ```sh
    npm ci --ignore-scripts
    npm run build
    npm run preview
    ```

    打开终端显示的本地地址。`src/GeneratedPages.jsx` 包含页面控件及动作入口，`src/Design.json` 保存布局、文字与示例数据。
    在 `src/contactActions.js` 的 `onAction` 接收具名动作。需要宿主数据时，向 `DesignRuntime`
    传入 `design`、`data={{ values, lists, controlStates }}` 和 `onAction`，更新 React 状态即可刷新数据。
    返回 `{ fieldErrors: { email: "邮箱已被使用" } }` 可在邮箱字段下显示错误。

    ## 数据与动作

    - 字段绑定的键读取宿主值，未传入时使用设计中的示例值。表单的提交键可以单独命名。
    - 列表用数据键接收 `{ state, rows }`。单行形如 `{ id: "lin", fields: { name: "林乔", phone: "202-555-0147" } }`。
      每行使用稳定且唯一的标识。状态可为 `ready`、`empty`、`loading`、`failed`。就绪且没有行时显示空态。
    - 动作包含 `name`、`pageID`、`layerID` 和 `values`。表单动作附带 `form`，数据行触发或传入详情时附带 `record`。
    - 网络与持久化由宿主实现。宿主可用控件标识向 `controlStates` 写入 `disabled` 或 `busy`。
    """
}

enum RuntimeAssets {
    static func folder(_ name: String) -> URL {
        Bundle.main.bundleURL.appending(path: "Contents/Resources/Runtime/\(name)", directoryHint: .isDirectory)
    }

    static func encode(_ design: RuntimeDesign, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return try encoder.encode(design)
    }
}
