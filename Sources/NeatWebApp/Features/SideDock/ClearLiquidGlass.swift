import AppKit

/// 把 BrainDrop / JotBox 那套通透玻璃配方打到系统玻璃视图上。
/// 只改外观私有属性，不改路径：`_setPath:` 是形变接口，拿来当贴边外形会让玻璃往下淌。
@available(macOS 26.0, *)
enum ClearLiquidGlass {
    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void

    static func apply(in root: NSView) {
        apply(to: root)
    }

    private static func apply(to view: NSView) {
        if let glass = view as? NSGlassEffectView {
            apply(toGlass: glass)
        }
        for subview in view.subviews {
            apply(to: subview)
        }
    }

    private static func apply(toGlass glass: NSGlassEffectView) {
        glass.style = .clear
        glass.tintColor = .clear
        setPrivateIntegerProperty(on: glass, "variant", value: 2)
        setPrivateIntegerProperty(on: glass, "scrimState", value: 0)
        setPrivateIntegerProperty(on: glass, "subduedState", value: 0)
    }

    private static func setPrivateIntegerProperty(on object: NSView, _ key: String, value: Int) {
        let selectorNames = [
            "set_\(key):",
            "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        ]

        guard let selectorName = selectorNames.first(where: {
            object.responds(to: NSSelectorFromString($0))
        }) else {
            return
        }

        let selector = NSSelectorFromString(selectorName)
        let implementation = object.method(for: selector)
        let setter = unsafeBitCast(implementation, to: IntegerSetter.self)
        setter(object, selector, value)
    }
}
