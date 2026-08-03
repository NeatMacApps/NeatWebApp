import AppKit

/// WebApp 窗口内的浏览器级快捷键。
///
/// 运行时进程是 `LSUIElement`，永远不显示菜单栏，只能拿到 SwiftUI 隐式生成的标准菜单
/// （复制、粘贴、撤销、全选等），浏览器动作没有任何菜单项可挂，因此这里自己做按键映射，
/// 交给 WebView 在 `performKeyEquivalent` 阶段消费——网页里的输入框拿到焦点时，
/// 普通 `keyDown` 会先被网页吃掉。
///
/// 刻意不接管的按键：
/// - `Command ←` / `Command →`：在网页输入框里是"跳到行首/行尾"，抢过来会让用户打字时误触发前进后退。
///   前进后退只绑 `Command [` / `Command ]`，与 Safari 菜单里的标注一致。
/// - `Command H`：系统隐藏应用，只有加 Shift 才是回到配置地址。
/// - `Command C/V/X/A/Z`：交给系统标准菜单，避免与网页内的编辑行为打架。
enum BrowserKeyCommand: Equatable {
    case zoomIn
    case zoomOut
    case resetZoom
    case reload
    case reloadIgnoringCache
    case goBack
    case goForward
    case goHome
    case printPage
    case collapseWindow

    /// 主键盘与数字小键盘的 `charactersIgnoringModifiers` 一致，因此无需区分 `.numericPad`。
    static func resolve(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> BrowserKeyCommand? {
        let relevantFlags = modifierFlags.intersection([.command, .shift, .option, .control])
        guard relevantFlags.contains(.command),
              !relevantFlags.contains(.option),
              !relevantFlags.contains(.control) else {
            return nil
        }

        // 大小写统一处理，避免 Caps Lock 打开时把 Command R 误判成 Command Shift R。
        guard let key = charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        let isShiftPressed = relevantFlags.contains(.shift)

        switch key {
        case "=", "+":
            return .zoomIn
        case "-", "_":
            return .zoomOut
        case "0":
            return .resetZoom
        case "r":
            return isShiftPressed ? .reloadIgnoringCache : .reload
        case "[":
            return isShiftPressed ? nil : .goBack
        case "]":
            return isShiftPressed ? nil : .goForward
        case "h":
            return isShiftPressed ? .goHome : nil
        case "p":
            return isShiftPressed ? nil : .printPage
        case "w":
            return isShiftPressed ? nil : .collapseWindow
        default:
            return nil
        }
    }

    static func resolve(event: NSEvent) -> BrowserKeyCommand? {
        resolve(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }
}
