import CryptoKit
import Foundation

struct ExportManifest: Codable, Equatable, Sendable {
    static let filename = "UI Design Export.json"
    let version: Int
    let complete: Bool
    let pages: [SourceExport.Page]
    let hostLinks: [SourceExport.HostLink]
    var generatedFiles: [String: String]

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

struct ExportUpdate: Sendable {
    enum State: String, Sendable {
        case added, generated, conflict, host
    }

    struct Change: Identifiable, Sendable {
        let path: String
        let state: State
        let before: Data?
        let after: Data
        var id: String { path }

        var textComparison: (String, String)? {
            guard after.count < 170_000, (before?.count ?? 0) < 170_000,
                  let new = String(data: after, encoding: .utf8),
                  let old = String(data: before ?? Data(), encoding: .utf8) else { return nil }
            return (old, new)
        }
    }

    let destination: URL
    let changes: [Change]
    private let oldManifest: Data
    private let manifest: ExportManifest

    init(generated: URL, destination: URL, manifest: ExportManifest) throws {
        self.destination = destination
        self.manifest = manifest
        guard let oldBytes = try Self.read(ExportManifest.filename, in: destination),
              let previous = try? JSONDecoder().decode(ExportManifest.self, from: oldBytes),
              previous.version == 1 else { throw ExportProblem.invalidDirectory }
        oldManifest = oldBytes
        let hostHooks: Set<String> = ["iPhone/Sources/ContactActions.swift", "Web/src/contactActions.js"]
        changes = try manifest.generatedFiles.keys.sorted().compactMap { path in
            guard let after = try Self.read(path, in: generated) else { throw ExportProblem.unsafePath(path) }
            let before = try Self.read(path, in: destination)
            guard after != before else { return nil }
            let old = previous.generatedFiles[path]
            let state: State
            if before == nil { state = .added }
            else if hostHooks.contains(path) { state = .host }
            else if let before, old == ExportManifest.digest(before) { state = .generated }
            else { state = .conflict }
            return Change(path: path, state: state, before: before, after: after)
        }
    }

    func apply(replacingConflicts: Set<String>) throws {
        guard try Self.read(ExportManifest.filename, in: destination) == oldManifest else {
            throw ExportProblem.changedAfterReview(ExportManifest.filename)
        }
        var updated = manifest
        let previous = try JSONDecoder().decode(ExportManifest.self, from: oldManifest)
        let plan = changes.filter { change in
            let overwrite = change.state == .added || change.state == .generated ||
                (change.state == .conflict && replacingConflicts.contains(change.path))
            if !overwrite { updated.generatedFiles[change.path] = previous.generatedFiles[change.path] }
            return overwrite
        }
        for change in changes {
            guard try Self.read(change.path, in: destination) == change.before else {
                throw ExportProblem.changedAfterReview(change.path)
            }
        }
        let finalManifest = try updated.encoded()
        let files = FileManager.default
        var completed: [Change] = []
        var createdDirectories: [URL] = []
        do {
            for change in plan {
                let url = try Self.checkedURL(change.path, in: destination)
                guard try Self.read(change.path, in: destination) == change.before else {
                    throw ExportProblem.changedAfterReview(change.path)
                }
                var directory = url.deletingLastPathComponent()
                var missing: [URL] = []
                while !files.fileExists(atPath: directory.path) {
                    missing.append(directory)
                    directory.deleteLastPathComponent()
                }
                for directory in missing.reversed() {
                    try files.createDirectory(at: directory, withIntermediateDirectories: false)
                    createdDirectories.append(directory)
                }
                try change.after.write(to: url, options: .atomic)
                completed.append(change)
            }
            guard try Self.read(ExportManifest.filename, in: destination) == oldManifest else {
                throw ExportProblem.changedAfterReview(ExportManifest.filename)
            }
            try finalManifest.write(to: destination.appending(path: ExportManifest.filename), options: .atomic)
        } catch {
            var restoreIssues: [String] = []
            for change in completed.reversed() {
                do {
                    let url = try Self.checkedURL(change.path, in: destination)
                    // Don't destroy a third-party write that arrived while updating.
                    guard try Self.read(change.path, in: destination) == change.after else {
                        restoreIssues.append(change.path)
                        continue
                    }
                    if let original = change.before { try original.write(to: url, options: .atomic) }
                    else { try files.removeItem(at: url) }
                } catch {
                    restoreIssues.append(change.path)
                }
            }
            for directory in createdDirectories.reversed() {
                if (try? files.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                    try? files.removeItem(at: directory)
                }
            }
            if !restoreIssues.isEmpty {
                throw ExportRecoveryError(failedPaths: restoreIssues)
            }
            throw error
        }
    }

    static func read(_ path: String, in root: URL) throws -> Data? {
        let url = try checkedURL(path, in: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func checkedURL(_ path: String, in root: URL) throws -> URL {
        let components = path.components(separatedBy: "/")
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\") else { throw ExportProblem.unsafePath(path) }
        let files = FileManager.default
        let rootAttributes = try? files.attributesOfItem(atPath: root.path)
        guard rootAttributes?[.type] as? FileAttributeType == .typeDirectory else {
            throw ExportProblem.invalidDirectory
        }
        var current = root
        for (index, component) in components.enumerated() {
            current.append(path: component)
            if let attributes = try? files.attributesOfItem(atPath: current.path) {
                let expected: FileAttributeType = index == components.count - 1 ? .typeRegular : .typeDirectory
                guard attributes[.type] as? FileAttributeType == expected else {
                    throw ExportProblem.unsafePath(path)
                }
            }
        }
        return current
    }
}

private struct ExportRecoveryError: LocalizedError {
    let failedPaths: [String]
    var errorDescription: String? { "更新中断。下列文件后来又被修改或无法恢复：\(failedPaths.joined(separator: "、"))" }
}
