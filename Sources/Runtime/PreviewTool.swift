import Foundation

struct PreviewIssue: LocalizedError, Equatable {
    let text: String
    var errorDescription: String? { text }
}

enum PreviewTool {
    static let support = URL.applicationSupportDirectory.appending(path: "UI Design", directoryHint: .isDirectory)

    static func process(_ tool: String, _ arguments: [String], in directory: URL? = nil) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        process.environment = environment
        return process
    }

    private static var searchPath: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }

    static func find(_ name: String, override: String? = nil, bundled: URL? = nil) -> String? {
        let explicit = override.flatMap { ProcessInfo.processInfo.environment[$0] }
        return ([explicit, bundled?.path(percentEncoded: false)].compactMap { $0 } + searchPath.map { "\($0)/\(name)" })
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil, input: Data? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let log = FileManager.default.temporaryDirectory.appending(path: "uidesign-\(UUID().uuidString).log")
                let inputFile = log.appendingPathExtension("input")
                defer {
                    try? FileManager.default.removeItem(at: log)
                    if input != nil { try? FileManager.default.removeItem(at: inputFile) }
                }
                do {
                    try Data().write(to: log)
                    let file = try FileHandle(forWritingTo: log)
                    defer { try? file.close() }
                    let process = process(tool, arguments, in: directory)
                    process.standardOutput = file
                    process.standardError = file
                    if let input {
                        try input.write(to: inputFile, options: .atomic)
                        process.standardInput = try FileHandle(forReadingFrom: inputFile)
                    } else { process.standardInput = FileHandle.nullDevice }
                    try process.run()
                    process.waitUntilExit()
                    let data = try Data(contentsOf: log)
                    guard process.terminationStatus == 0 else {
                        let details = String(decoding: data, as: UTF8.self)
                        throw PreviewIssue(text: "\(URL(filePath: tool).lastPathComponent) 执行失败\n\(details.suffix(1800))")
                    }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
