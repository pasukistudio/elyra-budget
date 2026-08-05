import SwiftUI
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {

    // MARK: - Initialisierung aus Hex

    init(hexString: String) {
        let cleanedHex = Self.cleanedHexString(
            from: hexString
        )

        guard
            cleanedHex.count == 6,
            let value = UInt64(
                cleanedHex,
                radix: 16
            )
        else {
            self = .blue
            return
        }

        let red = Double(
            (value >> 16) & 0xFF
        ) / 255

        let green = Double(
            (value >> 8) & 0xFF
        ) / 255

        let blue = Double(
            value & 0xFF
        ) / 255

        self.init(
            red: red,
            green: green,
            blue: blue
        )
    }

    // MARK: - Umwandlung in Hex

    func toHex() -> String? {
        guard let components = rgbComponents else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Self.hexComponent(components.red),
            Self.hexComponent(components.green),
            Self.hexComponent(components.blue)
        )
    }

    // MARK: - RGB-Komponenten

    private var rgbComponents: (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    )? {
#if os(iOS)
        let nativeColor = UIColor(self)
            .resolvedColor(
                with: UITraitCollection.current
            )

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard nativeColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return nil
        }

        return (
            red: red,
            green: green,
            blue: blue
        )

#elseif os(macOS)
        guard let nativeColor = NSColor(self)
            .usingColorSpace(.sRGB)
        else {
            return nil
        }

        return (
            red: nativeColor.redComponent,
            green: nativeColor.greenComponent,
            blue: nativeColor.blueComponent
        )
#endif
    }

    // MARK: - Hilfsfunktionen

    private static func cleanedHexString(
        from hexString: String
    ) -> String {
        hexString
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .replacingOccurrences(
                of: "#",
                with: ""
            )
    }

    private static func hexComponent(
        _ value: CGFloat
    ) -> Int {
        Int(
            round(
                min(max(value, 0), 1) * 255
            )
        )
    }
}
