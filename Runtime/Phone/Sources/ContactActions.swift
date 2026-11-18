import Foundation

struct ContactSave: Encodable {
    let contactID: String
    let values: [String: String]
}

enum ContactActions {
    static func onAction(_ event: DesignEvent) -> DesignActionResult {
        // Replace with the host's business logic.
        DesignActionResult()
    }

    static func onSaveContact(_ event: ContactSave) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        print("saveContact \(String(decoding: data, as: UTF8.self))")
    }
}
