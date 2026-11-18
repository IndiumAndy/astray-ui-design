import Foundation

struct Configuration {
    let project: URL
    let exports: URL?

    init(_ arguments: [String]) throws {
        var options: [String: String] = [:]
        guard arguments.count.isMultiple(of: 2) else { throw CanvasBridgeError.invalidRequest }
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[index]
            let value = arguments[index + 1]
            guard ["--project", "--exports"].contains(key), options[key] == nil, value.hasPrefix("/") else {
                throw CanvasBridgeError.invalidRequest
            }
            options[key] = value
        }
        guard let document = options["--project"] else { throw CanvasBridgeError.projectPath }
        project = URL(filePath: document)
        exports = options["--exports"].map { URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath() }
    }
}

struct CanvasTools {
    let configuration: Configuration
    let bridge: CanvasBridge

    init(configuration: Configuration) throws {
        self.configuration = configuration
        bridge = try CanvasBridge(projectURL: configuration.project)
    }

    func send(_ request: CanvasBridgeRequest) throws -> CanvasBridgeResponse {
        let response = try bridge.withLock {
            if try bridge.activeLease() != nil {
                try bridge.enqueue(request)
                return nil as CanvasBridgeResponse?
            }
            return try bridge.runOffline(request)
        }
        if let response { return response }
        defer { bridge.abandon(request) }
        while Date() < request.deadline {
            if let response = try bridge.receive(request) { return response }
            Thread.sleep(forTimeInterval: 0.08)
        }
        throw CanvasBridgeError.timeout
    }

    func call(_ name: String, _ arguments: [String: Any]) throws -> [String: Any] {
        switch name {
        case "canvas_read":
            let state = try send(CanvasBridgeRequest(.read))
            if let error = state.error { return result(["message": error], error: true) }
            guard let project = state.project, let revision = state.revision else { throw CanvasBridgeError.invalidRequest }
            let payload = try JSONSerialization.jsonObject(with: DesignCodec.encoded(project))
            return result(["revision": revision, "editorOpen": state.editorOpen ?? false,
                           "project": removeImageBytes(payload)])
        case "canvas_apply":
            struct Edit: Decodable {
                let page: UUID
                let revision: String
                let operations: [CanvasOperation]
            }
            let edit = try decode(Edit.self, arguments)
            let state = try send(CanvasBridgeRequest(.edit, page: edit.page, revision: edit.revision,
                                                     operations: edit.operations))
            if let error = state.error {
                var details = ["message": error]
                details["currentRevision"] = state.revision
                return result(details, error: true)
            }
            return result(["revision": state.revision ?? "", "editorOpen": state.editorOpen ?? false])
        case "preview_simulator":
            let input = try decode(MCPPreviewInput.self, arguments)
            let state = try send(CanvasBridgeRequest(.simulator, input: input))
            if let error = state.error { return result(["message": error], error: true) }
            guard let frame = state.screenshot else { throw CanvasBridgeError.noPreview }
            return ["content": [
                ["type": "text", "text": "内嵌 iPhone 当前画面。点按与滑动坐标使用 402 × 874 pt。"],
                ["type": "image", "mimeType": "image/png", "data": frame.base64EncodedString()]
            ], "isError": false]
        case "canvas_export":
            struct Export: Decodable {
                let name: String
                let revision: String
                let pages: [UUID]?
            }
            let export = try decode(Export.self, arguments)
            guard let base = configuration.exports else { throw CanvasBridgeError.noExportRoot }
            let target = try exportURL(base: base, name: export.name)
            let state = try send(CanvasBridgeRequest(.read))
            if let error = state.error { return result(["message": error], error: true) }
            guard let project = state.project, let revision = state.revision else { throw CanvasBridgeError.invalidRequest }
            guard revision == export.revision else { throw CanvasBatchError.conflict(current: revision) }
            let scope = export.pages.map { SourceExportScope.pages(Set($0)) } ?? .complete
            let payload = try SourceExport(project: project, scope: scope)
            try ProjectExport.write(payload, to: target)
            return result(["directory": target.path, "pages": payload.pages.map(\.title), "revision": revision])
        default:
            return result(["message": "没有此工具"], error: true)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ arguments: [String: Any]) throws -> T {
        do { return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: arguments)) }
        catch { throw CanvasBridgeError.invalidRequest }
    }

    private func exportURL(base: URL, name: String) throws -> URL {
        let safe = name.trimmingCharacters(in: .whitespaces)
        let files = FileManager.default
        guard !safe.isEmpty, safe.utf8.count <= 160, !safe.hasPrefix("."),
              safe.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil,
              (try? files.attributesOfItem(atPath: base.path)[.type]) as? FileAttributeType == .typeDirectory else {
            throw CanvasBridgeError.unsafeExport
        }
        let destination = base.appending(path: safe, directoryHint: .isDirectory)
        guard (try? files.attributesOfItem(atPath: destination.path)) == nil else { throw CanvasBridgeError.unsafeExport }
        return destination
    }

    private func removeImageBytes(_ value: Any) -> Any {
        if let list = value as? [Any] { return list.map(removeImageBytes) }
        if let object = value as? [String: Any] {
            return object.reduce(into: [String: Any]()) { output, pair in
                if pair.key == "image", object["kind"] as? String == "image", pair.value is String {
                    output["hasImage"] = true
                } else if pair.key == "referenceImage", var reference = pair.value as? [String: Any] {
                    if reference.removeValue(forKey: "data") != nil { reference["hasImage"] = true }
                    output[pair.key] = reference
                } else {
                    output[pair.key] = removeImageBytes(pair.value)
                }
            }
        }
        return value
    }

    private static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static func array(_ item: [String: Any]) -> [String: Any] { ["type": "array", "items": item] }

    static var catalog: [[String: Any]] {
        let uuid = ["type": "string", "format": "uuid"]
        let string = ["type": "string"]
        let number = ["type": "number"]
        let kind = ["type": "string", "enum": ["text", "align", "gap"]] as [String: Any]
        let operation = schema(["kind": kind, "ids": array(uuid), "text": string, "value": number],
                               required: ["kind", "ids"])
        return [
            ["name": "canvas_read", "description": "Read the pinned project and its current revision. Image bytes are omitted.", "inputSchema": schema([:]), "annotations": ["readOnlyHint": true]],
            ["name": "canvas_apply", "description": "Apply an atomic batch. text edits one layer; align aligns siblings in a free layout; gap changes one container's spacing. Read again on a revision conflict.",
             "inputSchema": schema(["page": uuid, "revision": string, "operations": array(operation)],
                                   required: ["page", "revision", "operations"])],
            ["name": "preview_simulator", "description": "Screenshot, tap, swipe, or type on this project's visible embedded iPhone preview. Coordinates are in a 402 by 874 point screen.",
             "inputSchema": schema(["kind": ["type": "string", "enum": ["screenshot", "tap", "swipe", "text"]],
                                     "x": number, "y": number, "endX": number, "endY": number, "text": string],
                                   required: ["kind"])],
            ["name": "canvas_export", "description": "Export to a new directory under the explicitly configured export root. Omit pages for a complete export; existing files are not replaced.",
             "inputSchema": schema(["revision": string, "name": string, "pages": array(uuid)],
                                   required: ["revision", "name"])]
        ]
    }
}

func result(_ body: [String: Any], error: Bool = false) -> [String: Any] {
    let bytes = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return ["content": [["type": "text", "text": String(decoding: bytes, as: UTF8.self)]], "isError": error]
}

func reply(id: Any, result: [String: Any]) { write(["jsonrpc": "2.0", "id": id, "result": result]) }

func rpcError(id: Any, code: Int, message: String) {
    write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func write(_ object: [String: Any]) {
    guard var bytes = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
    bytes.append(10)
    try? FileHandle.standardOutput.write(contentsOf: bytes)
}

do {
    let tools = try CanvasTools(configuration: Configuration(Array(CommandLine.arguments.dropFirst())))
    var initialized = false
    while let line = readLine() {
        guard line.utf8.count <= 1_048_576, let bytes = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            rpcError(id: NSNull(), code: -32700, message: "Parse error")
            continue
        }
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            rpcError(id: id ?? NSNull(), code: -32600, message: "Invalid request")
            continue
        }
        guard let id else {
            if method == "notifications/initialized" { initialized = true }
            continue
        }
        let parameters = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let proposed = parameters["protocolVersion"] as? String
            let known = ["2025-11-25", "2025-06-18", "2025-03-26"]
            reply(id: id, result: ["protocolVersion": proposed.flatMap { known.contains($0) ? $0 : nil } ?? known[0],
                                   "capabilities": ["tools": ["listChanged": false]],
                                   "serverInfo": ["name": "uidesign", "version": "0.1.0"]])
        case "ping": reply(id: id, result: [:])
        case "tools/list" where initialized: reply(id: id, result: ["tools": CanvasTools.catalog])
        case "tools/call" where initialized:
            guard let name = parameters["name"] as? String else {
                rpcError(id: id, code: -32602, message: "Missing tool name")
                continue
            }
            do { reply(id: id, result: try tools.call(name, parameters["arguments"] as? [String: Any] ?? [:])) }
            catch CanvasBatchError.conflict(let current) {
                reply(id: id, result: result(["message": "设计已被修改。请先重新读取，再提交更新", "currentRevision": current], error: true))
            } catch { reply(id: id, result: result(["message": error.localizedDescription], error: true)) }
        default: rpcError(id: id, code: -32601, message: "Method not found")
        }
    }
} catch {
    let help = "\(error.localizedDescription)\nUIDesignMCP --project /path/Design.uidesign [--exports /path/Exports]\n"
    try? FileHandle.standardError.write(contentsOf: Data(help.utf8))
    exit(2)
}
