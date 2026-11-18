import Foundation

enum ContactField: String, Codable, CaseIterable, Identifiable, Sendable {
    case name, phone, nickname, note

    var id: Self { self }
    var title: String {
        switch self {
        case .name: "姓名"
        case .phone: "电话"
        case .nickname: "昵称"
        case .note: "备注"
        }
    }
    var isEditable: Bool { self == .nickname || self == .note }
}

struct DesignContact: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var phone: String
    var nickname = ""
    var note = ""

    subscript(field: ContactField) -> String {
        switch field {
        case .name: name
        case .phone: phone
        case .nickname: nickname
        case .note: note
        }
    }
}

struct RuntimeDesign: Codable, Equatable, Sendable {
    let entry: String
    let pages: [RuntimePage]
    let contacts: [DesignContact]
}

struct RuntimePage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let width: Double
    var layers: [RuntimeLayer]
    var height: CGFloat?
    var contentTop: CGFloat?
    var adaptive: Bool?
}

struct RuntimeLayer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let field: ContactField?
    var destination: String?
    let savesContact: Bool?
    let isOn: Bool
    var parent: String?
    var geometry: LayerGeometry?
    var overrides: [String: LayerGeometry]?
    var styleHeight: CGFloat?
    var cornerRadius: CGFloat?
    var inputType: String?
    var inputLabel: String?
    var fieldHint: String?
    var secondaryButton: Bool?
    var image: Data?
    var behavior: LayerBehavior?
    var contentMinimum: CGFloat?

    var isContainer: Bool { ["layout", "labeledInput", "listRow", "actionBar"].contains(kind) }
    var minimumWidth: CGFloat {
        if isContainer { return 44 }
        return switch kind {
        case "contactList": 120
        case "setting": 116
        case "toggle": 52
        case "divider": 4
        default: 44
        }
    }
    var isActionRow: Bool { kind == "listRow" && behavior?.action != nil }

    var minimumHeight: CGFloat {
        if isActionRow { return 44 }
        if isContainer { return 4 }
        return switch kind {
        case "title", "label": 24
        case "divider": 1
        case "image": 44
        case "contactList": 56
        default: 44
        }
    }
    var textPadding: CGFloat { kind == "button" || kind == "input" ? 24 : 0 }
}
