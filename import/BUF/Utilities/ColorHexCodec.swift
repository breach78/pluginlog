import AppKit
import SwiftUI

enum ColorHexCodec {
    // Keep one canonical HEX parser/formatter so color behavior stays identical across screens/services.
    static func hexString(from color: NSColor?) -> String? {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return nil }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func nsColor(from hex: String?) -> NSColor? {
        guard let (red, green, blue) = rgbComponents(from: hex) else {
            return nil
        }

        return NSColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    static func color(from hex: String?) -> Color? {
        guard let nsColor = nsColor(from: hex) else {
            return nil
        }
        return Color(nsColor: nsColor)
    }

    private static func rgbComponents(from hex: String?) -> (Int, Int, Int)? {
        guard let hex else { return nil }

        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else {
            return nil
        }

        let red = (value >> 16) & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = value & 0xFF
        return (red, green, blue)
    }
}
