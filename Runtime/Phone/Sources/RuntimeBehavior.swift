import Foundation

enum DesignValue: Codable, Equatable, Sendable {
    case text(String), flag(Bool), number(Double)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else if let flag = try? value.decode(Bool.self) { self = .flag(flag) }
        else { self = .number(try value.decode(Double.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .text(let text): try value.encode(text)
        case .flag(let flag): try value.encode(flag)
        case .number(let number): try value.encode(number)
        }
    }

    var text: String {
        switch self {
        case .text(let text): text
        case .flag(let value): value ? "true" : "false"
        case .number(let number): number.formatted(.number.grouping(.never))
        }
    }

    var flag: Bool { self == .flag(true) }
}

enum BindingSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case application, record
    var id: Self { self }
    var title: String { self == .application ? "由应用传入" : "由列表行传入" }
}

struct FieldBinding: Codable, Equatable, Sendable {
    var source: BindingSource = .application
    var key: String
    var sample: DesignValue?
}

enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case navigate, sheet, back, dismiss, named, submit
    var id: Self { self }
    var title: String {
        switch self {
        case .navigate: "打开页面"
        case .sheet: "弹出面板"
        case .back: "返回"
        case .dismiss: "关闭面板"
        case .named: "业务动作"
        case .submit: "提交表单"
        }
    }
}

struct DesignAction: Codable, Equatable, Sendable {
    var kind: ActionKind
    var target: String? = nil
    var name: String? = nil
    var form: String? = nil

    static func page(_ kind: ActionKind, _ id: UUID) -> Self { .init(kind: kind, target: id.uuidString) }
}

struct FieldRules: Codable, Equatable, Sendable {
    var required = false
    var minimum: Int?
    var maximum: Int?
    var email = false
    var message: String?

    func error(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return required ? message ?? "请填写此字段" : nil }
        if let minimum, value.count < minimum { return message ?? "至少输入 \(minimum) 个字符" }
        if let maximum, value.count > maximum { return message ?? "最多输入 \(maximum) 个字符" }
        if email && trimmed.range(of: #"^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$"#, options: .regularExpression) == nil {
            return message ?? "请输入有效的邮箱地址"
        }
        return nil
    }
}

enum ControlState: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, disabled, busy, error
    var id: Self { self }
    var title: String {
        switch self {
        case .normal: "正常"
        case .disabled: "禁用"
        case .busy: "处理中"
        case .error: "错误"
        }
    }
    var blocksInput: Bool { self == .disabled || self == .busy }
}

enum ListState: String, Codable, CaseIterable, Identifiable, Sendable {
    case ready, empty, loading, failed
    var id: Self { self }
    var title: String {
        switch self {
        case .ready: "有数据"
        case .empty: "空数据"
        case .loading: "加载中"
        case .failed: "加载失败"
        }
    }
}

struct DesignRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var fields: [String: DesignValue]
}

struct ListContent: Codable, Equatable, Sendable {
    var state: ListState = .ready
    var rows: [DesignRecord] = []
    var message: String?

    var resolvedState: ListState { state == .ready && rows.isEmpty ? .empty : state }
}

struct ListDesign: Codable, Equatable, Sendable {
    var key = "contacts"
    var titleKey = "name"
    var detailKey = "phone"
    var sample = ListContent()
    var rowHeight: Int?
    var emptyText = "暂无联系人"
    var loadingText = "正在加载"
    var failureText = "无法加载联系人"
    var emptyButton = ""
    var emptyAction: DesignAction?

    func message(for content: ListContent) -> String {
        if let message = content.message { return message }
        switch content.resolvedState {
        case .ready: return ""
        case .empty: return emptyText
        case .loading: return loadingText
        case .failed: return failureText
        }
    }
}

struct LayerBehavior: Codable, Equatable, Sendable {
    var binding: FieldBinding?
    var form: String?
    var submissionKey: String?
    var rules: FieldRules?
    var action: DesignAction?
    var changeAction: String?
    var state: ControlState?
    var stateMessage: String?
    var list: ListDesign?
}

struct RuntimeData: Equatable, Sendable {
    var values: [String: DesignValue] = [:]
    var lists: [String: ListContent] = [:]
    var controlStates: [String: ControlState] = [:]
}

struct DesignEvent: Encodable, Equatable, Sendable {
    let name: String
    let pageID: String
    let layerID: String
    var form: String?
    var values: [String: DesignValue] = [:]
    var record: DesignRecord?
}

struct DesignActionResult: Equatable, Sendable {
    var fieldErrors: [String: String] = [:]
}

struct FormSubmission {
    let fields: [RuntimeLayer]
    let values: [String: DesignValue]
    let errors: [String: String]

    init(form: String, layers: [RuntimeLayer], value: (RuntimeLayer) -> DesignValue,
         state: (RuntimeLayer) -> ControlState) {
        fields = layers.filter {
            ["input", "toggle", "setting"].contains($0.kind) && $0.behavior?.form == form && !state($0).blocksInput
        }
        var values: [String: DesignValue] = [:]
        var errors: [String: String] = [:]
        for field in fields {
            let submitted = value(field)
            if values.updateValue(submitted, forKey: field.eventKey) != nil {
                errors[field.id] = "表单内的提交键重复"
            } else if let error = field.behavior?.rules?.error(for: submitted.text) {
                errors[field.id] = error
            }
        }
        self.values = values
        self.errors = errors
    }

    func errorsByLayer(_ result: DesignActionResult) -> [String: String] {
        var errors: [String: String] = [:]
        for field in fields {
            if let error = result.fieldErrors[field.eventKey], !error.isEmpty { errors[field.id] = error }
        }
        return errors
    }
}

extension RuntimeLayer {
    var eventKey: String { behavior?.submissionKey ?? behavior?.binding?.key ?? field?.rawValue ?? id }

    func originalValue(data: RuntimeData, record: DesignRecord?, legacy: String? = nil) -> DesignValue {
        if let binding = behavior?.binding {
            let values = binding.source == .record ? record?.fields : data.values
            if let value = values?[binding.key] ?? binding.sample { return value }
        }
        if let legacy { return .text(legacy) }
        switch kind {
        case "toggle", "setting": return .flag(isOn)
        case "input": return .text("")
        default: return .text(text)
        }
    }
}
