import SwiftUI

struct WorkbenchPalette {
    private let dark: Bool
    private let highContrast: Bool

    init(_ appearance: ColorScheme, _ contrast: ColorSchemeContrast) {
        dark = appearance == .dark
        highContrast = contrast == .increased
    }

    var panel: Color { color(0xF5F5F7, 0x252527) }
    var sidebarTint: Color { panel.opacity(0.82) }
    var canvas: Color { color(0xE5E5EA, 0x1D1D22) }
    var ruler: Color { panel.opacity(0.90) }
    var field: Color { color(0xFFFFFF, 0x303035) }
    var ink: Color { color(0x1D1D1F, 0xF5F5F7) }
    var secondary: Color { color(0x515154, 0xCACAD0) }
    var propertyLabel: Color { color(0x3A3A3C, 0xD5D5DB) }
    var muted: Color { color(highContrast ? 0x59595E : 0x66666B, 0xAAAAB0) }
    var measure: Color { color(0x6D6D72, 0xB5B5BC) }
    var accent: Color { color(highContrast ? 0x00499A : 0x005AC7, 0x72B7FF) }
    var selection: Color { Color(workbenchHex: highContrast ? 0x00499A : 0x005AC7) }
    var focusHalo: Color { accent.opacity(highContrast ? 0.72 : 0.35) }
    var searchFill: Color { wash(0.05, 0.09) }
    var hover: Color { wash(0.05, 0.08) }
    var rowHover: Color { wash(0.04, 0.07) }
    var active: Color { wash(0.09, 0.13) }
    var seam: Color { wash(highContrast ? 0.28 : 0.10, 0.14) }
    var groupSeam: Color { wash(highContrast ? 0.24 : 0.07, 0.12) }
    var fieldSeam: Color { wash(highContrast ? 0.30 : 0.14, 0.22) }
    var artboardSeam: Color { wash(0.08, 0.13) }
    var grid: Color { wash(0.02, 0.045) }
    var majorGrid: Color { wash(0.045, 0.09) }

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(workbenchHex: self.dark ? dark : light)
    }

    private func wash(_ light: Double, _ dark: Double) -> Color {
        self.dark ? .white.opacity(dark) : .black.opacity(light)
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
