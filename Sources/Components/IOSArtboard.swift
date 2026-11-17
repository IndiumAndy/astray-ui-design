import SwiftUI

enum IOSLayout {
    static let statusHeight: CGFloat = 56
    static let homeHeight: CGFloat = 34
    static let headingHeight: CGFloat = 64
    static let pageInset: CGFloat = 20
    static let rowInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
}

struct IOSSamplePalette {
    let scheme: ColorScheme

    var grouped: Color { color(0xF2F2F7, 0x000000) }
    var cell: Color { color(0xFFFFFF, 0x1C1C1E) }
    var search: Color { color(0xE3E3E9, 0x29292D) }
    var label: Color { color(0x111116, 0xF5F5FA) }
    var secondary: Color { color(0x5E5E69, 0xAEAEB8) }
    var separator: Color { color(0xD9D9E0, 0x34343B) }
    var accent: Color { color(0x005AC7, 0x7CB6FF) }
    var navigationAccent: Color { color(0x007AFF, 0x72B7FF) }
    var sectionLabel: Color { color(0x6D6D72, 0xAEAEB8) }
    var avatar: Color { color(0xDFEAFC, 0x22344D) }
    var selectedRow: Color { color(0xEAF1FD, 0x182B42) }
    var switchOn: Color { color(0x30A755, 0x32C960) }

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(workbenchHex: scheme == .dark ? dark : light)
    }
}

struct IOSArtboard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: (IOSSamplePalette) -> Content

    var body: some View {
        let palette = IOSSamplePalette(scheme: scheme)
        VStack(spacing: 0) {
            IOSStatusBar(palette: palette)
                .accessibilityHidden(true)
            content(palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Capsule()
                .fill(palette.label)
                .frame(width: 124, height: 5)
                .padding(.bottom, 8)
                .frame(height: IOSLayout.homeHeight, alignment: .bottom)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.label)
        .background(palette.grouped)
    }
}

private struct IOSStatusBar: View {
    let palette: IOSSamplePalette

    var body: some View {
        HStack(spacing: 0) {
            Text("9:41")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                    .font(.system(size: 19, weight: .medium))
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(palette.label)
        .padding(.horizontal, 32)
        .frame(height: IOSLayout.statusHeight)
    }
}
