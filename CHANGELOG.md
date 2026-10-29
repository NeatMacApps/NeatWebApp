# Changelog

Release notes are bilingual: English first, then complete Simplified Chinese.
Development adds entries under `## Unreleased`; at release time they become the
next version's section. A `Release: minor` or `Release: major` line requests a
larger version step; `Release: hold <reason>` keeps the changes unreleased until
the named acceptance is done.

## Unreleased

## 0.3.35

English:

- Bookmark rows gain a native right-click menu (Open, Rename, Add WebApp, Delete); Add WebApp builds an isolated app from the bookmark's title and URL, importing source HTTP cookies via a one-time Keychain handoff before first navigation.
- Website icon loading is recoverable and pressure-aware: transient failures retry with capped backoff, and memory pressure only pauses speculative prefetch.

简体中文：

- 收藏夹行支持原生右键菜单（打开、重命名、添加为网页应用、删除）；从收藏添加网页应用时经一次性钥匙串交接导入来源 HTTP Cookie。
- 网站图标加载可恢复且能感知内存压力：短暂失败按上限退避重试，内存压力只暂停推测性预取。
