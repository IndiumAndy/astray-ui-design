import Foundation

extension DesignProject {
    static func interactionExample() -> Self {
        var project = Self()
        project.page.title = "通讯录"
        var settings = DesignPage()
        settings.title = "设置"
        var help = DesignPage()
        help.title = "关于通讯录"
        var detail = DesignPage()
        detail.title = "联系人详情"
        var create = DesignPage()
        create.title = "新建联系人"

        var list = ListDesign()
        list.emptyButton = "添加联系人"
        list.emptyAction = .page(.navigate, create.id)
        list.sample.rows = [
            row("lin", "林乔", "202-555-0147"),
            row("chen", "陈亦舟", "202-555-0162"),
            row("shen", "沈知夏", "202-555-0183")
        ]
        var records = control(.contactList, "", y: 240, height: 56)
        records.behavior = LayerBehavior(action: .page(.navigate, detail.id), list: list)
        var search = control(.input, "搜索联系人", y: 172)
        search.behavior = LayerBehavior(submissionKey: "query", changeAction: "searchContacts")
        var settingsLink = control(.listRow, "", y: 116)
        settingsLink.children[0].text = "设置"
        settingsLink.behavior = LayerBehavior(action: .page(.navigate, settings.id))
        let helpButton = button("关于", action: .page(.sheet, help.id), y: 420, secondary: true)
        project.page.layers = [control(.title, "通讯录", y: 72), settingsLink, search,
                               section([records, helpButton], y: 240)]

        var notifications = control(.setting, "", y: 120)
        notifications.children[0].text = "消息通知"
        notifications.children[1].behavior = LayerBehavior(
            binding: FieldBinding(key: "notifications", sample: .flag(true)), changeAction: "setNotifications"
        )
        var nickname = formField("昵称", key: "nickname", form: "profile")
        nickname.children[1].behavior?.binding = FieldBinding(key: "nickname", sample: .text("小林"))
        let name = formField("姓名", key: "name", form: "profile", rules: FieldRules(required: true, message: "请输入姓名"))
        let password = formField("密码", key: "password", form: "profile", type: .password,
                                 rules: FieldRules(required: true, minimum: 8, maximum: 20))
        let email = formField("邮箱", key: "email", form: "profile", type: .email,
                              rules: FieldRules(required: true, email: true))
        var signature = formField("个人签名", key: "signature", form: "signature")
        signature.children[1].behavior?.rules = FieldRules(maximum: 80)
        let signatureForm = button("保存签名", action: DesignAction(kind: .submit, name: "saveSignature", form: "signature"),
                                   secondary: true)
        let busy = button("同步联系人", action: DesignAction(kind: .named, name: "syncContacts"), secondary: true)
        var disabled = button("删除账户", action: DesignAction(kind: .named, name: "deleteAccount"), secondary: true)
        disabled.behavior?.state = .disabled
        settings.layers = [
            control(.title, "设置", y: 72),
            section([notifications, nickname, name, password, email,
                     button("保存资料", action: DesignAction(kind: .submit, name: "saveProfile", form: "profile")),
                     signature, signatureForm, busy, disabled], y: 124)
        ]

        help.layers = [
            control(.title, "关于通讯录", y: 72),
            control(.label, "在通讯录中查看和整理联系人。", y: 128),
            button("完成", action: DesignAction(kind: .dismiss), y: 192)
        ]

        var nameTitle = control(.title, "姓名", y: 72)
        nameTitle.behavior = LayerBehavior(binding: FieldBinding(source: .record, key: "name", sample: .text("林乔")))
        var phone = control(.label, "电话", y: 124)
        phone.behavior = LayerBehavior(binding: FieldBinding(source: .record, key: "phone", sample: .text("202-555-0147")))
        detail.layers = [nameTitle, phone]

        create.layers = [
            control(.title, "新建联系人", y: 72),
            section([
                formField("姓名", key: "name", form: "contact", rules: FieldRules(required: true)),
                formField("电话", key: "phone", form: "contact"),
                button("添加", action: DesignAction(kind: .submit, name: "addContact", form: "contact"))
            ], y: 124)
        ]
        project.additionalPages = [settings, help, detail, create]
        return project
    }

    private static func row(_ id: String, _ name: String, _ phone: String) -> DesignRecord {
        DesignRecord(id: id, fields: ["name": .text(name), "phone": .text(phone)])
    }

    private static func control(_ kind: LayerKind, _ text: String, y: CGFloat = 0, height: CGFloat = 48) -> DesignLayer {
        var layer = DesignLayer(kind: kind, frame: CGRect(x: 24, y: y, width: 342, height: height))
        layer.text = text
        if kind == .title { layer.geometry = LayerGeometry(width: .fill, height: .content) }
        return layer
    }

    private static func button(_ title: String, action: DesignAction, y: CGFloat = 0, secondary: Bool = false) -> DesignLayer {
        var button = control(.button, title, y: y)
        button.behavior = LayerBehavior(action: action)
        button.secondaryButton = secondary ? true : nil
        return button
    }

    private static func formField(_ title: String, key: String, form: String,
                                  type: DesignInputType = .text, rules: FieldRules? = nil) -> DesignLayer {
        var field = control(.labeledInput, "")
        field.children[0].text = title
        field.children[1].text = ""
        field.children[1].inputType = type
        field.children[1].behavior = LayerBehavior(form: form, submissionKey: key, rules: rules)
        return field
    }

    private static func section(_ children: [DesignLayer], y: CGFloat) -> DesignLayer {
        var group = control(.layout, "", y: y)
        group.geometry = LayerGeometry(width: .fill, height: .content, arrangement: .vertical, gap: 12)
        group.children = children.map { child in
            var child = child
            child.frame.origin = .zero
            child.geometry = (child.geometry ?? LayerGeometry()).applying(LayerGeometry(width: .fill))
            return child
        }
        return group
    }
}
