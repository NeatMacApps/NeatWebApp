import Foundation
import WebKit

/// 「手动隐藏网页元素」注入到页面里的那段脚本。
///
/// 两件事合在一段脚本里：
/// 1. **应用规则**——把当前站点已隐藏的元素用一段样式压掉，页面动态重渲染也照样管用。
/// 2. **挑选模式**——鼠标划过时高亮、点一下就选中，把选中元素反推成 CSS 选择器回传给原生层。
///
/// 挑选模式刻意不提供任何键盘调整层级的操作：鼠标指到哪、高亮框圈住什么，点下去消失的就是什么。
/// 代价是"指针命中的元素"必须自己往外扩到视觉上完整的那一块，否则点中广告里的一张图，
/// 隐藏后只会留下一个空框子——这条扩展规则见脚本里的 `resolveTarget`。
enum BrowserElementHidingScript {
    static let messageHandlerName = "neatElementHiding"

    /// 从页面回传给原生层的消息。
    enum IncomingMessage {
        case picked(selector: String, label: String, host: String)
        case cancelled
        case undoLatest
        case failed(reason: String)

        init?(body: Any) {
            guard let payload = body as? [String: Any], let type = payload["type"] as? String else {
                return nil
            }

            switch type {
            case "picked":
                guard
                    let selector = (payload["selector"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !selector.isEmpty
                else {
                    return nil
                }

                let label = (payload["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self = .picked(
                    selector: selector,
                    label: label.isEmpty ? "一块网页元素" : label,
                    host: payload["host"] as? String ?? ""
                )
            case "cancelled":
                self = .cancelled
            case "undo":
                self = .undoLatest
            case "failed":
                self = .failed(reason: payload["reason"] as? String ?? "这个元素没法被稳定定位")
            default:
                return nil
            }
        }
    }

    @MainActor
    static func makeUserScript(rules: [HiddenElementRule]) -> WKUserScript {
        WKUserScript(
            source: source(rules: rules),
            // 必须在文档开头注入：晚一步用户就会先看见要隐藏的东西闪一下再消失。
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static func applyRulesScript(rules: [HiddenElementRule]) -> String {
        "window.__neatWebAppElementHiding?.setRules(\(rulesJSON(rules)));"
    }

    static let startPickingScript = "window.__neatWebAppElementHiding?.startPicking();"

    static let stopPickingScript = "window.__neatWebAppElementHiding?.stopPicking();"

    static func undoToastScript(label: String) -> String {
        "window.__neatWebAppElementHiding?.showUndoToast(\(jsonString(label)));"
    }

    /// 规则序列化成 JSON。选择器里出现花括号说明它已经不是选择器了，直接丢掉，
    /// 否则拼进样式表会把后面的规则整片带坏。
    static func rulesJSON(_ rules: [HiddenElementRule]) -> String {
        let payload = rules
            .filter { isUsableSelector($0.selector) && !$0.host.isEmpty }
            .map { ["host": $0.host, "selector": $0.selector] }

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return json
    }

    static func isUsableSelector(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return !trimmed.contains("{")
            && !trimmed.contains("}")
            && !trimmed.contains("\n")
    }

    private static func jsonString(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        // 把单元素数组的方括号剥掉，得到一个转义完备的 JS 字符串字面量。
        return String(json.dropFirst().dropLast())
    }

    private static func source(rules: [HiddenElementRule]) -> String {
        #"""
        (() => {
            const rulesFromNative = \#(rulesJSON(rules));

            if (window.__neatWebAppElementHiding) {
                window.__neatWebAppElementHiding.setRules(rulesFromNative);
                return;
            }

            const handler = window.webkit?.messageHandlers?.\#(messageHandlerName);
            const finder = \#(BrowserSelectorFinderScript.expression);

            const STYLE_ID = 'neat-webapp-hidden-elements';
            const TOAST_ID = 'neat-webapp-undo-toast';
            // 打了这个标记的节点是我们自己的界面，挑选时必须跳过，否则用户会选中高亮框本身。
            const MARK = 'data-neat-webapp-ui';
            // 往外扩到"视觉上完整的一块"：父级没有明显变大就继续往外。
            const AREA_GROWTH_LIMIT = 1.5;
            // 但不能一路吞掉整个页面，超过半个视口就停。
            const MAX_VIEWPORT_RATIO = 0.5;

            let rules = Array.isArray(rulesFromNative) ? rulesFromNative : [];
            let picking = false;
            let hoverTarget = null;
            let ui = null;
            let toastTimer = 0;

            const normalizeHost = (value) => {
                const lower = (value || '').toLowerCase();
                return lower.startsWith('www.') ? lower.slice(4) : lower;
            };

            const currentHost = () => normalizeHost(location.hostname);

            const activeSelectors = () => rules
                .filter((rule) => rule && rule.host === currentHost())
                .map((rule) => rule.selector)
                .filter((selector) => typeof selector === 'string' && selector.length > 0 && !/[{}]/.test(selector));

            const applyRules = () => {
                const parent = document.head || document.documentElement;
                if (!parent) {
                    return;
                }

                let style = document.getElementById(STYLE_ID);
                if (!style || !style.isConnected) {
                    style = document.createElement('style');
                    style.id = STYLE_ID;
                    style.setAttribute(MARK, '1');
                }

                const css = activeSelectors()
                    .map((selector) => selector + ' { display: none !important; }')
                    .join('\n');

                if (style.textContent !== css) {
                    style.textContent = css;
                }

                // 挂到最后，站点自己的样式再晚也压不过它。
                parent.appendChild(style);
            };

            const rectOf = (element) => {
                const rect = element.getBoundingClientRect();
                return {
                    rect,
                    area: Math.max(0, rect.width) * Math.max(0, rect.height)
                };
            };

            const isOwnUI = (node) => {
                let current = node;
                while (current && current.hasAttribute) {
                    if (current.hasAttribute(MARK)) {
                        return true;
                    }
                    current = current.parentElement;
                }
                return false;
            };

            // 用户只把鼠标放上去，不做任何层级调整。所以指针命中的元素要自己往外扩：
            // 命中广告里的一张图时，隐藏的应该是整个广告块，而不是留下一个空框子。
            const resolveTarget = (x, y) => {
                const hit = document.elementFromPoint(x, y);
                if (!hit || isOwnUI(hit)) {
                    return null;
                }

                if (hit === document.body || hit === document.documentElement) {
                    return null;
                }

                const viewportArea = Math.max(1, window.innerWidth * window.innerHeight);
                let current = hit;
                let currentArea = rectOf(current).area;

                while (true) {
                    const parent = current.parentElement;
                    if (!parent || parent === document.body || parent === document.documentElement) {
                        break;
                    }

                    const parentArea = rectOf(parent).area;
                    if (parentArea > viewportArea * MAX_VIEWPORT_RATIO) {
                        break;
                    }

                    if (currentArea > 0 && parentArea > currentArea * AREA_GROWTH_LIMIT) {
                        break;
                    }

                    current = parent;
                    currentArea = parentArea;
                }

                return current;
            };

            const ensureUI = () => {
                if (ui && ui.root.isConnected) {
                    return ui;
                }

                const root = document.createElement('div');
                root.setAttribute(MARK, '1');
                root.style.cssText = 'position: fixed; inset: 0; z-index: 2147483646; pointer-events: none;';

                // 外扩的巨型阴影把页面其余部分压暗，用户一眼看清"点下去消失的是哪一块"。
                const box = document.createElement('div');
                box.setAttribute(MARK, '1');
                box.style.cssText = [
                    'position: fixed',
                    'display: none',
                    'border: 2px solid rgba(255, 69, 58, 0.95)',
                    'border-radius: 4px',
                    'background: rgba(255, 69, 58, 0.14)',
                    'box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.28)',
                    'pointer-events: none',
                    'transition: left 90ms ease-out, top 90ms ease-out, width 90ms ease-out, height 90ms ease-out'
                ].join('; ');

                const hint = document.createElement('div');
                hint.setAttribute(MARK, '1');
                hint.textContent = '点击要隐藏的元素 · 按 Esc 退出';
                hint.style.cssText = [
                    'position: fixed',
                    'top: 14px',
                    'left: 50%',
                    'transform: translateX(-50%)',
                    'padding: 7px 14px',
                    'border-radius: 999px',
                    'background: rgba(20, 20, 22, 0.92)',
                    'color: #fff',
                    'font: 600 12px/1.4 -apple-system, system-ui, sans-serif',
                    'pointer-events: none',
                    'white-space: nowrap'
                ].join('; ');

                root.appendChild(box);
                root.appendChild(hint);
                (document.body || document.documentElement).appendChild(root);

                ui = { root, box, hint };
                return ui;
            };

            const updateHighlight = (target) => {
                const view = ensureUI();
                if (!target || !target.isConnected) {
                    view.box.style.display = 'none';
                    return;
                }

                const rect = target.getBoundingClientRect();
                view.box.style.display = 'block';
                view.box.style.left = rect.left + 'px';
                view.box.style.top = rect.top + 'px';
                view.box.style.width = rect.width + 'px';
                view.box.style.height = rect.height + 'px';
            };

            const describe = (element) => {
                const text = (element.innerText || element.textContent || '').trim().replace(/\s+/g, ' ');
                if (text) {
                    return text.length > 24 ? text.slice(0, 24) + '…' : text;
                }

                const labelAttribute = element.getAttribute('alt')
                    || element.getAttribute('aria-label')
                    || element.getAttribute('title');
                if (labelAttribute && labelAttribute.trim()) {
                    return labelAttribute.trim().slice(0, 24);
                }

                const image = element.querySelector ? element.querySelector('img[alt]') : null;
                if (image && image.alt && image.alt.trim()) {
                    return image.alt.trim().slice(0, 24);
                }

                return element.tagName.toLowerCase() === 'img' ? '一张图片' : '一块无文字区域';
            };

            const swallow = (event) => {
                if (!picking) {
                    return;
                }
                event.preventDefault();
                event.stopPropagation();
            };

            const onMouseMove = (event) => {
                if (!picking) {
                    return;
                }
                hoverTarget = resolveTarget(event.clientX, event.clientY);
                updateHighlight(hoverTarget);
            };

            const onClick = (event) => {
                if (!picking) {
                    return;
                }
                event.preventDefault();
                event.stopPropagation();
                commit(resolveTarget(event.clientX, event.clientY) || hoverTarget);
            };

            const onKeyDown = (event) => {
                if (!picking || event.key !== 'Escape') {
                    return;
                }
                event.preventDefault();
                event.stopPropagation();
                stopPicking();
                handler?.postMessage({ type: 'cancelled' });
            };

            const onViewportChange = () => {
                if (picking) {
                    updateHighlight(hoverTarget);
                }
            };

            const commit = (target) => {
                stopPicking();

                if (!target) {
                    handler?.postMessage({ type: 'failed', reason: '没有选中任何元素' });
                    return;
                }

                const label = describe(target);
                let selector = '';
                try {
                    selector = finder(target, { root: document.body, timeoutMs: 600 });
                } catch (error) {
                    handler?.postMessage({ type: 'failed', reason: '这个元素没法被稳定定位，换一块试试' });
                    return;
                }

                if (!selector || /[{}]/.test(selector)) {
                    handler?.postMessage({ type: 'failed', reason: '这个元素没法被稳定定位，换一块试试' });
                    return;
                }

                handler?.postMessage({ type: 'picked', selector, label, host: currentHost() });
            };

            const startPicking = () => {
                if (picking) {
                    return;
                }

                picking = true;
                hoverTarget = null;
                ensureUI();
                updateHighlight(null);

                document.addEventListener('mousemove', onMouseMove, true);
                document.addEventListener('click', onClick, true);
                document.addEventListener('mousedown', swallow, true);
                document.addEventListener('mouseup', swallow, true);
                document.addEventListener('contextmenu', swallow, true);
                document.addEventListener('keydown', onKeyDown, true);
                window.addEventListener('scroll', onViewportChange, true);
                window.addEventListener('resize', onViewportChange, true);
            };

            const stopPicking = () => {
                if (!picking) {
                    return;
                }

                picking = false;
                hoverTarget = null;

                document.removeEventListener('mousemove', onMouseMove, true);
                document.removeEventListener('click', onClick, true);
                document.removeEventListener('mousedown', swallow, true);
                document.removeEventListener('mouseup', swallow, true);
                document.removeEventListener('contextmenu', swallow, true);
                document.removeEventListener('keydown', onKeyDown, true);
                window.removeEventListener('scroll', onViewportChange, true);
                window.removeEventListener('resize', onViewportChange, true);

                if (ui) {
                    ui.root.remove();
                    ui = null;
                }
            };

            const showUndoToast = (label) => {
                const container = document.body || document.documentElement;
                if (!container) {
                    return;
                }

                document.getElementById(TOAST_ID)?.remove();

                const toast = document.createElement('div');
                toast.id = TOAST_ID;
                toast.setAttribute(MARK, '1');
                toast.style.cssText = [
                    'position: fixed',
                    'left: 50%',
                    'bottom: 26px',
                    'transform: translateX(-50%)',
                    'z-index: 2147483647',
                    'display: flex',
                    'align-items: center',
                    'gap: 12px',
                    'padding: 9px 12px 9px 16px',
                    'border-radius: 999px',
                    'background: rgba(20, 20, 22, 0.92)',
                    'color: #fff',
                    'font: 500 12px/1.4 -apple-system, system-ui, sans-serif',
                    'box-shadow: 0 6px 20px rgba(0, 0, 0, 0.3)'
                ].join('; ');

                const text = document.createElement('span');
                text.textContent = '已隐藏 ' + label;

                const undo = document.createElement('button');
                undo.textContent = '撤销';
                undo.setAttribute(MARK, '1');
                undo.style.cssText = [
                    'all: unset',
                    'cursor: pointer',
                    'padding: 3px 10px',
                    'border-radius: 999px',
                    'background: rgba(255, 255, 255, 0.16)',
                    'color: #fff',
                    'font: 600 12px/1.4 -apple-system, system-ui, sans-serif'
                ].join('; ');
                undo.addEventListener('click', () => {
                    toast.remove();
                    handler?.postMessage({ type: 'undo' });
                });

                toast.appendChild(text);
                toast.appendChild(undo);
                container.appendChild(toast);

                clearTimeout(toastTimer);
                toastTimer = setTimeout(() => toast.remove(), 5000);
            };

            window.__neatWebAppElementHiding = {
                setRules: (next) => {
                    rules = Array.isArray(next) ? next : [];
                    applyRules();
                },
                startPicking,
                stopPicking,
                showUndoToast
            };

            applyRules();
            document.addEventListener('DOMContentLoaded', applyRules);
            window.addEventListener('pageshow', applyRules);
            window.addEventListener('popstate', applyRules);
            window.addEventListener('hashchange', applyRules);
        })();
        """#
    }
}
