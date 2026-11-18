import Foundation

extension DesignProject {
    static func contactExample() -> Self {
        var project = Self()
        project.page.title = "联系人"
        var detail = DesignPage()
        detail.title = "联系人详情"

        var list = exampleLayer(.contactList, "", y: 140, height: 168)
        list.destination = detail.id
        project.page.layers = [exampleLayer(.title, "联系人", y: 88, height: 44), list]

        var save = exampleLayer(.button, "保存", y: 336, height: 48)
        save.savesContact = true
        detail.layers = [
            exampleLayer(.title, "姓名", y: 116, height: 44, field: .name),
            exampleLayer(.title, "电话", y: 160, height: 32, field: .phone),
            exampleLayer(.input, "昵称", y: 216, height: 48, field: .nickname),
            exampleLayer(.input, "备注", y: 272, height: 48, field: .note),
            save
        ]
        project.additionalPages = [detail]
        project.contacts = [
            DesignContact(id: "lin", name: "林乔", phone: "202-555-0147"),
            DesignContact(id: "chen", name: "陈亦舟", phone: "202-555-0162"),
            DesignContact(id: "shen", name: "沈知夏", phone: "202-555-0183"),
            DesignContact(id: "zhou", name: "周遥", phone: "202-555-0116")
        ]
        return project
    }

    private static func exampleLayer(_ kind: LayerKind, _ text: String, y: CGFloat, height: CGFloat,
                                     field: ContactField? = nil) -> DesignLayer {
        var layer = DesignLayer(kind: kind, frame: CGRect(x: 24, y: y, width: 342, height: height))
        layer.text = text
        layer.field = field
        return layer
    }

    func runtime(startingAt id: UUID? = nil) -> RuntimeDesign {
        RuntimeDesign(
            entry: page(withID: id).id.uuidString,
            pages: pages.map { $0.runtime(styles: buttonStyles ?? []) },
            contacts: contacts ?? []
        )
    }
}

extension DesignPage {
    func runtime(styles: [ButtonDesignStyle], contacts: [DesignContact] = [], canvas: Bool = false) -> RuntimePage {
        let stylesByID = Dictionary(uniqueKeysWithValues: styles.map { ($0.id, $0) })
        func layersFor(_ layer: DesignLayer, parent: UUID?, inputLabel: String? = nil) -> [RuntimeLayer] {
            let style = layer.styleID.flatMap { stylesByID[$0] }
            let isSetting = layer.kind == .setting
            var output = RuntimeLayer(
                id: layer.id.uuidString, kind: layer.kind.rawValue,
                text: isSetting ? layer.children[0].text : layer.text,
                x: layer.frame.minX, y: layer.frame.minY, width: layer.frame.width, height: layer.frame.height,
                field: layer.field, destination: layer.destination?.uuidString, savesContact: layer.savesContact,
                isOn: isSetting ? layer.children[1].isOn : layer.isOn, parent: parent?.uuidString,
                geometry: layer.geometry, overrides: layer.deviceLayouts, styleHeight: style?.height,
                cornerRadius: layer.cornerRadius ?? style?.radius, inputType: layer.inputType?.rawValue, inputLabel: inputLabel,
                fieldHint: layer.fieldHint, secondaryButton: layer.secondaryButton, image: layer.image,
                behavior: isSetting ? layer.children[1].behavior ?? layer.behavior : layer.behavior
            )
            if canvas && layer.kind == .contactList {
                if let sample = layer.behavior?.list?.sample {
                    if sample.resolvedState == .ready { output.contentMinimum = CGFloat(sample.rows.count * (layer.behavior?.list?.rowHeight ?? 56)) }
                    if sample.resolvedState == .empty && layer.behavior?.list?.emptyAction != nil { output.contentMinimum = 88 }
                } else if !contacts.isEmpty { output.contentMinimum = CGFloat(contacts.count) * 56 }
            }
            if canvas && layer.kind == .input && layer.behavior?.state == .error {
                output.contentMinimum = 64
            }
            let label = layer.kind == .labeledInput ? layer.children.first(where: { $0.kind == .label })?.text : nil
            return [output] + (isSetting ? [] : layer.children.flatMap {
                layersFor($0, parent: layer.id, inputLabel: $0.kind == .input ? label : nil)
            })
        }
        return RuntimePage(id: id.uuidString, title: title, width: size.width,
                           layers: layers.flatMap { layersFor($0, parent: nil) }, height: size.height, contentTop: safeTop,
                           adaptive: customSize != nil || deviceLayout != .phone ||
                             allLayers.contains { $0.geometry != nil || $0.deviceLayouts != nil })
    }
}
