import SwiftUI

struct PhonePreview: View {
    let device: ReviewDevice
    let palette: WorkbenchPalette

    private let panelHeaderHeight: CGFloat = 56
    private let bezel: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("iPhone 预览")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("设计稿")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(height: panelHeaderHeight, alignment: .top)

            GeometryReader { geometry in
                let top = CanvasLayout.boardTop - panelHeaderHeight - bezel
                let scale = min(
                    (geometry.size.width - 40 - bezel * 2) / device.size.width,
                    (geometry.size.height - top - 24 - bezel * 2) / device.size.height
                )

                DevicePage(size: device.size, scale: max(0.1, scale)) {
                    IOSArtboard { ContactDetailSample(palette: $0) }
                }
                .clipShape(.rect(cornerRadius: 24))
                .padding(bezel)
                .background(Color(workbenchHex: 0x242B36), in: .rect(cornerRadius: 28))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("iPhone 上的联系人详情设计稿")
            }
        }
        .background(palette.surface)
    }
}
