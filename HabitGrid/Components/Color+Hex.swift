import SwiftUI

// MARK: - Hex initialiser

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex) ?? .systemGreen)
    }
}

extension UIColor {
    convenience init?(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&int) else { return nil }
        self.init(
            red:   CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8)  & 0xFF) / 255,
            blue:  CGFloat(int         & 0xFF) / 255,
            alpha: 1
        )
    }

    /// HSB components; saturation is clamped ≥ 0.45 so low-sat inputs still
    /// produce visible shades (e.g. white/gray input → still a tinted swatch).
    func contributionHSB() -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, max(s, 0.45), b)
    }
}

// MARK: - Contribution shade factory

extension Color {
    /// Maps intensity bucket (0–4) + a hex base colour + colour scheme to
    /// the appropriate cell fill colour.
    static func contribution(intensity: Int, hex: String, scheme: ColorScheme) -> Color {
        guard intensity > 0 else {
            return scheme == .dark
                ? Color(white: 0.13)
                : Color(UIColor.systemGray5)
        }

        let (h, s, _) = (UIColor(hex: hex) ?? .systemGreen).contributionHSB()

        let (finalS, finalB): (CGFloat, CGFloat)
        if scheme == .light {
            switch intensity {
            case 1:  (finalS, finalB) = (s * 0.32, 0.94)
            case 2:  (finalS, finalB) = (s * 0.54, 0.82)
            case 3:  (finalS, finalB) = (s * 0.80, 0.65)
            default: (finalS, finalB) = (s,        0.42)
            }
        } else {
            switch intensity {
            case 1:  (finalS, finalB) = (s * 0.55, 0.20)
            case 2:  (finalS, finalB) = (s * 0.65, 0.38)
            case 3:  (finalS, finalB) = (s * 0.72, 0.57)
            default: (finalS, finalB) = (s * 0.80, 0.78)
            }
        }
        return Color(hue: Double(h), saturation: Double(finalS), brightness: Double(finalB))
    }

}
