import WebKit

/// 内嵌网页里的通行密钥（passkey / WebAuthn）限制。
///
/// 苹果只允许应用在 `WKWebView` 里对**自己通过关联域名声明过的站点**使用 WebAuthn。
/// 想对任意第三方站点可用，必须持有受限权限
/// `com.apple.developer.web-browser.public-key-credential`——它只发给正式浏览器产品，
/// 需要单独向苹果申请审批。本应用当前没有该权限，网页发起的请求会被系统直接拒绝，
/// 站点侧通常只表现为「点了没反应」或一个语焉不详的失败提示。
///
/// 这里**不改变任何行为**：原方法照常调用、参数与结果原样透传、失败照样按原错误抛回站点，
/// 只在确实被平台拒绝时上报一次，由原生层解释原因并给出可行出路。
enum BrowserPasskeySupport {
    static let messageHandlerName = "passkeyUnavailable"

    @MainActor
    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
                const handler = window.webkit?.messageHandlers?.passkeyUnavailable;
                const container = navigator.credentials;
                if (!handler || !container || window.__neatWebAppPasskeyProbeInstalled) {
                    return;
                }

                window.__neatWebAppPasskeyProbeInstalled = true;

                // 只认平台拒绝这几种错误；站点自身的校验失败、用户主动取消不在此列。
                const blockedErrors = new Set(['NotAllowedError', 'NotSupportedError', 'SecurityError']);

                const wrap = (methodName) => {
                    const original = container[methodName];
                    if (typeof original !== 'function') {
                        return;
                    }

                    container[methodName] = function (options) {
                        const result = original.apply(this, arguments);
                        if (!options || !options.publicKey) {
                            return result;
                        }

                        return result.catch((error) => {
                            if (error && blockedErrors.has(error.name)) {
                                handler.postMessage({ action: methodName, name: error.name });
                            }

                            throw error;
                        });
                    };
                };

                wrap('get');
                wrap('create');
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
