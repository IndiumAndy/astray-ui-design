import AppKit
import Combine
import os
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let uiDesignProject = Self(exportedAs: "local.uidesign.project", conformingTo: .json)
    static let uiDesignComponent = Self(exportedAs: "local.uidesign.component", conformingTo: .data)
}

@Observable
final class DesignFile: ReferenceFileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.uiDesignProject]

    let objectWillChange = ObservableObjectPublisher()
    // Editing and notifications run on the main actor. The document reader
    // and writer can take a consistent value snapshot from a background task.
    private let storage: OSAllocatedUnfairLock<DesignProject>
    @MainActor @ObservationIgnored private weak var nativeDocument: NSDocument?
    @MainActor @ObservationIgnored private var pendingAutosave: Task<Void, Never>?

    init(project: DesignProject = DesignProject()) {
        storage = OSAllocatedUnfairLock(initialState: project)
    }

    var project: DesignProject {
        access(keyPath: \.project)
        return storage.withLock { $0 }
    }

    convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DesignFileError.unreadable }
        self.init(project: try Self.read(data))
    }

    @MainActor func attach(to document: NSDocument) { nativeDocument = document }

    @MainActor func apply(_ project: DesignProject, undoManager: UndoManager?, action: String) {
        let previous = self.project
        guard previous != project else { return }

        // The committed gesture owns a single group. Keep native field
        // editing's automatic grouping in place outside this transaction.
        let automaticGrouping = undoManager?.groupsByEvent == true && undoManager?.groupingLevel == 0
        if automaticGrouping { undoManager?.groupsByEvent = false }
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.endUndoGrouping()
            if automaticGrouping { undoManager?.groupsByEvent = true }
            scheduleAutosave()
        }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] file in
            MainActor.assumeIsolated {
                file.apply(previous, undoManager: undoManager, action: action)
            }
        }
        undoManager?.setActionName(action)

        objectWillChange.send()
        withMutation(keyPath: \.project) {
            storage.withLock { $0 = project }
        }
    }

    @MainActor private func scheduleAutosave() {
        pendingAutosave?.cancel()
        // Until the first explicit save, AppKit owns untitled recovery.
        guard let document = nativeDocument, document.fileURL != nil else { return }
        pendingAutosave = Task { @MainActor [weak document] in
            do {
                try await Task.sleep(for: .milliseconds(650))
                guard let document, document.fileURL != nil, document.hasUnautosavedChanges else { return }
                try await document.autosave(withImplicitCancellability: false)
            } catch {
                if !Task.isCancelled { _ = document?.presentError(error) }
            }
        }
    }

    func snapshot(contentType: UTType) throws -> DesignProject { project }

    func fileWrapper(snapshot: DesignProject, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encoded(snapshot))
    }

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
