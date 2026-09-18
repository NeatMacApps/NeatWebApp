import Foundation
import WebKit

/// Skips paint for off-screen blocks in **any** long scrolling page.
///
/// This is a container-wide display optimization, not a site special case.
/// Homogeneous lists (chat turns, history rows, feed cards) stay in the DOM
/// so React/Vue keep working; off-screen items skip layout/paint until they
/// approach the viewport. Newest siblings stay live so streaming UIs are
/// not interrupted.
///
/// Do **not** use `content-visibility: auto` — WebKit can leave on-screen
/// content blank. Use explicit `hidden` only while the block is outside a
/// large margin.
enum BrowserOffscreenBlockParkingScript {
    @MainActor
    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    static let source = #"""
    (() => {
        if (window.__neatWebAppOffscreenParkInstalled) {
            return;
        }
        window.__neatWebAppOffscreenParkInstalled = true;

        const PARKED = 'data-neat-parked';
        const HEIGHT = '--neat-park-h';
        const MARK = 'data-neat-webapp-ui';
        const MIN_SIBLINGS = 6;
        const MIN_PARK_HEIGHT = 32;
        const MARGIN = 1000;
        const SKIP_TAGS = new Set([
            'HTML', 'BODY', 'HEAD', 'SCRIPT', 'STYLE', 'LINK', 'META',
            'INPUT', 'TEXTAREA', 'SELECT', 'BUTTON', 'VIDEO', 'AUDIO',
            'CANVAS', 'IFRAME', 'IMG', 'SVG', 'PATH', 'BR', 'HR'
        ]);

        const style = document.createElement('style');
        style.setAttribute(MARK, 'offscreen-park');
        style.textContent = `
            [${PARKED}] {
                content-visibility: hidden;
                contain: strict;
                contain-intrinsic-size: var(${HEIGHT}, 80px);
                height: var(${HEIGHT}, 80px);
                max-height: var(${HEIGHT}, 80px);
                overflow: hidden;
            }
            [contenteditable="true"] {
                contain: layout style;
            }
        `;

        const mountStyle = () => {
            const parent = document.head || document.documentElement;
            if (parent && !style.isConnected) {
                parent.appendChild(style);
            }
        };
        mountStyle();

        const isSkippable = (el) => {
            if (!(el instanceof HTMLElement)) {
                return true;
            }
            if (SKIP_TAGS.has(el.tagName) || el.hasAttribute(MARK) || el.closest(`[${MARK}]`)) {
                return true;
            }
            const position = getComputedStyle(el).position;
            return position === 'fixed' || position === 'sticky';
        };

        const isScrollable = (node) => {
            if (!(node instanceof HTMLElement)) {
                return false;
            }
            const overflowY = getComputedStyle(node).overflowY;
            return (overflowY === 'auto' || overflowY === 'scroll')
                && node.scrollHeight > node.clientHeight + 2;
        };

        const isVerticalList = (parent) => {
            const cs = getComputedStyle(parent);
            if (cs.flexDirection === 'row' || cs.flexDirection === 'row-reverse') {
                return false;
            }
            if ((cs.overflowX === 'auto' || cs.overflowX === 'scroll')
                && parent.scrollWidth > parent.clientWidth + 20) {
                return false;
            }
            return true;
        };

        const findScrollers = () => {
            const found = [];
            const seen = new Set();
            const add = (node) => {
                if (!(node instanceof HTMLElement) || seen.has(node)) {
                    return;
                }
                seen.add(node);
                found.push(node);
            };
            const scrolling = document.scrollingElement;
            if (scrolling instanceof HTMLElement && scrolling.scrollHeight > scrolling.clientHeight + 2) {
                add(scrolling);
            }
            document.querySelectorAll('div, main, section, article, ol, ul, [data-scroll-root]').forEach((node) => {
                if (isScrollable(node)) {
                    add(node);
                }
            });
            return found;
        };

        const collectParents = (scroller) => {
            const parents = [];
            const stack = [scroller];
            while (stack.length > 0) {
                const node = stack.pop();
                if (!(node instanceof Element)) {
                    continue;
                }
                if (node.childElementCount >= MIN_SIBLINGS) {
                    parents.push(node);
                    continue;
                }
                for (const child of node.children) {
                    if (child.childElementCount > 0) {
                        stack.push(child);
                    }
                }
            }
            return parents;
        };

        const isProtected = (el, items) => {
            if (el.contains(document.activeElement)) {
                return true;
            }
            const count = items.length;
            if (count === 0) {
                return true;
            }
            if (el === items[count - 1] || el === items[count - 2]) {
                return true;
            }
            const busy = el.getAttribute('aria-busy') === 'true'
                || items[count - 1].getAttribute('aria-busy') === 'true';
            return busy && el === items[count - 3];
        };

        const park = (el) => {
            if (!(el instanceof HTMLElement) || el.hasAttribute(PARKED)) {
                return;
            }
            const height = Math.ceil(el.getBoundingClientRect().height);
            if (height < MIN_PARK_HEIGHT) {
                return;
            }
            el.style.setProperty(HEIGHT, height + 'px');
            el.setAttribute(PARKED, '');
        };

        const unpark = (el) => {
            if (!(el instanceof HTMLElement) || !el.hasAttribute(PARKED)) {
                return;
            }
            el.removeAttribute(PARKED);
            el.style.removeProperty(HEIGHT);
        };

        const isNearViewport = (el, scroller) => {
            const rootRect = scroller.getBoundingClientRect();
            const rect = el.getBoundingClientRect();
            return rect.bottom > rootRect.top - MARGIN && rect.top < rootRect.bottom + MARGIN;
        };

        const syncItem = (el, scroller, items) => {
            if (isNearViewport(el, scroller) || isProtected(el, items)) {
                unpark(el);
            } else {
                park(el);
            }
        };

        const collectLists = () => {
            const lists = [];
            const seenParents = new Set();
            for (const scroller of findScrollers()) {
                for (const parent of collectParents(scroller)) {
                    if (seenParents.has(parent) || !isVerticalList(parent)) {
                        continue;
                    }
                    const items = [...parent.children].filter((child) => !isSkippable(child));
                    if (items.length < MIN_SIBLINGS) {
                        continue;
                    }
                    seenParents.add(parent);
                    lists.push({ scroller, items });
                }
            }
            return lists;
        };

        const observers = new Map();

        const bind = () => {
            mountStyle();
            const lists = collectLists();
            const liveItems = new Set();

            for (const observer of observers.values()) {
                observer.disconnect();
            }
            observers.clear();

            for (const { scroller, items } of lists) {
                const observer = new IntersectionObserver((entries) => {
                    for (const entry of entries) {
                        const el = entry.target;
                        if (!(el instanceof HTMLElement)) {
                            continue;
                        }
                        if (entry.isIntersecting || isProtected(el, items)) {
                            unpark(el);
                        } else {
                            park(el);
                        }
                    }
                }, {
                    root: scroller === document.scrollingElement ? null : scroller,
                    rootMargin: `${MARGIN}px 0px ${MARGIN}px 0px`,
                    threshold: 0
                });
                observers.set(scroller, observer);
                for (const el of items) {
                    liveItems.add(el);
                    observer.observe(el);
                    syncItem(el, scroller, items);
                }
            }

            document.querySelectorAll(`[${PARKED}]`).forEach((el) => {
                if (!liveItems.has(el)) {
                    unpark(el);
                }
            });
        };

        let bindFrame = 0;
        const scheduleBind = () => {
            if (bindFrame !== 0) {
                return;
            }
            bindFrame = requestAnimationFrame(() => {
                bindFrame = 0;
                bind();
            });
        };

        const mutations = new MutationObserver((records) => {
            for (const record of records) {
                if (record.type === 'childList' && (record.addedNodes.length > 0 || record.removedNodes.length > 0)) {
                    scheduleBind();
                    return;
                }
            }
        });
        mutations.observe(document.documentElement, { childList: true, subtree: true });

        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') {
                scheduleBind();
            }
        });

        scheduleBind();
        setTimeout(scheduleBind, 400);
        setTimeout(scheduleBind, 1200);
    })();
    """#
}
