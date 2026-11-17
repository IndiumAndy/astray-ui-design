import SwiftUI

// Neutral Astryx reference values used by the artboard samples.
private enum SampleToken {
    static let elementRadius: CGFloat = 10
    static let containerRadius: CGFloat = 12
    static let body: CGFloat = 14
    static let label: CGFloat = 14
}

struct SettingsSample: View {
    let palette: WorkbenchPalette

    static let rowInset: CGFloat = 24
    static let selectedRowY: CGFloat = 156
    static let rowHeight: CGFloat = 56
    static let rowSpacing = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SampleHeading(title: "设置")
                .frame(height: 96, alignment: .bottomLeading)
                .padding(.bottom, 28)

            sectionLabel("通知")
            VStack(spacing: 0) {
                row("消息通知", symbol: "bell", enabled: true)
                Divider().padding(.leading, 48)
                row("邮件摘要", symbol: "envelope", enabled: false)
            }
            .workbenchSurface(palette, radius: SampleToken.containerRadius)

            sectionLabel("账号")
                .padding(.top, 24)
            VStack(spacing: 0) {
                row("个人资料", symbol: "person.crop.circle")
                Divider().padding(.leading, 48)
                row("隐私与安全", symbol: "lock")
            }
            .workbenchSurface(palette, radius: SampleToken.containerRadius)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.rowInset)
        .background(palette.surface)
    }

    static func selectedBounds(for device: ReviewDevice) -> CGRect {
        CGRect(
            x: rowInset, y: selectedRowY,
            width: device.size.width - rowInset * 2, height: rowHeight
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: SampleToken.label, weight: .medium))
            .foregroundStyle(palette.secondary)
            .frame(height: 32, alignment: .topLeading)
    }

    private func row(_ title: String, symbol: String, enabled: Bool? = nil) -> some View {
        HStack(spacing: CGFloat(Self.rowSpacing)) {
            WorkbenchSymbol(name: symbol)
                .foregroundStyle(palette.secondary)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            if let enabled {
                SampleSwitch(enabled: enabled, palette: palette)
            } else {
                WorkbenchSymbol(name: "chevron.right")
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.rowHeight)
    }
}

private struct SampleSwitch: View {
    let enabled: Bool
    let palette: WorkbenchPalette

    var body: some View {
        Capsule()
            .fill(enabled ? palette.accentFill : palette.recessed)
            .overlay {
                Capsule().strokeBorder(palette.seam)
            }
            .overlay(alignment: enabled ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                    .padding(4)
            }
            .frame(width: 48, height: 28)
    }
}

struct ContactsSample: View {
    let palette: WorkbenchPalette

    static let firstRowCenter: CGFloat = 192
    static let rowInset: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SampleHeading(title: "联系人")
                .frame(height: 96, alignment: .bottomLeading)

            Label("搜索联系人", systemImage: "magnifyingglass")
                .font(.system(size: SampleToken.body))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(palette.recessed, in: .rect(cornerRadius: SampleToken.elementRadius))
                .padding(.top, 12)
                .padding(.bottom, 16)

            ForEach(ContactSample.all) { contact in
                HStack(spacing: 12) {
                    ContactMonogram(character: String(contact.name.prefix(1)), size: 36, palette: palette)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name)
                            .font(.system(size: 16, weight: .medium))
                        Text(contact.role)
                            .font(.system(size: SampleToken.body))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer(minLength: 8)
                    WorkbenchSymbol(name: "chevron.right")
                        .foregroundStyle(palette.muted)
                }
                .padding(.horizontal, 12)
                .frame(height: 64)
                .background {
                    if contact == .featured {
                        RoundedRectangle(cornerRadius: SampleToken.elementRadius)
                            .fill(palette.tint)
                    }
                }
                if contact != ContactSample.all.last { Divider().padding(.leading, 60) }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.rowInset)
        .background(palette.surface)
    }
}

struct ContactDetailSample: View {
    let palette: WorkbenchPalette
    private let contact = ContactSample.featured

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("联系人", systemImage: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(height: 44)
                .padding(.top, 40)
                .padding(.bottom, 28)

            ContactMonogram(character: "林", size: 76, palette: palette)
                .padding(.bottom, 16)
            SampleHeading(title: contact.name)
                .padding(.bottom, 8)
            Text(contact.role)
                .font(.system(size: 16))
                .foregroundStyle(palette.secondary)
                .padding(.bottom, 36)

            Text("联系方式")
                .font(.system(size: 18, weight: .semibold))
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                field("手机号", value: "+1 415 555 0136")
                Divider()
                field("电子邮箱", value: "lin.xiao@example.com")
            }
            .padding(.horizontal, 16)
            .workbenchSurface(palette, radius: SampleToken.containerRadius)

            Label("编辑联系人", systemImage: "pencil")
                .font(.system(size: SampleToken.label, weight: .medium))
                .foregroundStyle(palette.surface)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(palette.ink, in: .rect(cornerRadius: SampleToken.elementRadius))
                .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(palette.surface)
    }

    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: SampleToken.body))
                .foregroundStyle(palette.secondary)
            Text(value)
                .font(.system(size: 16, weight: .medium))
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private struct SampleHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 32, weight: .semibold))
    }
}

private struct ContactMonogram: View {
    let character: String
    let size: CGFloat
    let palette: WorkbenchPalette

    var body: some View {
        Text(character)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(palette.accent)
            .frame(width: size, height: size)
            .background(palette.tint, in: .circle)
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
