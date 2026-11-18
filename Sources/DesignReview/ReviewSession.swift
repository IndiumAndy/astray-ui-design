import Observation
import SwiftUI

enum ReviewState: String, CaseIterable, Identifiable {
    case blank, selection, flow

    var id: Self { self }

    var reviewTitle: String {
        switch self {
        case .blank: "空白画板"
        case .selection: "选中组合"
        case .flow: "连线与 iPhone"
        }
    }

    var documentTitle: String {
        switch self {
        case .blank: "未命名设计"
        case .selection: "设置页"
        case .flow: "通讯录"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .blank: "1"
        case .selection: "2"
        case .flow: "3"
        }
    }
}

enum ReviewDevice: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone, largePhone

    var id: Self { self }

    var name: String {
        self == .phone ? "iPhone" : "iPhone 大屏"
    }

    var size: CGSize {
        switch self {
        case .phone: CGSize(width: 390, height: 844)
        case .largePhone: CGSize(width: 430, height: 932)
        }
    }

    var dimensions: String { "\(Int(size.width)) × \(Int(size.height))" }
}

enum CanvasZoom: String, CaseIterable, Identifiable {
    case fit, actual, half, quarter

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: "适合窗口"
        case .actual: "100%"
        case .half: "50%"
        case .quarter: "25%"
        }
    }

    var factor: CGFloat? {
        switch self {
        case .fit: nil
        case .actual: 1
        case .half: 0.5
        case .quarter: 0.25
        }
    }
}

enum NavigatorTab: String, CaseIterable, Identifiable {
    case components, layers

    var id: Self { self }
    var title: String { self == .components ? "组件" : "图层" }
}

enum ReviewDirection: String, CaseIterable, Identifiable {
    case horizontal, vertical

    var id: Self { self }
    var title: String { self == .horizontal ? "横排" : "竖排" }
    var symbol: String { self == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2" }
}

struct ReviewArrangement {
    static let spacingRange = 0...32
    var direction = ReviewDirection.horizontal
    var spacing = 12
}

@MainActor @Observable
final class ReviewSession {
    let design: DesignEditing?
    private(set) var state: ReviewState
    private var deviceSample = ReviewDevice.phone
    private var inspectorOverride: Bool?
    private let defaults: UserDefaults
    private static let snapPreference = "canvasSnapEnabled"

    init(state: ReviewState = .blank, document: DesignFile? = nil, defaults: UserDefaults = .standard) {
        self.state = state
        self.defaults = defaults
        self.design = document.map(DesignEditing.init(file:))
        snapEnabled = defaults.object(forKey: Self.snapPreference) as? Bool ?? true
        open(state)
    }

    var editor: DesignEditing? { state == .blank ? design : nil }

    var device: ReviewDevice {
        get { editor?.page.device ?? deviceSample }
        set {
            if let editor { editor.setDevice(newValue) }
            else { deviceSample = newValue }
        }
    }

    var trailingPaneVisible: Bool { inspectorOverride ?? (editor?.selection != nil || state == .selection) }

    func toggleInspector() { inspectorOverride = !trailingPaneVisible }

    var selectedZoomPreset: CanvasZoom? { editor?.magnification == nil ? zoom : nil }

    func setZoom(_ newValue: CanvasZoom) {
        zoom = newValue
        editor?.magnification = nil
        if newValue == .fit { editor?.pan = .zero }
    }

    private(set) var searchRequest = 0
    private(set) var zoom = CanvasZoom.fit
    var libraryVisible = true
    var navigatorTab = NavigatorTab.components
    var previewVisible = false
    var snapEnabled: Bool {
        didSet { defaults.set(snapEnabled, forKey: Self.snapPreference) }
    }
    var arrangement = ReviewArrangement()

    func open(_ state: ReviewState) {
        self.state = state
        libraryVisible = true
        navigatorTab = state == .selection ? .layers : .components
        inspectorOverride = nil
        previewVisible = state == .flow
        arrangement = ReviewArrangement()
    }

    func requestSearch() {
        libraryVisible = true
        navigatorTab = .components
        searchRequest += 1
    }
}

struct CanvasZoomOptions: View {
    let session: ReviewSession

    var body: some View {
        ForEach(CanvasZoom.allCases) { zoom in
            Button {
                session.setZoom(zoom)
            } label: {
                if session.selectedZoomPreset == zoom {
                    Label(zoom.title, systemImage: "checkmark")
                } else {
                    Text(zoom.title)
                }
            }
        }
    }
}

struct ReviewLaunch {
    let state: ReviewState
    let focusSearch: Bool
    let appearance: ColorScheme?
    let width: CGFloat
    let height: CGFloat

    init(arguments: [String]) {
        state = Self.value(after: "--design-review", in: arguments)
            .flatMap(ReviewState.init) ?? .blank
        focusSearch = arguments.contains("--focus-library-search")
        appearance = arguments.contains("--review-dark") ? .dark : nil
        let compact = arguments.contains("--compact-review")
        width = compact ? 1080 : 1320
        height = compact ? 640 : 800
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        return arguments.dropFirst(index + 1).first
    }
}
