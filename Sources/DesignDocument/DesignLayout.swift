import CoreGraphics
import Foundation

enum DesignInputType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, email, password

    var id: Self { self }
    var title: String {
        switch self {
        case .text: "普通文本"
        case .email: "电子邮件"
        case .password: "密码"
        }
    }
}

struct ButtonDesignStyle: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var height: CGFloat
    var radius: CGFloat
}

enum ReferenceLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case login, settings, listDetail
    var id: Self { self }
    var title: String {
        switch self {
        case .login: "登录"
        case .settings: "设置"
        case .listDetail: "列表与详情"
        }
    }

    var inset: CGFloat { self == .login ? 24 : 20 }

    func guides(in page: DesignPage) -> [CGRect] {
        let width = page.size.width - 2 * inset
        let fields: [(CGFloat, CGFloat)]
        switch self {
        case .login: fields = [(32, 44), (104, 48), (168, 48), (240, 48)]
        case .settings: fields = [(24, 44), (84, 56), (152, 56), (220, 56), (288, 56)]
        case .listDetail: fields = [(24, 44), (84, 56), (152, 56), (220, 56)]
        }
        return fields.map { y, height in CGRect(x: inset, y: page.safeTop + y, width: width, height: height) }
    }
}

struct ReferenceImage: Codable, Equatable, Sendable {
    static let maximumBytes = 12_000_000
    let data: Data
    let name: String
    var opacity: CGFloat = 0.35
    var isLocked = true
    var isHidden = false
    var offset = CGPoint.zero

    var isValid: Bool {
        !data.isEmpty && data.count <= Self.maximumBytes && (0...1).contains(opacity)
        && offset.x.isFinite && offset.y.isFinite
    }
}
