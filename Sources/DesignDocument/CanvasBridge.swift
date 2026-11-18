import CoreGraphics
import Darwin
import Foundation

struct CanvasBridgeRequest: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case read, edit, simulator }
    let id: UUID
    let deadline: Date
    let kind: Kind
    var page: UUID?
    var revision: String?
    var operations: [CanvasOperation]?
    var input: MCPPreviewInput?

    init(_ kind: Kind, timeout: TimeInterval = 12, page: UUID? = nil, revision: String? = nil,
         operations: [CanvasOperation]? = nil, input: MCPPreviewInput? = nil) {
        id = UUID()
        deadline = Date().addingTimeInterval(timeout)
        self.kind = kind
        self.page = page
        self.revision = revision
        self.operations = operations
        self.input = input
    }
}

struct MCPPreviewInput: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case screenshot, tap, swipe, text }
    let kind: Kind
    var x: CGFloat?
    var y: CGFloat?
    var endX: CGFloat?
    var endY: CGFloat?
    var text: String?
}

struct CanvasBridgeResponse: Codable, Sendable {
    var project: DesignProject?
    var revision: String?
    var editorOpen: Bool? = nil
    var screenshot: Data? = nil
    var error: String? = nil
}

struct CanvasBridgeLease: Codable, Sendable {
    let owner: UUID
    let processID: Int32
}

struct CanvasBridge {
    let projectURL: URL
    let directory: URL

    init(projectURL: URL, root: URL = URL.temporaryDirectory) throws {
        let normalized = projectURL.standardizedFileURL
        guard normalized.pathExtension == "uidesign", normalized.isFileURL else {
            throw CanvasBridgeError.projectPath
        }
        self.projectURL = normalized.resolvingSymlinksInPath()
        let base = root.appending(path: "UIDesignDocumentBridge-\(getuid())", directoryHint: .isDirectory)
        let digest = ExportManifest.digest(Data(self.projectURL.path.utf8))
        directory = base.appending(path: digest, directoryHint: .isDirectory)
        try Self.createPrivateDirectory(base)
        try Self.createPrivateDirectory(directory)
    }

    private static func createPrivateDirectory(_ url: URL) throws {
        let files = FileManager.default
        let privateMode: NSNumber = 0o700
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: privateMode])
        } catch {
            if !files.fileExists(atPath: url.path) { throw error }
        }
        let attrs = try files.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let access = attrs[.posixPermissions] as? NSNumber, access.intValue & 0o077 == 0 else {
            throw CanvasBridgeError.bridgeDirectory
        }
    }

    func withLock<T>(_ work: () throws -> T) throws -> T {
        let lock = directory.appending(path: "document.lock")
        let fd = open(lock.path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard fd != -1 else { throw CanvasBridgeError.bridgeDirectory }
        defer { _ = close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CanvasBridgeError.bridgeDirectory }
        defer { _ = flock(fd, LOCK_UN) }
        return try work()
    }

    func acquire(_ lease: CanvasBridgeLease) throws -> Bool {
        try withLock {
            if let active = try activeLease(), active.owner != lease.owner { return false }
            try Self.write(lease, to: leaseURL)
            return true
        }
    }

    func release(_ lease: CanvasBridgeLease) {
        try? withLock {
            if try activeLease()?.owner == lease.owner { try FileManager.default.removeItem(at: leaseURL) }
        }
    }

    func activeLease() throws -> CanvasBridgeLease? {
        guard let lease: CanvasBridgeLease = try Self.read(CanvasBridgeLease.self, at: leaseURL),
              lease.processID > 0 else { return nil }
        return kill(lease.processID, 0) == 0 || errno == EPERM ? lease : nil
    }

    func enqueue(_ request: CanvasBridgeRequest) throws { try Self.write(request, to: requestURL(request.id)) }

    func requests() throws -> [CanvasBridgeRequest] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return entries.filter { $0.pathExtension == "request" }
            .compactMap { url -> CanvasBridgeRequest? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let request = try? Self.read(CanvasBridgeRequest.self, at: url),
                      request.id == id else { return nil }
                return request
            }
            .sorted { ($0.deadline, $0.id.uuidString) < ($1.deadline, $1.id.uuidString) }
    }

    func respond(_ response: CanvasBridgeResponse, to request: CanvasBridgeRequest) throws {
        try Self.write(response, to: resultURL(request.id))
        try? FileManager.default.removeItem(at: requestURL(request.id))
    }

    func abandon(_ request: CanvasBridgeRequest) {
        try? FileManager.default.removeItem(at: requestURL(request.id))
    }

    func receive(_ request: CanvasBridgeRequest) throws -> CanvasBridgeResponse? {
        let url = resultURL(request.id)
        guard let result = try Self.read(CanvasBridgeResponse.self, at: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return result
    }

    func getProject() throws -> DesignProject {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: projectURL.path),
              attrs[.type] as? FileAttributeType == .typeRegular else { throw CanvasBridgeError.projectPath }
        return try DesignCodec.read(Data(contentsOf: projectURL))
    }

    func runOffline(_ request: CanvasBridgeRequest) throws -> CanvasBridgeResponse {
        let project = try getProject()
        switch request.kind {
        case .read:
            return CanvasBridgeResponse(project: project, revision: try DesignBatch.revision(project), editorOpen: false)
        case .edit:
            guard let page = request.page, let revision = request.revision, let operations = request.operations else {
                throw CanvasBridgeError.invalidRequest
            }
            let updated = try DesignBatch.applying(operations, to: project, pageID: page, expecting: revision)
            let bytes = try DesignCodec.encoded(updated)
            try bytes.write(to: projectURL, options: .atomic)
            return CanvasBridgeResponse(revision: ExportManifest.digest(bytes), editorOpen: false)
        case .simulator: throw CanvasBridgeError.noPreview
        }
    }

    private var leaseURL: URL { directory.appending(path: "editor.json") }
    private func requestURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).request") }
    private func resultURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).response") }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return nil }
        let attrs = try files.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.int64Value ?? Int64.max <= 128_000_000 else {
            throw CanvasBridgeError.bridgeDirectory
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

enum CanvasBridgeError: LocalizedError {
    case projectPath, bridgeDirectory, invalidRequest, timeout, noPreview, accessDisabled, noExportRoot, unsafeExport
    var errorDescription: String? {
        switch self {
        case .projectPath: "请指定已保存的 .uidesign 项目文件"
        case .bridgeDirectory: "项目的本机通信目录不可用或权限不安全"
        case .invalidRequest: "操作缺少必填参数或数值不合法"
        case .timeout: "编辑器未确认此操作。请重新读取项目，不要直接重试写入"
        case .noPreview: "请先在这个项目窗口打开内嵌 iPhone 预览"
        case .accessDisabled: "请在项目窗口的「工作台」菜单打开「允许本机 MCP」"
        case .noExportRoot: "启动 MCP 时请显式指定允许导出的目录"
        case .unsafeExport: "导出名称无效，或位置已存在；为保护现有文件，请使用新目录"
        }
    }
}
