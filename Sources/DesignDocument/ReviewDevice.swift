import CoreGraphics
import Foundation

enum ReviewDevice: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone, largePhone, tablet, desktop

    var id: Self { self }

    var name: String {
        switch self {
        case .phone: "iPhone"
        case .largePhone: "iPhone 大屏"
        case .tablet: "iPad"
        case .desktop: "桌面"
        }
    }

    var size: CGSize {
        switch self {
        case .phone: CGSize(width: 390, height: 844)
        case .largePhone: CGSize(width: 430, height: 932)
        case .tablet: CGSize(width: 820, height: 1180)
        case .desktop: CGSize(width: 1440, height: 900)
        }
    }

    var dimensions: String { "\(Int(size.width)) × \(Int(size.height))" }
}
