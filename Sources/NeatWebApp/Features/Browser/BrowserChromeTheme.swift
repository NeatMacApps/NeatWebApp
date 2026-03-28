import AppKit
import SwiftUI

struct BrowserChromeTheme: Equatable {
    let pageColor: BrowserThemeColor
    let barTopColor: BrowserThemeColor
    let barBottomColor: BrowserThemeColor
    let foregroundColor: BrowserThemeColor
    let dividerColor: BrowserThemeColor
    let highlightedFillColor: BrowserThemeColor

    static let fallback = BrowserChromeTheme(pageColor: .fallbackBackground)

    init(pageColor: BrowserThemeColor) {
        let resolvedPageColor = pageColor.resolved(over: .fallbackBackground)
        let usesLightForeground = resolvedPageColor.relativeLuminance < 0.5

        self.pageColor = resolvedPageColor
        self.barTopColor = resolvedPageColor.blended(
            with: usesLightForeground ? .white : .black,
            amount: usesLightForeground ? 0.1 : 0.03
        )
        self.barBottomColor = resolvedPageColor.blended(
            with: usesLightForeground ? .white : .black,
            amount: usesLightForeground ? 0.04 : 0.08
        )
        self.foregroundColor = usesLightForeground
            ? BrowserThemeColor(red: 0.97, green: 0.98, blue: 1)
            : BrowserThemeColor(red: 0.1, green: 0.12, blue: 0.16)
        self.dividerColor = usesLightForeground
            ? BrowserThemeColor(red: 1, green: 1, blue: 1, alpha: 0.14)
            : BrowserThemeColor(red: 0, green: 0, blue: 0, alpha: 0.1)
        self.highlightedFillColor = usesLightForeground
            ? BrowserThemeColor(red: 1, green: 1, blue: 1, alpha: 0.16)
            : BrowserThemeColor(red: 0, green: 0, blue: 0, alpha: 0.1)
    }
}

struct BrowserThemeColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = BrowserThemeColor(red: 1, green: 1, blue: 1)
    static let black = BrowserThemeColor(red: 0, green: 0, blue: 0)
    static let fallbackBackground = BrowserThemeColor(red: 0.11, green: 0.12, blue: 0.14)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped(to: 0 ... 1)
        self.green = green.clamped(to: 0 ... 1)
        self.blue = blue.clamped(to: 0 ... 1)
        self.alpha = alpha.clamped(to: 0 ... 1)
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    var relativeLuminance: Double {
        let opaqueColor = resolved(over: .fallbackBackground)
        return (0.2126 * opaqueColor.red.linearizedSRGBComponent)
            + (0.7152 * opaqueColor.green.linearizedSRGBComponent)
            + (0.0722 * opaqueColor.blue.linearizedSRGBComponent)
    }

    func blended(with other: BrowserThemeColor, amount: Double) -> BrowserThemeColor {
        let clampedAmount = amount.clamped(to: 0 ... 1)
        let remainingAmount = 1 - clampedAmount

        return BrowserThemeColor(
            red: (red * remainingAmount) + (other.red * clampedAmount),
            green: (green * remainingAmount) + (other.green * clampedAmount),
            blue: (blue * remainingAmount) + (other.blue * clampedAmount),
            alpha: (alpha * remainingAmount) + (other.alpha * clampedAmount)
        )
    }

    func resolved(over background: BrowserThemeColor) -> BrowserThemeColor {
        guard alpha < 1 else {
            return self
        }

        let outputAlpha = alpha + (background.alpha * (1 - alpha))
        guard outputAlpha > 0 else {
            return .fallbackBackground
        }

        return BrowserThemeColor(
            red: ((red * alpha) + (background.red * background.alpha * (1 - alpha))) / outputAlpha,
            green: ((green * alpha) + (background.green * background.alpha * (1 - alpha))) / outputAlpha,
            blue: ((blue * alpha) + (background.blue * background.alpha * (1 - alpha))) / outputAlpha,
            alpha: outputAlpha
        )
    }

    static func fromScriptMessageBody(_ body: Any) -> BrowserThemeColor? {
        guard let payload = body as? [String: Any] else {
            return nil
        }

        guard
            let red = payload.doubleValue(forKey: "red"),
            let green = payload.doubleValue(forKey: "green"),
            let blue = payload.doubleValue(forKey: "blue")
        else {
            return nil
        }

        let alpha = payload.doubleValue(forKey: "alpha") ?? 1
        return BrowserThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension Double {
    var linearizedSRGBComponent: Double {
        if self <= 0.04045 {
            return self / 12.92
        }

        return pow((self + 0.055) / 1.055, 2.4)
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func doubleValue(forKey key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.doubleValue
        }

        return nil
    }
}
