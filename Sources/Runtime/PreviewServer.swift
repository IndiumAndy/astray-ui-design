import Foundation
import Network
import os

final class PreviewServer: Sendable {
    private struct Response: Sendable {
        let mime: String
        let contents: Data
    }

    private struct Content: Sendable {
        var design = Data()
        var assets: [String: Response] = [:]
    }

    private let content = OSAllocatedUnfairLock(initialState: Content())
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local.uidesign.preview-server")
    private let prefix = "/\(UUID().uuidString)/"

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    deinit { listener.cancel() }

    func open() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    if let port = self.listener.port,
                       let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.prefix)") {
                        continuation.resume(returning: url)
                    } else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.receive(on: connection)
                self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            }
            listener.start(queue: queue)
        }
    }

    func publish(_ design: RuntimeDesign) throws {
        let data = try RuntimeAssets.encode(design)
        content.withLock { $0.design = data }
    }

    func serveWeb(from dist: URL) throws {
        let pages = try FileManager.default.contentsOfDirectory(at: dist.appending(path: "assets"), includingPropertiesForKeys: nil)
        var assets = ["": Response(mime: "text/html; charset=utf-8", contents: try Data(contentsOf: dist.appending(path: "index.html")))]
        for file in pages {
            let mime: String
            switch file.pathExtension {
            case "js": mime = "text/javascript; charset=utf-8"
            case "css": mime = "text/css; charset=utf-8"
            default: continue
            }
            assets["assets/\(file.lastPathComponent)"] = Response(mime: mime, contents: try Data(contentsOf: file))
        }
        let responses = assets
        content.withLock { $0.assets = responses }
    }

    private func receive(on connection: NWConnection, incomplete: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            let request = incomplete + data
            guard request.count <= 8192 else { connection.cancel(); return }
            let separator = Data("\r\n\r\n".utf8)
            guard request.range(of: separator) != nil else {
                if complete { connection.cancel() }
                else { self.receive(on: connection, incomplete: request) }
                return
            }
            let requestLine = String(decoding: request, as: UTF8.self).prefix { $0 != "\r\n" && $0 != "\r" && $0 != "\n" }
            let words = requestLine.split(separator: " ")
            let response = words.count == 3 && words[0] == "GET" ? self.resource(at: words[1]) : nil
            let status = response == nil ? "404 Not Found" : "200 OK"
            let body = response?.contents ?? Data()
            let type = response?.mime ?? "text/plain"
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func resource(at path: Substring) -> Response? {
        guard path.hasPrefix(prefix) else { return nil }
        let key = String(path.dropFirst(prefix.count))
        return content.withLock { content in
            key == "design.json" ? Response(mime: "application/json; charset=utf-8", contents: content.design) : content.assets[key]
        }
    }
}
