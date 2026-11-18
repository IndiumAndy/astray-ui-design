import AppKit
import ImageIO
import Observation

@MainActor @Observable
final class SimulatorPreview {
    static let screen = CGSize(width: 402, height: 874)
    private static weak var active: SimulatorPreview?
    private static let deviceName = "UI Design Stage 2"
    private static let deviceType = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
    private static let runner = "local.uidesign.contacts"

    private(set) var frame: CGImage?
    private(set) var status: String?
    private(set) var isBusy = false
    private(set) var issue: PreviewIssue?
    private var stream: Process?
    private var requestedURL: URL?
    private var loadedURL: URL?
    private var device: String?
    private var axe: String?
    private var inputQueue: Task<Void, Never>?
    private var generation = 0

    func start(_ url: URL) async {
        guard !isBusy else { return }
        if stream != nil && loadedURL == url { return }
        Self.active?.stop(reset: Self.active !== self)
        Self.active = self
        isBusy = true
        issue = nil
        requestedURL = url
        let generation = self.generation
        defer { if self.generation == generation { isBusy = false } }
        do {
            let localAXe = PreviewTool.support.appending(path: "Tools/AXe/axe")
            guard let axe = PreviewTool.find("axe", override: "UIDESIGN_AXE", bundled: localAXe) else {
                throw PreviewIssue(text: "找不到 AXe。按项目 README 安装 AXe 2.0.4 后重试")
            }
            self.axe = axe
            status = "准备 iPhone 模拟器"
            let device = try await Self.previewDevice()
            guard self.generation == generation else { return }
            self.device = device
            async let boot: Data = PreviewTool.run("/usr/bin/xcrun", ["simctl", "bootstatus", device, "-b"])
            let app = try await PreviewBuild.shared.output("Phone")
            _ = try await boot
            guard self.generation == generation else { return }
            if loadedURL != url {
                status = "启动联系人预览"
                _ = try await PreviewTool.run("/usr/bin/xcrun", ["simctl", "install", device, app.path(percentEncoded: false)])
                guard self.generation == generation else { return }
                _ = try await PreviewTool.run("/usr/bin/xcrun", ["simctl", "launch", "--terminate-running-process", device, Self.runner, "--preview-url=\(url.absoluteString)"])
                guard self.generation == generation else { return }
                loadedURL = url
            }
            status = "连接模拟器画面"
            try beginStream(axe: axe, device: device, generation: generation)
        } catch {
            guard self.generation == generation else { return }
            fail(error)
        }
    }

    func stop(reset: Bool = false) {
        generation += 1
        inputQueue?.cancel()
        inputQueue = nil
        if let stream, stream.isRunning { stream.terminate() }
        stream = nil
        frame = nil
        status = nil
        isBusy = false
        if reset { loadedURL = nil }
    }

    func retry() async {
        guard let requestedURL else { return }
        stop(reset: true)
        await start(requestedURL)
    }

    func touch(from start: CGPoint, to end: CGPoint) {
        let startX = String(Int(start.x)), startY = String(Int(start.y))
        let endX = String(Int(end.x)), endY = String(Int(end.y))
        if hypot(end.x - start.x, end.y - start.y) < 8 {
            send(["tap", "-x", endX, "-y", endY])
        } else {
            send(["swipe", "--start-x", startX, "--start-y", startY, "--end-x", endX, "--end-y", endY, "--duration", "0.25"])
        }
    }

    func characters(_ text: String) {
        guard !text.isEmpty else { return }
        if text.utf8.allSatisfy({ (32...126).contains($0) }) {
            send(["type", "--", text], udidFirst: true)
        } else {
            // Transfer Unicode through this dedicated simulator’s clipboard.
            sendPaste(text)
        }
    }

    func key(_ usage: UInt16) { send(["key", String(usage)]) }

    func shortcut(_ usage: UInt16) { send(["key-combo", "--modifiers", "227", "--key", String(usage)]) }

    private func sendPaste(_ text: String) {
        enqueue { axe, device in
            _ = try await PreviewTool.run("/usr/bin/xcrun", ["simctl", "pbcopy", device], input: Data(text.utf8))
            _ = try await PreviewTool.run(axe, ["key-combo", "--modifiers", "227", "--key", "25", "--udid", device])
        }
    }

    private func send(_ arguments: [String], udidFirst: Bool = false) {
        enqueue { axe, device in
            let flags = ["--udid", device]
            let command = udidFirst ? Array(arguments.prefix(1)) + flags + arguments.dropFirst() : arguments + flags
            _ = try await PreviewTool.run(axe, command)
        }
    }

    private func enqueue(_ action: @escaping (String, String) async throws -> Void) {
        guard let device, let axe, frame != nil else { return }
        let previous = inputQueue
        let generation = self.generation
        inputQueue = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            do { try await action(axe, device) }
            catch { if self.generation == generation { self.issue = PreviewIssue(text: error.localizedDescription) } }
        }
    }

    private func beginStream(axe: String, device: String, generation: Int) throws {
        let process = PreviewTool.process(axe, ["stream-video", "--udid", device, "--format", "raw", "--fps", "20", "--scale", "0.5", "--quality", "70"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        stream = process
        let input = output.fileHandleForReading
        Task.detached { [weak self] in
            defer { try? input.close() }
            do {
                while let length = try Self.readExactly(4, from: input) {
                    let count = length.reduce(0) { ($0 << 8) + Int($1) }
                    guard count > 0, count <= 4_194_304,
                          let bytes = try Self.readExactly(count, from: input) else { break }
                    if let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                       let frame = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                        await self?.receive(frame, generation: generation)
                    }
                }
            } catch { }
            if process.isRunning { process.terminate() }
            await self?.streamEnded(generation: generation)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if let self, self.generation == generation, self.frame == nil, self.stream != nil {
                self.stop(reset: true)
                self.fail(PreviewIssue(text: "未收到模拟器画面，请重试"))
            }
        }
    }

    private nonisolated static func readExactly(_ count: Int, from input: FileHandle) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try input.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }

    private func receive(_ frame: CGImage, generation: Int) {
        guard self.generation == generation else { return }
        self.frame = frame
        status = nil
    }

    private func streamEnded(generation: Int) {
        guard self.generation == generation else { return }
        stop(reset: true)
        fail(PreviewIssue(text: "模拟器画面已断开，请重试"))
    }

    private func fail(_ error: Error) {
        status = nil
        issue = PreviewIssue(text: error.localizedDescription)
    }

    private static func previewDevice() async throws -> String {
        let data = try await PreviewTool.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"])
        let devices = try JSONDecoder().decode(DeviceList.self, from: data).devices
        if let device = devices.values.flatMap({ $0 }).first(where: { $0.name == deviceName && $0.deviceTypeIdentifier == deviceType }) {
            return device.udid
        }
        guard let runtime = devices.keys.filter({ $0.contains(".iOS-") }).max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else {
            throw PreviewIssue(text: "请在 Xcode 安装 iOS 模拟器运行时后重试")
        }
        let result = try await PreviewTool.run("/usr/bin/xcrun", ["simctl", "create", deviceName, deviceType, runtime])
        return String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }

    private struct Device: Decodable {
        let name: String
        let udid: String
        let deviceTypeIdentifier: String?
    }
}
