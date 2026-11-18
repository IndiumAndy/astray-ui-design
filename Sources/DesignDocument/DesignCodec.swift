import Foundation

enum DesignCodec {
    static func read(_ data: Data) throws -> DesignProject {
        var decoded: DesignProject
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard (1...DesignProject.currentVersion).contains(header.version) else {
                throw DesignFileError.unsupportedVersion(header.version)
            }
            decoded = try decoder.decode(DesignProject.self, from: data)
            try decoded.migrate()
        } catch let error as DesignFileError {
            throw error
        } catch {
            throw DesignFileError.unreadable
        }
        return try decoded.validated()
    }

    static func encoded(_ project: DesignProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project.validated())
    }

    private struct Header: Decodable {
        let version: Int
    }
}
