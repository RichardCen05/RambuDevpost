import SwiftUI

/// Rambu colors and type, shared by the app and the Live Activity widget.
enum Brand {
    static let teal = Color(hex: 0x006F63)
    static let tealBright = Color(hex: 0x00937F)
    static let tealDeep = Color(hex: 0x054F47)
    static let tealSoft = Color(hex: 0xE2F2EF)

    static let ink = Color(hex: 0x0F2A29)
    static let ink2 = Color(hex: 0x3B5250)
    static let ink3 = Color(hex: 0x5B716F)
    static let canvas = Color(hex: 0xF2F6F5)
    static let hairline = Color(hex: 0xDCE7E4)

    static let amber = Color(hex: 0xF4B400)
    static let amberSoft = Color(hex: 0xFFF3C7)
    static let amberInk = Color(hex: 0x5A4100)

    static let red = Color(hex: 0xD2372C)
    static let redSoft = Color(hex: 0xFDE6E3)
    static let redInk = Color(hex: 0x9E1F15)

    static let green = Color(hex: 0x1E8259)
    static let greenSoft = Color(hex: 0xE4F3EC)
    static let greenInk = Color(hex: 0x14603F)

    static let puckCream = Color(hex: 0xF4F0E6)

    static func title(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Call risk as the app shows it.
enum Risk: String, Codable, Sendable {
    case low, needsReview = "needs_review", highRisk = "high_risk"

    var tint: Color {
        switch self {
        case .low: Brand.green
        case .needsReview: Brand.amber
        case .highRisk: Brand.red
        }
    }

    var soft: Color {
        switch self {
        case .low: Brand.greenSoft
        case .needsReview: Brand.amberSoft
        case .highRisk: Brand.redSoft
        }
    }

    var ink: Color {
        switch self {
        case .low: Brand.greenInk
        case .needsReview: Brand.amberInk
        case .highRisk: Brand.redInk
        }
    }

    /// Mascot image asset for this level (`-dark` variants exist for dark backgrounds).
    var mascot: String {
        switch self {
        case .low: "mascot-calm-safe"
        case .needsReview: "mascot-check-review"
        case .highRisk: "mascot-stop-danger"
        }
    }
}
