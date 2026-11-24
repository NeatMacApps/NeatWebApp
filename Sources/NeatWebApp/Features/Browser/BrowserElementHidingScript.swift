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
        case broad(selector: String, count: Int, label: String)

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
                    label: label.isEmpty ? String(localized: "browser.hiding.fallback_picked_label") : label,
                    host: payload["host"] as? String ?? ""
                )
            case "cancelled":
                self = .cancelled
            case "undo":
                self = .undoLatest
            case "failed":
                self = .failed(reason: payload["reason"] as? String ?? String(localized: "browser.hiding.unstable"))
            case "broad":
                guard
                    let selector = (payload["selector"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !selector.isEmpty
                else {
                    return nil
                }
                let count: Int
                if let int = payload["count"] as? Int {
                    count = int
                } else if let double = payload["count"] as? Double {
                    count = Int(double)
                } else if let number = payload["count"] as? NSNumber {
                    count = number.intValue
                } else {
                    return nil
                }
                let label = (payload["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self = .broad(
                    selector: selector,
                    count: count,
                    label: (label?.isEmpty == false ? label! : String(localized: "browser.hiding.fallback_broad_label"))
                )
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

    /// 刚隐藏完立刻数一下这条选择器命中了多少元素：超过阈值说明它不是用户指的那一小块，
    /// 而是全站通用类名（如 `.visible`），页面脚本一多就会反复触发全量样式匹配、越用越卡。
    /// 只回传超标的情况，不打扰正常的单块隐藏。
    static let broadRuleMatchLimit = 30

    static func reportBroadRuleScript(selector: String, label: String, limit: Int = broadRuleMatchLimit) -> String {
        "window.__neatWebAppElementHiding?.reportBroadRule(\(jsonString(selector)), \(jsonString(label)), \(limit));"
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

            const GENERIC_ROOT_IDS = new Set([
                'app', 'root', '__next', '__nuxt', 'main', 'page',
                'container', 'wrapper', 'content', 'article-content-container'
            ]);
            const STATE_OR_THEME_CLASSES = new Set([
                'light', 'dark', 'active', 'selected', 'current', 'open', 'closed',
                'show', 'hide', 'hidden', 'visible', 'focus', 'focused', 'hover',
                'disabled', 'loading', 'expanded', 'collapsed', 'checked', 'on', 'off',
                'init', 'ready', 'mobile', 'desktop', 'pc', 'android', 'ios',
                'white', 'black', 'small', 'medium', 'large', 'fixed', 'sticky'
            ]);
            const STATE_PREFIX_RE = /^(?:is|has|js|state|theme|mode|layer|v-enter|v-leave|fade|slide|animate|anim|transition)[-_]/i;
            const GENERIC_CLASSES = new Set([
                'box', 'main', 'page', 'app', 'root', 'layout', 'container', 'wrapper', 'wrap',
                'content', 'inner', 'outer', 'body', 'head', 'header', 'footer', 'nav', 'navbar',
                'sidebar', 'aside', 'section', 'panel', 'card', 'item', 'items', 'list', 'row', 'rows',
                'col', 'cols', 'grid', 'flex', 'group', 'controls', 'control', 'actions', 'action',
                'btn', 'btns', 'button', 'buttons', 'icon', 'icons', 'iconfont', 'img', 'image',
                'pic', 'picture', 'photo', 'avatar', 'title', 'subtitle', 'heading', 'text', 'txt',
                'label', 'desc', 'description', 'info', 'meta', 'mask', 'modal', 'dialog', 'popup',
                'overlay', 'drawer', 'menu', 'dropdown', 'tab', 'tabs', 'bar', 'toolbar',
                'top', 'bottom', 'left', 'right', 'center', 'middle', 'badge', 'tag', 'tags',
                'tip', 'tips', 'dot', 'dots', 'line', 'divider', 'bg', 'link', 'input', 'form',
                'search', 'close', 'logo', 'banner', 'ad', 'ads', 'placeholder',
                'content-wrapper', 'main-wrapper'
            ]);
            const UTILITY_CLASS_RE = /^(?:p|px|py|pt|pr|pb|pl|m|mx|my|mt|mr|mb|ml|-m|-mx|-my|-mt|-mr|-mb|-ml|w|h|min-w|max-w|min-h|max-h|size|gap|gap-x|gap-y|space-x|space-y|text|bg|border|rounded|shadow|opacity|z|top|bottom|left|right|inset|overflow|cursor|items|justify|self|content|place|flex|grow|shrink|basis|grid|col|row|font|leading|tracking|transition|duration|ease|delay|scale|rotate|translate|skew|ring|outline|divide|fill|stroke|sr|select|pointer|appearance|whitespace|break|truncate|align|object|aspect|order)-/i;
            const SINGLETON_UTILITY_RE = /^(?:flex|inline-flex|grid|inline-grid|block|inline-block|inline|hidden|relative|absolute|fixed|sticky|static|truncate|uppercase|lowercase|capitalize|underline|italic|antialiased|clearfix|sr-only|pointer-events-none|pointer-events-auto|select-none|overflow-hidden|overflow-auto|whitespace-nowrap)$/i;
            const CSS_IN_JS_HASH_RE = /^(?:css|sc|emotion|svelte|jsx)-[a-z0-9]{4,}$/i;
            const COMMON_SHORT_WORDS = new Set([
                'length', 'strength', 'widths', 'depths', 'months', 'eighth', 'fifths', 'sixths', 'ninths', 'twelfth'
            ]);
            const TIER1_ATTRS = [
                'data-testid', 'data-test', 'data-cy', 'data-qa',
                'data-component', 'data-module', 'data-slot', 'data-section',
                'data-name', 'data-widget', 'data-block', 'data-region'
            ];
            const TIER1_ATTR_SET = new Set(TIER1_ATTRS);
            const TIER2_ATTRS = ['aria-label', 'title', 'alt', 'name'];
            const LANDMARK_ROLES = new Set([
                'banner', 'complementary', 'contentinfo', 'navigation', 'search', 'dialog', 'alertdialog', 'status'
            ]);
            const SEMANTIC_LANDMARK_TAGS = new Set(['header', 'nav', 'aside', 'footer']);

            let rules = Array.isArray(rulesFromNative) ? rulesFromNative : [];
            let picking = false;
            let hoverTarget = null;
            let ui = null;
            let toastTimer = 0;

            const escapeAttrValue = (value) => String(value)
                .replace(/\\/g, '\\\\')
                .replace(/"/g, '\\"');

            const looksLikeHash = (token) => {
                if (!token || token.length < 4 || token.length > 10) {
                    return false;
                }
                if (/[^A-Za-z0-9_-]/.test(token)) {
                    return false;
                }
                if (/[0-9]/.test(token)) {
                    return true;
                }
                if (/^[a-z]+$/.test(token)) {
                    return token.length >= 5 && /[^aeiouy]{4,}/i.test(token) && !COMMON_SHORT_WORDS.has(token);
                }
                if (/^[A-Z]+$/.test(token)) {
                    return token.length >= 5 && /[^AEIOUY]{4,}/.test(token);
                }
                if (/^[A-Z][a-z]+$/.test(token)) {
                    return false;
                }
                if (/^[a-z]+[A-Z][a-z]{2,}$/.test(token) && !/[^aeiouy]{4,}/i.test(token)) {
                    return false;
                }
                return /[A-Z]/.test(token) && /[a-z]/.test(token);
            };

            const isDynamicID = (id) => {
                if (typeof id !== 'string') {
                    return true;
                }
                const trimmed = id.trim();
                if (!trimmed || trimmed.length > 80 || /\s|[{}]/.test(trimmed)) {
                    return true;
                }
                if (/^\d+$/.test(trimmed)) {
                    return true;
                }
                if (/^[:«]r[a-z0-9_-]*[:»]?$/i.test(trimmed)) {
                    return true;
                }
                if (/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(trimmed)) {
                    return true;
                }
                if (/^[0-9a-f]{12,}$/i.test(trimmed) || /[-_][0-9a-f]{8,}$/i.test(trimmed)) {
                    return true;
                }
                if (/^(?:ember|react|mui|radix|headlessui|rc-tabs|el-id|el-popper|tippy)(?:[-_:\d]|$)/i.test(trimmed)) {
                    return true;
                }
                if (/^aria-[a-z-]*\d/i.test(trimmed)) {
                    return true;
                }
                if (/[-_]\d{4,}$/.test(trimmed)) {
                    return true;
                }
                const parts = trimmed.split(/[-_]/);
                if (parts.length >= 2 && looksLikeHash(parts[parts.length - 1])) {
                    return true;
                }
                return false;
            };

            const isSpecificID = (id) => (
                !isDynamicID(id) && !GENERIC_ROOT_IDS.has(id.trim().toLowerCase())
            );

            const isStateOrThemeToken = (name) => {
                if (!name) {
                    return false;
                }
                return STATE_OR_THEME_CLASSES.has(name.toLowerCase()) || STATE_PREFIX_RE.test(name);
            };

            const isUtilityClass = (name) => (
                !name || /[:[\]/!]/.test(name) || UTILITY_CLASS_RE.test(name) || SINGLETON_UTILITY_RE.test(name)
            );

            const extractCSSModulePrefix = (name) => {
                if (!name || typeof name !== 'string' || /[{}]/.test(name)) {
                    return null;
                }
                const viteMatch = name.match(/^(_[A-Za-z][A-Za-z0-9-]{2,}_)([a-z0-9]{5,8})_\d+$/);
                if (viteMatch) {
                    const local = viteMatch[1].slice(1, -1);
                    if (!isStateOrThemeToken(local) && !GENERIC_CLASSES.has(local.toLowerCase())) {
                        return viteMatch[1];
                    }
                    return null;
                }
                const wpMatch = name.match(/^([A-Za-z][A-Za-z0-9-]*(?:_{1,2}[A-Za-z][A-Za-z0-9-]*)*_{1,3})([A-Za-z0-9_-]{4,10})$/);
                if (!wpMatch) {
                    return null;
                }
                const prefix = wpMatch[1];
                const hash = wpMatch[2];
                if (!looksLikeHash(hash)) {
                    return null;
                }
                const segments = prefix.replace(/_+$/, '').split(/_+/).filter(Boolean);
                if (segments.length === 0) {
                    return null;
                }
                const lastSeg = segments[segments.length - 1];
                if (isStateOrThemeToken(lastSeg)) {
                    return null;
                }
                if (segments.length === 1 && GENERIC_CLASSES.has(lastSeg.toLowerCase())) {
                    return null;
                }
                if (segments.length >= 2 && isStateOrThemeToken(segments[0])) {
                    return null;
                }
                return prefix;
            };

            const cssModulePrefixSelector = (prefix) => {
                const escaped = escapeAttrValue(prefix);
                return `:is([class^="${escaped}"],[class*=" ${escaped}"])`;
            };

            const isStableClassName = (name) => {
                if (typeof name !== 'string' || !name || name.length > 80 || /\s|[{}]/.test(name)) {
                    return false;
                }
                if (!/^[A-Za-z_-][A-Za-z0-9_-]*$/.test(name)) {
                    return false;
                }
                if (/^v-(?:enter|leave|move|bind)/i.test(name) || /^ng-/i.test(name)) {
                    return false;
                }
                if (CSS_IN_JS_HASH_RE.test(name) || /^jss\d+$/i.test(name)) {
                    return false;
                }
                if (isUtilityClass(name) || isStateOrThemeToken(name)) {
                    return false;
                }
                if (extractCSSModulePrefix(name)) {
                    return false;
                }
                if (looksLikeHash(name)) {
                    return false;
                }
                return true;
            };

            const isSpecificClassName = (name) => (
                isStableClassName(name) && !GENERIC_CLASSES.has(name.toLowerCase())
            );

            const isStableTier1Value = (value) => {
                if (typeof value !== 'string') {
                    return false;
                }
                const trimmed = value.trim();
                return trimmed.length > 0
                    && trimmed.length <= 60
                    && !/[{}\n\r]/.test(trimmed)
                    && !/^\d+$/.test(trimmed)
                    && !/[0-9a-f]{8}-[0-9a-f]{4}-/i.test(trimmed);
            };

            const isStableSemanticAttrValue = (value) => {
                if (typeof value !== 'string') {
                    return false;
                }
                const trimmed = value.trim();
                if (!trimmed || trimmed.length > 50 || /[{}\n\r]/.test(trimmed)) {
                    return false;
                }
                if (/\d{1,2}:\d{2}/.test(trimmed) || /[¥$€£]\s*\d/.test(trimmed) || /^\d+$/.test(trimmed)) {
                    return false;
                }
                if (/(?:^|\D)\d{2,}(?:\D|$)/.test(trimmed)) {
                    return false;
                }
                return true;
            };

            const isCleanStaticHref = (href) => {
                if (typeof href !== 'string') {
                    return false;
                }
                const trimmed = href.trim();
                if (trimmed.length < 2 || trimmed.length > 60 || /[{}\n\r?#]/.test(trimmed)) {
                    return false;
                }
                if (!((trimmed.startsWith('/') && !trimmed.startsWith('//')) || /^https?:\/\//i.test(trimmed))) {
                    return false;
                }
                if (/\d{4,}/.test(trimmed)) {
                    return false;
                }
                return true;
            };

            const extractStableAttributes = (element) => {
                const tier1 = [];
                const tier2 = [];
                const vueScopes = [];
                let staticHref = null;
                const tag = element.tagName.toLowerCase();

                for (const name of TIER1_ATTRS) {
                    const value = element.getAttribute(name);
                    if (isStableTier1Value(value)) {
                        tier1.push(`[${CSS.escape(name)}="${escapeAttrValue(value.trim())}"]`);
                    }
                }

                for (const name of TIER2_ATTRS) {
                    const value = element.getAttribute(name);
                    if (isStableSemanticAttrValue(value)) {
                        tier2.push(`[${CSS.escape(name)}="${escapeAttrValue(value.trim())}"]`);
                    }
                }

                const role = element.getAttribute('role');
                if (role && LANDMARK_ROLES.has(role.trim().toLowerCase())) {
                    tier2.push(`[role="${escapeAttrValue(role.trim().toLowerCase())}"]`);
                }

                if (tag === 'a') {
                    const href = element.getAttribute('href');
                    if (isCleanStaticHref(href)) {
                        staticHref = `a[href="${escapeAttrValue(href.trim())}"]`;
                    }
                }

                for (let i = 0; i < element.attributes.length; i++) {
                    const attr = element.attributes[i];
                    if (/^data-v-[a-f0-9]{6,12}$/i.test(attr.name)) {
                        vueScopes.push(`[${CSS.escape(attr.name)}]`);
                    }
                }

                return { tier1, tier2, staticHref, vueScopes };
            };

            const isStableFinderAttr = (name, value) => {
                if (TIER1_ATTR_SET.has(name)) {
                    return isStableTier1Value(value);
                }
                if (name === 'aria-label' || name === 'title' || name === 'alt' || name === 'name') {
                    return isStableSemanticAttrValue(value);
                }
                if (name === 'role') {
                    return typeof value === 'string' && LANDMARK_ROLES.has(value.trim().toLowerCase());
                }
                if (name === 'href') {
                    return isCleanStaticHref(value);
                }
                return false;
            };

            const splitSelectorParts = (sel) => {
                const parts = [];
                let current = '';
                let bracketDepth = 0;
                let parenDepth = 0;
                let quote = null;

                for (let i = 0; i < sel.length; i++) {
                    const ch = sel[i];
                    if (quote) {
                        current += ch;
                        if (ch === '\\' && i + 1 < sel.length) {
                            current += sel[++i];
                        } else if (ch === quote) {
                            quote = null;
                        }
                        continue;
                    }
                    if (ch === '"' || ch === "'") {
                        quote = ch;
                        current += ch;
                        continue;
                    }
                    if (ch === '[') {
                        bracketDepth++;
                        current += ch;
                        continue;
                    }
                    if (ch === ']') {
                        bracketDepth = Math.max(0, bracketDepth - 1);
                        current += ch;
                        continue;
                    }
                    if (ch === '(') {
                        parenDepth++;
                        current += ch;
                        continue;
                    }
                    if (ch === ')') {
                        parenDepth = Math.max(0, parenDepth - 1);
                        current += ch;
                        continue;
                    }
                    if (bracketDepth === 0 && parenDepth === 0 && /[\s>+~]/.test(ch)) {
                        if (current.trim()) {
                            parts.push(current.trim());
                            current = '';
                        }
                        continue;
                    }
                    current += ch;
                }
                if (current.trim()) {
                    parts.push(current.trim());
                }
                return parts;
            };

            const extractSimpleIdentifiersOutsideBrackets = (segment) => {
                let stripped = '';
                let bracketDepth = 0;
                let parenDepth = 0;
                let quote = null;

                for (let i = 0; i < segment.length; i++) {
                    const ch = segment[i];
                    if (quote) {
                        if (ch === '\\' && i + 1 < segment.length) {
                            i++;
                        } else if (ch === quote) {
                            quote = null;
                        }
                        continue;
                    }
                    if (ch === '"' || ch === "'") {
                        quote = ch;
                        continue;
                    }
                    if (ch === '[') {
                        bracketDepth++;
                        continue;
                    }
                    if (ch === ']') {
                        bracketDepth = Math.max(0, bracketDepth - 1);
                        continue;
                    }
                    if (ch === '(') {
                        parenDepth++;
                        continue;
                    }
                    if (ch === ')') {
                        parenDepth = Math.max(0, parenDepth - 1);
                        continue;
                    }
                    if (bracketDepth === 0 && parenDepth === 0) {
                        stripped += ch;
                    }
                }

                const ids = [];
                const classes = [];
                const tokenRe = /([#.])((?:\\.|[A-Za-z0-9_-])+)/g;
                let m;
                while ((m = tokenRe.exec(stripped)) !== null) {
                    const raw = m[2].replace(/\\(.)/g, '$1');
                    if (m[1] === '#') {
                        ids.push(raw);
                    } else {
                        classes.push(raw);
                    }
                }
                return { ids, classes };
            };

            const segmentHasSpecificToken = (segment) => {
                if (!segment) {
                    return false;
                }
                if (/\[class\^="[^"]+"\]/.test(segment)) {
                    return true;
                }
                for (const name of TIER1_ATTRS) {
                    if (segment.includes(`[${name}=`)) {
                        return true;
                    }
                }
                for (const name of TIER2_ATTRS) {
                    if (segment.includes(`[${name}=`)) {
                        return true;
                    }
                }
                if (/\[role="/.test(segment) || /\[href="/.test(segment)) {
                    return true;
                }
                const { ids, classes } = extractSimpleIdentifiersOutsideBrackets(segment);
                if (ids.some(isSpecificID)) {
                    return true;
                }
                if (classes.some(isSpecificClassName)) {
                    return true;
                }
                if (classes.some(isStableClassName) && /\[data-v-[a-f0-9]+\]/i.test(segment)) {
                    return true;
                }
                const hasIndex = segment.indexOf(':has(');
                if (hasIndex !== -1) {
                    const inner = segment.slice(hasIndex + 5, -1);
                    if (splitSelectorParts(inner).some(segmentHasSpecificToken)) {
                        return true;
                    }
                }
                return false;
            };

            const isUniqueMatch = (selector, target) => {
                if (!selector || typeof selector !== 'string' || /[{}\n\r]/.test(selector)) {
                    return false;
                }
                try {
                    const matches = document.querySelectorAll(selector);
                    return matches.length === 1 && matches[0] === target;
                } catch (_) {
                    return false;
                }
            };

            const isSafeSelector = (selector, target) => {
                if (!isUniqueMatch(selector, target)) {
                    return false;
                }
                const nthMatches = selector.match(/:nth-(?:of-type|child)\(/g);
                if (nthMatches && nthMatches.length > 1) {
                    return false;
                }
                const parts = splitSelectorParts(selector);
                if (parts.length === 0) {
                    return false;
                }
                const nonPositionalSpecific = parts.some(
                    (part) => !/:nth-(?:of-type|child)\(/.test(part) && segmentHasSpecificToken(part)
                );
                if (nthMatches && nthMatches.length === 1) {
                    return nonPositionalSpecific;
                }
                return parts.some(segmentHasSpecificToken);
            };

            const directIdentityCandidates = (element, allowGenericClasses = false) => {
                const candidates = [];
                const tag = element.tagName.toLowerCase();
                const id = element.getAttribute('id');
                if (id && isSpecificID(id)) {
                    candidates.push('#' + CSS.escape(id.trim()));
                }

                const attrs = extractStableAttributes(element);
                for (const attrSel of attrs.tier1) {
                    candidates.push(attrSel);
                }

                const modulePrefixes = [];
                const specificClasses = [];
                const genericStableClasses = [];
                for (let i = 0; i < element.classList.length; i++) {
                    const cls = element.classList[i];
                    const prefix = extractCSSModulePrefix(cls);
                    if (prefix && !modulePrefixes.includes(prefix)) {
                        modulePrefixes.push(prefix);
                    } else if (isSpecificClassName(cls)) {
                        specificClasses.push('.' + CSS.escape(cls));
                    } else if (isStableClassName(cls)) {
                        genericStableClasses.push('.' + CSS.escape(cls));
                    }
                }

                for (const prefix of modulePrefixes) {
                    candidates.push(cssModulePrefixSelector(prefix));
                }
                for (const clsSel of specificClasses) {
                    candidates.push(clsSel);
                }
                if (specificClasses.length >= 2) {
                    candidates.push(specificClasses[0] + specificClasses[1]);
                }
                for (const attrSel of attrs.tier2) {
                    candidates.push(tag + attrSel);
                    candidates.push(attrSel);
                }
                if (attrs.staticHref) {
                    candidates.push(attrs.staticHref);
                }

                if (allowGenericClasses) {
                    for (const clsSel of genericStableClasses) {
                        candidates.push(clsSel);
                    }
                }

                if (attrs.vueScopes.length > 0) {
                    const scope = attrs.vueScopes[0];
                    for (const clsSel of specificClasses) {
                        candidates.push(clsSel + scope);
                    }
                    for (const clsSel of genericStableClasses) {
                        candidates.push(clsSel + scope);
                    }
                }

                return Array.from(new Set(candidates));
            };

            const anchorTokensForElement = (element) => {
                const tokens = [];
                const tag = element.tagName.toLowerCase();
                const id = element.getAttribute('id');
                if (id && isSpecificID(id)) {
                    tokens.push('#' + CSS.escape(id.trim()));
                }
                const attrs = extractStableAttributes(element);
                tokens.push(...attrs.tier1);
                for (let i = 0; i < element.classList.length; i++) {
                    const cls = element.classList[i];
                    const prefix = extractCSSModulePrefix(cls);
                    if (prefix) {
                        tokens.push(cssModulePrefixSelector(prefix));
                    } else if (isSpecificClassName(cls)) {
                        tokens.push('.' + CSS.escape(cls));
                    }
                }
                tokens.push(...attrs.tier2);
                if (SEMANTIC_LANDMARK_TAGS.has(tag)) {
                    tokens.push(tag);
                }
                if (attrs.vueScopes.length > 0) {
                    for (let i = 0; i < element.classList.length; i++) {
                        const cls = element.classList[i];
                        if (isStableClassName(cls)) {
                            tokens.push('.' + CSS.escape(cls) + attrs.vueScopes[0]);
                        }
                    }
                }
                return Array.from(new Set(tokens));
            };

            const descendantFingerprintCandidates = (target) => {
                const results = [];
                const queue = [];
                for (const child of target.children) {
                    if (!isOwnUI(child)) {
                        queue.push({ node: child, depth: 1, chain: [child.tagName.toLowerCase()] });
                    }
                }

                let visited = 0;
                while (queue.length > 0 && visited < 60) {
                    const current = queue.shift();
                    visited++;
                    const { node, depth, chain } = current;
                    const ids = directIdentityCandidates(node, false);
                    for (const descSel of ids) {
                        results.push({ descSel, chain, depth });
                    }
                    if (depth < 4) {
                        for (const child of node.children) {
                            if (!isOwnUI(child)) {
                                queue.push({
                                    node: child,
                                    depth: depth + 1,
                                    chain: chain.concat(child.tagName.toLowerCase())
                                });
                            }
                        }
                    }
                }
                return results;
            };

            const buildStableSelector = (target) => {
                if (
                    !target
                    || target.nodeType !== Node.ELEMENT_NODE
                    || !document.body
                    || target === document.body
                    || target === document.documentElement
                    || !document.body.contains(target)
                ) {
                    return '';
                }

                // Strategy 1: Direct semantic identity on target
                for (const candidate of directIdentityCandidates(target, false)) {
                    if (isSafeSelector(candidate, target)) {
                        return candidate;
                    }
                }

                // Collect up to 8 ancestors inside document.body
                const ancestors = [];
                let cursor = target.parentElement;
                while (cursor && cursor !== document.body && ancestors.length < 8) {
                    const anchorTokens = anchorTokensForElement(cursor);
                    if (anchorTokens.length > 0) {
                        ancestors.push({
                            element: cursor,
                            isDirectParent: cursor === target.parentElement,
                            tokens: anchorTokens
                        });
                    }
                    cursor = cursor.parentElement;
                }

                // Strategy 2: Semantic ancestor-anchored non-positional chain
                const targetTag = target.tagName.toLowerCase();
                const targetTokens = directIdentityCandidates(target, true);
                if (!targetTokens.includes(targetTag)) {
                    targetTokens.push(targetTag);
                }

                // 2a: Single strong ancestor + target token (prefer direct parent combinator when applicable)
                for (const ancestor of ancestors) {
                    for (const anchor of ancestor.tokens) {
                        for (const tToken of targetTokens) {
                            const combinators = ancestor.isDirectParent ? [' > ', ' '] : [' '];
                            for (const comb of combinators) {
                                const candidate = anchor + comb + tToken;
                                if (isSafeSelector(candidate, target)) {
                                    return candidate;
                                }
                            }
                        }
                    }
                }

                // 2b: Two semantic ancestors + target token
                for (let i = 0; i < ancestors.length; i++) {
                    for (let j = i + 1; j < ancestors.length; j++) {
                        const near = ancestors[i];
                        const far = ancestors[j];
                        const nearComb = near.isDirectParent ? ' > ' : ' ';
                        for (const farTok of far.tokens.slice(0, 2)) {
                            for (const nearTok of near.tokens.slice(0, 2)) {
                                for (const tToken of targetTokens.slice(0, 4)) {
                                    const candidate = farTok + ' ' + nearTok + nearComb + tToken;
                                    if (isSafeSelector(candidate, target)) {
                                        return candidate;
                                    }
                                }
                            }
                        }
                    }
                }

                // Strategy 3: :has(...) descendant fingerprint for anonymous wrapper blocks
                const fingerprints = descendantFingerprintCandidates(target);
                const parentEl = target.parentElement;
                const parentAnchors = parentEl && parentEl !== document.body ? anchorTokensForElement(parentEl) : [];

                for (const fp of fingerprints) {
                    const directPath = fp.chain.slice(0, -1).map((tag) => `${tag} > `).join('');
                    const directCandidate = `${targetTag}:has(> ${directPath}${fp.descSel})`;
                    if (isSafeSelector(directCandidate, target)) {
                        return directCandidate;
                    }

                    for (const pAnchor of parentAnchors) {
                        const parentAnchored = `${pAnchor} > ${targetTag}:has(${fp.descSel})`;
                        if (isSafeSelector(parentAnchored, target)) {
                            return parentAnchored;
                        }
                    }

                    for (const ancestor of ancestors) {
                        for (const anchor of ancestor.tokens) {
                            const comb = ancestor.isDirectParent ? ' > ' : ' ';
                            const anchored = `${anchor}${comb}${targetTag}:has(${fp.descSel})`;
                            if (isSafeSelector(anchored, target)) {
                                return anchored;
                            }
                        }
                    }
                }

                // Strategy 4: Configured finder fallback gated by strict safety validator
                try {
                    const fallbackSelector = finder(target, {
                        root: document.body,
                        idName: isSpecificID,
                        className: isSpecificClassName,
                        attr: isStableFinderAttr,
                        seedMinLength: 3,
                        optimizedMinLength: 2,
                        timeoutMs: 600
                    });
                    if (isSafeSelector(fallbackSelector, target)) {
                        return fallbackSelector;
                    }
                } catch (_) {
                    return '';
                }

                return '';
            };

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
                    selector = buildStableSelector(target);
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
                generateSelector: (target) => buildStableSelector(target),
                startPicking,
                stopPicking,
                showUndoToast,
                reportBroadRule: (selector, label, limit) => {
                    let count = 0;
                    try {
                        count = document.querySelectorAll(selector).length;
                    } catch (error) {
                        return;
                    }
                    if (count > limit) {
                        handler?.postMessage({ type: 'broad', selector, label, count });
                    }
                }
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
