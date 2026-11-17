import SwiftUI

struct SelectionInspector: View {
    let device: ReviewDevice
    let palette: WorkbenchPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("检查器")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 16)

                HStack(spacing: 12) {
                    WorkbenchSymbol(name: "square.stack")
                        .foregroundStyle(palette.accent)
                        .frame(width: 36, height: 36)
                        .background(palette.tint, in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("消息通知")
                            .font(.system(size: 14, weight: .semibold))
                        Text("设置项组合")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 20)

                Divider()
                geometrySection
                Divider().padding(.vertical, 16)

                sectionTitle("排列")
                    .padding(.bottom, 8)
                property("方向", value: "横排", symbol: "rectangle.split.2x1")
                property("间距", value: "\(Int(IOSLayout.rowSpacing)) pt")
                Divider().padding(.vertical, 16)

                sectionTitle("子控件")
                    .padding(.bottom, 8)
                property("图标", symbol: "bell")
                property("消息通知", symbol: "textformat")
                property("开关", symbol: "switch.2")
            }
            .padding(16)
        }
        .background(palette.surface)
    }

    private var geometrySection: some View {
        let bounds = SettingsSample.selectedBounds(for: device)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("位置与大小")
                Spacer()
                Text("pt")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .accessibilityLabel("单位，点")
            }
            HStack(spacing: 8) {
                metric("X", value: bounds.minX)
                metric("Y", value: bounds.minY)
            }
            HStack(spacing: 8) {
                metric("宽度", value: bounds.width)
                metric("高度", value: bounds.height)
            }
        }
        .padding(.top, 16)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func metric(_ title: String, value: CGFloat) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 4)
            Text(Int(value).formatted(.number.grouping(.never)))
                .font(.system(size: 13, design: .monospaced))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(palette.recessed, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func property(_ title: String, value: String? = nil, symbol: String? = nil) -> some View {
        HStack(spacing: 8) {
            if value == nil, let symbol {
                WorkbenchSymbol(name: symbol)
                    .foregroundStyle(palette.secondary)
            }
            Text(title)
                .foregroundStyle(value == nil ? palette.ink : palette.secondary)
            Spacer()
            if let value {
                if let symbol {
                    WorkbenchSymbol(name: symbol)
                        .foregroundStyle(palette.muted)
                }
                Text(value)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 13))
        .frame(height: 32)
        .accessibilityElement(children: .combine)
    }
}
