import SwiftUI

struct PhonePreview: View {
    let device: ReviewDevice
    let palette: WorkbenchPalette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("iPhone 预览")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("设计稿")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            }
            .padding(16)

            GeometryReader { geometry in
                let available = geometry.size
                let scale = min(
                    (available.width - 52) / device.size.width,
                    (available.height - 64) / device.size.height
                )

                DevicePage(size: device.size, scale: max(0.1, scale)) {
                    ContactDetailSample(palette: palette)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(palette.ink)
                                .frame(width: 112, height: 5)
                                .padding(.bottom, 8)
                                .accessibilityHidden(true)
                        }
                }
                .clipShape(.rect(cornerRadius: 27))
                .padding(5)
                .background(Color(workbenchHex: 0x26313E), in: .rect(cornerRadius: 32))
                .overlay {
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(palette.ink.opacity(0.24))
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.13), radius: 14, y: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("iPhone 上的联系人详情设计稿")
            }
        }
        .background(palette.sidebar)
    }
}
