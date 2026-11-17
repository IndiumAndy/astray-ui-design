import SwiftUI

// Keep Astryx's Neutral 10 pt element and 12 pt container radii in the iOS composition.
private enum SampleShape {
    static let field: CGFloat = 10
    static let group: CGFloat = 12
}

struct SettingsSample: View {
    let palette: IOSSamplePalette

    static let headingGap: CGFloat = 12
    static let sectionHeaderHeight: CGFloat = 24
    static let rowHeight: CGFloat = 52
    private static let symbolWidth: CGFloat = 22
    private static let textInset = IOSLayout.rowInset + symbolWidth + IOSLayout.rowSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IOSPageHeading(title: "设置")
                .padding(.bottom, Self.headingGap)

            sectionLabel("通知")
            VStack(spacing: 0) {
                row("消息通知", symbol: "bell", enabled: true)
                separator
                row("邮件摘要", symbol: "envelope", enabled: false)
            }
            .background(palette.cell, in: .rect(cornerRadius: SampleShape.group))

            sectionLabel("账号")
                .padding(.top, 24)
            VStack(spacing: 0) {
                row("个人资料", symbol: "person.crop.circle")
                separator
                row("隐私与安全", symbol: "lock")
            }
            .background(palette.cell, in: .rect(cornerRadius: SampleShape.group))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, IOSLayout.pageInset)
    }

    static func selectedBounds(for device: ReviewDevice) -> CGRect {
        CGRect(
            x: IOSLayout.pageInset,
            y: IOSLayout.statusHeight + IOSLayout.headingHeight + headingGap + sectionHeaderHeight,
            width: device.size.width - IOSLayout.pageInset * 2,
            height: rowHeight
        )
    }

    private var separator: some View {
        palette.separator
            .frame(height: 0.5)
            .padding(.leading, Self.textInset)
    }

    private func sectionLabel(_ title: String) -> some View {
        IOSSectionLabel(title: title, palette: palette, leadingInset: Self.textInset)
            .frame(height: Self.sectionHeaderHeight, alignment: .topLeading)
    }

    private func row(_ title: String, symbol: String, enabled: Bool? = nil) -> some View {
        HStack(spacing: IOSLayout.rowSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: Self.symbolWidth)
            Text(title)
                .font(.system(size: 17))
            Spacer()
            if let enabled {
                IOSSampleSwitch(enabled: enabled, palette: palette)
            } else {
                IOSDisclosure(palette: palette)
            }
        }
        .padding(.horizontal, IOSLayout.rowInset)
        .frame(height: Self.rowHeight)
    }
}

private struct IOSSampleSwitch: View {
    let enabled: Bool
    let palette: IOSSamplePalette

    var body: some View {
        Capsule()
            .fill(enabled ? palette.switchOn : palette.search)
            .overlay(alignment: enabled ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 51, height: 31)
            .accessibilityLabel(enabled ? "已开启" : "已关闭")
    }
}

struct ContactsSample: View {
    let palette: IOSSamplePalette

    private static let searchHeight: CGFloat = 36
    private static let searchTop: CGFloat = 8
    private static let searchBottom: CGFloat = 16
    private static let rowHeight: CGFloat = 64

    static var firstRowCenter: CGFloat {
        IOSLayout.statusHeight + IOSLayout.headingHeight + searchTop
            + searchHeight + searchBottom + rowHeight / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IOSPageHeading(title: "联系人")

            Label("搜索联系人", systemImage: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: Self.searchHeight, alignment: .leading)
                .background(palette.search, in: .rect(cornerRadius: SampleShape.field))
                .padding(.top, Self.searchTop)
                .padding(.bottom, Self.searchBottom)

            VStack(spacing: 0) {
                ForEach(ContactSample.all) { contact in
                    row(contact)
                    if contact != ContactSample.all.last {
                        palette.separator
                            .frame(height: 0.5)
                            .padding(.leading, IOSLayout.rowInset + 36 + IOSLayout.rowSpacing)
                    }
                }
            }
            .background(palette.cell)
            .clipShape(.rect(cornerRadius: SampleShape.group))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, IOSLayout.pageInset)
    }

    private func row(_ contact: ContactSample) -> some View {
        HStack(spacing: IOSLayout.rowSpacing) {
            ContactMonogram(character: String(contact.name.prefix(1)), size: 36, palette: palette)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.system(size: 17, weight: .medium))
                Text(contact.role)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 8)
            IOSDisclosure(palette: palette)
        }
        .padding(.horizontal, IOSLayout.rowInset)
        .frame(height: Self.rowHeight)
        .background(contact == .featured ? palette.selectedRow : palette.cell)
    }
}

struct ContactDetailSample: View {
    let palette: IOSSamplePalette
    private let contact = ContactSample.featured

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("联系人", systemImage: "chevron.left")
                Spacer()
                Text("编辑")
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(palette.accent)
            .frame(height: 44)
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                ContactMonogram(character: "林", size: 80, palette: palette)
                    .padding(.bottom, 4)
                Text(contact.name)
                    .font(.system(size: 28, weight: .semibold))
                Text(contact.role)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)

            IOSSectionLabel(title: "联系方式", palette: palette)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                field("手机号", value: "+1 415 555 0136")
                palette.separator
                    .frame(height: 0.5)
                    .padding(.leading, IOSLayout.rowInset)
                field("电子邮箱", value: "lin.xiao@example.com")
            }
            .background(palette.cell, in: .rect(cornerRadius: SampleShape.group))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, IOSLayout.pageInset)
    }

    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(palette.secondary)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, IOSLayout.rowInset)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    }
}

private struct IOSPageHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .bold))
            .frame(height: IOSLayout.headingHeight, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct IOSSectionLabel: View {
    let title: String
    let palette: IOSSamplePalette
    var leadingInset: CGFloat = IOSLayout.rowInset

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(palette.secondary)
            .padding(.leading, leadingInset)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct IOSDisclosure: View {
    let palette: IOSSamplePalette

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .accessibilityHidden(true)
    }
}

private struct ContactMonogram: View {
    let character: String
    let size: CGFloat
    let palette: IOSSamplePalette

    var body: some View {
        Text(character)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(palette.accent)
            .frame(width: size, height: size)
            .background(palette.avatar, in: .circle)
            .accessibilityHidden(true)
    }
}

private struct ContactSample: Identifiable, Equatable {
    let name: String
    let role: String
    var id: String { name }

    static let featured = Self(name: "林晓", role: "产品设计")
    static let all = [
        featured,
        Self(name: "周宁", role: "前端开发"),
        Self(name: "许舟", role: "用户研究"),
        Self(name: "陈悦", role: "项目协调"),
        Self(name: "顾晨", role: "内容设计")
    ]
}
