import CryptoKit
import Foundation

actor PreviewBuild {
    static let shared = PreviewBuild()
    private var builds: [String: Task<URL, Error>] = [:]

    func output(_ platform: String) async throws -> URL {
        if let build = builds[platform] { return try await build.value }
        let build = Task { try await Self.build(platform) }
        builds[platform] = build
        do { return try await build.value }
        catch {
            builds[platform] = nil
            throw error
        }
    }

    private static func build(_ platform: String) async throws -> URL {
        let manager = FileManager.default
        let source = RuntimeAssets.folder(platform)
        let identity = try sourceDigest(source)
        let root = URL.cachesDirectory.appending(path: "UI Design/Preview/\(platform)-\(identity)")
        let template = root.appending(path: platform)
        let isWeb = platform == "Web"
        let product = isWeb ? template.appending(path: "dist") : root.appending(path: "Build/Products/Debug-iphonesimulator/DesignApp.app")
        let marker = root.appending(path: "ready")
        if manager.fileExists(atPath: marker.path(percentEncoded: false)), manager.fileExists(atPath: product.path(percentEncoded: false)) { return product }
        if manager.fileExists(atPath: root.path(percentEncoded: false)) { try manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: template)
        if isWeb {
            guard let npm = PreviewTool.find("npm", override: "UIDESIGN_NPM") else {
                throw PreviewIssue(text: "找不到 npm。安装 Node.js 22.12 或更新版本后重试")
            }
            _ = try await PreviewTool.run(npm, ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], in: template)
            _ = try await PreviewTool.run(npm, ["run", "build"], in: template)
        } else {
            _ = try await PreviewTool.run("/usr/bin/xcodebuild", [
                "-project", template.appending(path: "DesignApp.xcodeproj").path(percentEncoded: false), "-scheme", "DesignApp",
                "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", root.path(percentEncoded: false), "-quiet",
                "CODE_SIGNING_ALLOWED=NO", "build"
            ])
        }
        try Data().write(to: marker, options: .atomic)
        return product
    }

    private static func sourceDigest(_ source: URL) throws -> String {
        let files = try FileManager.default.subpathsOfDirectory(atPath: source.path(percentEncoded: false)).sorted()
        var hash = SHA256()
        for path in files {
            let url = source.appending(path: path)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                hash.update(data: Data(path.utf8))
                hash.update(data: try Data(contentsOf: url))
            }
        }
        return hash.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
