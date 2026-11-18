import SwiftUI

enum PreviewPlacement {
    case hidden
    case trailing(width: CGFloat)
    case centered(width: CGFloat)

    static let edgeInset: CGFloat = 16

    init(viewport: CGSize, visible: Bool, flow: Bool, live: Bool = false) {
        guard visible else {
            self = .hidden
            return
        }

        let threshold: CGFloat = flow ? 720 : 500
        let width = live ? min(328, max(264, viewport.width * 0.30)) : min(232, max(196, viewport.width * 0.24))
        if viewport.width < threshold {
            self = .centered(width: live ? 296 : 232)
        } else {
            self = .trailing(width: width)
        }
    }

    var width: CGFloat? {
        switch self {
        case .hidden: nil
        case .trailing(let width), .centered(let width): width
        }
    }

    var canvasClearance: CGFloat {
        guard case let .trailing(width) = self else { return 0 }
        return width + Self.edgeInset * 2
    }

    var isCentered: Bool {
        if case .centered = self { return true }
        return false
    }
}

struct PhonePreview: View {
    let state: ReviewState
    let device: ReviewDevice
    let arrangement: ReviewArrangement
    let width: CGFloat
    let availableHeight: CGFloat
    let palette: WorkbenchPalette
    var page: DesignPage? = nil
    let close: () -> Void

    private static let headerHeight: CGFloat = 32
    private static let bezel: CGFloat = 3
    private static let phoneTopPadding: CGFloat = 8
    private static let phoneBottomPadding: CGFloat = 10

    static let screenTop = headerHeight + phoneTopPadding + bezel

    var body: some View {
        let verticalInsets = Self.screenTop + Self.bezel + Self.phoneBottomPadding
        let scale = max(0.1, min(
            (width - 24 - Self.bezel * 2) / device.size.width,
            (availableHeight - verticalInsets) / device.size.height
        ))

        VStack(spacing: 0) {
            HStack {
                Text("iPhone 预览")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.secondary)
                .accessibilityLabel("关闭 iPhone 预览")
                .help("关闭预览")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: Self.headerHeight)
            .overlay(alignment: .bottom) { palette.groupSeam.frame(height: 1) }

            DevicePage(size: device.size, scale: scale) {
                if let page {
                    DesignPagePreview(page: page)
                } else {
                    IOSArtboard { phonePalette in
                        switch state {
                        case .blank: Color.clear
                        case .selection: SettingsSample(palette: phonePalette, arrangement: arrangement)
                        case .flow: ContactDetailSample(palette: phonePalette)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 20))
            .padding(Self.bezel)
            .background(Color(workbenchHex: 0x28282C), in: .rect(cornerRadius: 23))
            .padding(.top, Self.phoneTopPadding)
            .padding(.bottom, Self.phoneBottomPadding)
        }
        .frame(width: width)
        .background(palette.panel, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(palette.fieldSeam, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iPhone 画板预览")
    }
}
