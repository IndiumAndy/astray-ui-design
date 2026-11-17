import SwiftUI

struct SelectionInspector: View {
    let device: ReviewDevice
    let palette: WorkbenchPalette
    @Binding var arrangement: ReviewArrangement

    private let fieldHeight: CGFloat = 22

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("消息通知")
                            .font(.system(size: 12, weight: .semibold))
                        Text("设置项组合")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)

                palette.groupSeam.frame(height: 1)
                geometrySection.padding(.vertical, 12)
                palette.groupSeam.frame(height: 1)
                arrangementSection.padding(.vertical, 12)
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("属性检查器")
    }

    private var geometrySection: some View {
        let bounds = SettingsSample.selectedBounds(for: device, arrangement: arrangement)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("位置与大小")
                Spacer()
                Text("pt")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .accessibilityLabel("单位，点")
            }
            HStack(spacing: 6) {
                metric("X", label: "X 坐标", value: bounds.minX)
                metric("Y", label: "Y 坐标", value: bounds.minY)
            }
            HStack(spacing: 6) {
                metric("W", label: "宽度", value: bounds.width)
                metric("H", label: "高度", value: bounds.height)
            }
        }
    }

    private var arrangementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("排列")

            HStack {
                propertyLabel("方向")
                Spacer()
                Picker("方向", selection: $arrangement.direction) {
                    ForEach(ReviewDirection.allCases) { direction in
                        Label(direction.title, systemImage: direction.symbol)
                            .labelStyle(.iconOnly)
                            .tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(height: 22)
                .help("排列方向")
            }

            HStack {
                propertyLabel("间距")
                Spacer()
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        TextField("间距", value: spacing, format: .number.grouping(.never))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("inspector-spacing")
                        Text("pt")
                            .foregroundStyle(palette.muted)
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(width: 48, height: fieldHeight)
                    .background { fieldBackground }

                    Stepper("调整间距", value: $arrangement.spacing, in: ReviewArrangement.spacingRange)
                        .labelsHidden()
                        .controlSize(.mini)
                        .fixedSize()
                        .frame(height: fieldHeight)
                }
            }
        }
    }

    private var spacing: Binding<Int> {
        Binding(
            get: { arrangement.spacing },
            set: { arrangement.spacing = min(max($0, ReviewArrangement.spacingRange.lowerBound), ReviewArrangement.spacingRange.upperBound) }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func propertyLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(palette.propertyLabel)
            .accessibilityHidden(true)
    }

    private func metric(_ prefix: String, label: String, value: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(prefix)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
            Spacer(minLength: 4)
            Text(Int(value).formatted(.number.grouping(.never)))
                .font(.system(size: 12))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: fieldHeight)
        .background { fieldBackground }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) 点")
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(palette.field)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(palette.fieldSeam, lineWidth: 0.5)
            }
    }
}
