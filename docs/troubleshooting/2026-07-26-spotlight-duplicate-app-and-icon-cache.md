# Spotlight 重复 App 与图标缓存排查记录

安装、构建、改 App 图标，或排查 Spotlight 出现多个 NeatWebApp、图标不刷新、旧副本残留时使用本记录。

## 一句话结论

Spotlight 的应用结果不只来自磁盘文件名，还会受到 Spotlight 元数据和 LaunchServices 应用注册共同影响。只删除编译目录、只改图标、只重启 Finder，或只看 `mdfind` 都不足以证明问题已经解决。

## 现象与根因

### 系统搜索出现多个 NeatWebApp

Xcode 构建 macOS App 时会把生成的主程序和 Runtime 注册到 LaunchServices。历史构建目录、性能基线目录、安装过程中的备份和废纸篓副本都可能继续保留注册，因此 Spotlight 会把它们当作可打开的独立应用展示。

`DerivedData.noindex` 只能阻止 Spotlight 对目录做常规元数据索引，不能保证 Xcode 不注册构建产物。项目共享 Scheme 的构建后动作因此必须继续注销：

1. 编译出的 `NeatWebApp.app`。
2. 独立的 `NeatWebAppRuntime.app`。
3. 主程序内部的 `NeatWebAppRuntime.app`。

### `/Applications` 已替换但仍显示旧图标

图标缓存可能仍指向同一应用标识下的旧构建包或废纸篓副本。新图标已经进入正式安装包，并不代表 Finder、Spotlight 和 LaunchServices 已经切换到该包。

先消除重复注册，再刷新正式安装包；不要反过来反复重建图标。

## 预防规则

- 构建统一使用 `build/DerivedData.noindex`，不要恢复 `build/DerivedData` 或 `PlanBaseline` 作为日常构建输出。
- 不要删除共享 Scheme 中“避免编译副本出现在系统搜索中”的构建后动作。
- 日常启动只允许从 `/Applications/NeatWebApp.app` 进入，不直接打开编译目录里的 App。
- 安装过程产生临时备份时，完成回滚保护后要注销并清理该备份；仅移入废纸篓仍可能留下 LaunchServices 记录。
- 若要求磁盘上也只保留正式安装包，全部验证结束后执行一次同一路径的 `xcodebuild clean`。

## 最短修复路径

### 1. 盘点实际副本

```bash
find /Applications "$PWD/build" "$HOME/.Trash" \
  -iname 'NeatWebApp*.app' -type d -prune -print 2>/dev/null
```

最终主程序只应有：

```text
/Applications/NeatWebApp.app
```

正式主程序内部的 `Contents/Library/LoginItems/NeatWebAppRuntime.app` 是内嵌运行组件，不是多安装了一份主程序。

### 2. 盘点 LaunchServices 记录

```bash
launcher_db="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$launcher_db" -dump \
  | sed -n 's/^path:[[:space:]]*\(.*\) (0x[0-9a-f]*).*/\1/p' \
  | sort -u \
  | grep 'NeatWebApp'
```

健康状态只保留：

```text
/Applications/NeatWebApp.app
/Applications/NeatWebApp.app/Contents/Library/LoginItems/NeatWebAppRuntime.app
```

### 3. 注销所有非正式路径

对上一步列出的每个编译目录、历史目录、临时备份和废纸篓路径执行：

```bash
"$launcher_db" -u "/需要注销的精确路径"
```

全部处理后压缩数据库并重新注册正式安装包：

```bash
"$launcher_db" -gc
"$launcher_db" -f -R -trusted "/Applications/NeatWebApp.app"
```

在 zsh 脚本中遍历这些路径时，循环变量必须命名为 `bundle_path` 等业务名，禁止命名为 `path`。`path` 是 zsh 与 `PATH` 绑定的特殊数组，误用会让后续 `sed`、`sort` 等命令突然全部变成“找不到命令”。

### 4. 刷新正式图标并启动

```bash
touch "/Applications/NeatWebApp.app"
killall iconservicesagent 2>/dev/null || true
killall Finder 2>/dev/null || true
open "/Applications/NeatWebApp.app"
```

如果还要保证磁盘上没有编译 App，确认测试、分析和安装验证已完成后执行：

```bash
xcodebuild \
  -project "NeatWebApp.xcodeproj" \
  -scheme "NeatWebApp" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData.noindex \
  clean
```

## 验收

必须同时检查以下四项，不能只凭其中一项宣布完成：

1. 文件系统盘点只找到 `/Applications/NeatWebApp.app`。
2. LaunchServices 只保留正式主程序和其内嵌 Runtime 两条记录。
3. 运行进程路径来自 `/Applications/NeatWebApp.app/Contents/MacOS/NeatWebApp`。
4. Finder 中正式安装包显示当前 App 图标；菜单栏显示透明单色模板图标。

`mdfind` 适合检查 Spotlight 元数据，但它不是应用搜索结果的唯一真相源；新安装包尚未进入元数据索引时可能返回空，LaunchServices 仍可能已经正确。排查重复 App 时必须与 LaunchServices 记录交叉验证。

<!-- 该文档整理/压缩于 2026-09-05 -->
