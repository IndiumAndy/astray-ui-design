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

enum ReviewDevice: String, CaseIterable, Identifiable {
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
    case fit, half, quarter

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: "适合窗口"
        case .half: "50%"
        case .quarter: "25%"
        }
    }

    var factor: CGFloat? {
        switch self {
        case .fit: nil
        case .half: 0.5
        case .quarter: 0.25
        }
    }
}

@MainActor @Observable
final class ReviewSession {
    private(set) var state = ReviewState.blank
    private(set) var searchRequest = 0
    var device = ReviewDevice.phone
    var zoom = CanvasZoom.fit
    var libraryVisible = true
    var trailingPaneVisible = false
    var snapEnabled = true

    func open(_ state: ReviewState) {
        self.state = state
        libraryVisible = true
        trailingPaneVisible = state != .blank
    }

    func newDesign() {
        device = .phone
        zoom = .fit
        open(.blank)
    }

    func requestSearch() {
        libraryVisible = true
        searchRequest += 1
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
