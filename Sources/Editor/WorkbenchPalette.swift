import SwiftUI

struct WorkbenchPalette {
    private let dark: Bool
    private let highContrast: Bool

    init(_ appearance: ColorScheme, _ contrast: ColorSchemeContrast) {
        dark = appearance == .dark
        highContrast = contrast == .increased
    }

    var surface: Color { color(0xFFFFFF, 0x232830) }
    var sidebar: Color { color(0xF3F5F7, 0x1C2128) }
    var canvas: Color { color(0xF6F8FB, 0x171B21) }
    var ruler: Color { color(0xEDF1F5, 0x20262E) }
    var recessed: Color { color(0xF0F3F6, 0x2A3039) }
    var ink: Color { color(0x192432, 0xF0F3F8) }
    var secondary: Color { color(0x465669, 0xC2CCD9) }
    var muted: Color { color(0x566779, 0xA8B6C8) }
    var accent: Color { color(0x1258C9, 0x8AB7FF) }
    var accentFill: Color { color(0x1258C9, 0x2366CE) }
    var tint: Color { color(0xEAF2FF, 0x263A58) }
    var seam: Color { ink.opacity(highContrast ? 0.30 : 0.12) }
    var grid: Color { color(0xDFE6EE, 0x252C36) }
    var majorGrid: Color { color(0xD3DDE9, 0x323B47) }

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(workbenchHex: self.dark ? dark : light)
    }
}

extension Color {
    init(workbenchHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    func workbenchSurface(_ palette: WorkbenchPalette, radius: CGFloat = 8) -> some View {
        background(palette.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(palette.seam)
                    .allowsHitTesting(false)
            }
    }
}

struct WorkbenchSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 20)
            .accessibilityHidden(true)
    }
}
