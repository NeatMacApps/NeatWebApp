# 发布分发与应用内自动更新（NeatWebApp 专有部分）

> 通用做法——分发形态选择、证书与密钥体系、构建配置基线、公证与票据装订、安装包制作、Sparkle 自更新、发版脚本骨架、踩坑速查表——见工作区共享文档 [macOS 应用签名、公证、分发与应用内自更新](../../../../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)。**本文只记 NeatWebApp 独有的取值与决策**，不重复通用规则。

**状态**：已于 2026-08-03 在 Mac 上完成首次发版，v0.3.0 与 v0.3.1 均已签名、公证、装订并发布到两仓，正式 dmg 经匿名下载、票据校验与 Gatekeeper 判定验证通过。更新签名密钥已生成，公钥已写入宿主 `Info.plist`。

## 分发拓扑

- 私有源码仓 `Max/NeatWebApp`（默认分支 `master`）：源码、提交、标签和 dmg 备份，浏览器需登录。Git 远端走内网直连 `ssh://git@10.10.10.2:2222/Max/NeatWebApp.git`。
- 公开只读更新仓 `Max/NeatWebApp-updates`（默认分支 `main`）：只放 appcast、版本说明、zip 更新包和 dmg 首装包，不含源码，匿名可下载。
  - 首次安装页：`https://forgejo.caozc.top/Max/NeatWebApp-updates/releases/latest`
  - 自动更新清单：`https://forgejo.caozc.top/Max/NeatWebApp-updates/raw/branch/main/appcast.xml`
  - 更新仓 Git 远端：`ssh://git@10.10.10.2:2222/Max/NeatWebApp-updates.git`
- 不把私有源码仓改公开，也不把 Forgejo 访问令牌嵌进应用；已安装客户端不需要保存任何令牌。

## NeatWebApp 的具体取值

| 项 | 值 | 存放位置 |
|---|---|---|
| 团队标识 | `SHZQ3MWP3B` | `project.yml` 的 `settings.base` |
| 宿主包标识 | `com.geraltgraham.NeatWebApp` | `project.yml` |
| 内嵌运行时包标识 | `com.geraltgraham.NeatWebAppRuntime` | `project.yml` |
| 签名身份 | `Developer ID Application: Zhichao Cao (SHZQ3MWP3B)` | 本机登录钥匙串，与 JotBox 共用同一张证书 |
| Developer ID 描述文件 | **不需要**，见下 | — |
| 公证密钥 | 团队级 Team Key，与 JotBox 共用同一把 | `~/Documents/P8 密钥/发布公证密钥/` |
| Sparkle 更新签名密钥 | 钥匙串 account `neatwebapp`（**与 JotBox 的那把分开**）；应用内只存公钥 `SUPublicEDKey` | 本机钥匙串，私钥不导出、不进环境变量、不进仓库 |

## NeatWebApp 独有的决策

- **不需要 Developer ID 描述文件，也不需要在苹果开发者网站注册应用标识。** 本应用只声明摄像头与麦克风（`com.apple.security.device.camera` / `.audio-input`），它们属于加固运行时的资源访问权限，苹果不做背书、裸证书签名即可。这是与 JotBox 最大的差别——JotBox 因为要做 Passkey 才必须配描述文件。**因此 Release 配置里 `PROVISIONING_PROFILE_SPECIFIER` 显式留空**，避免手动签名模式下 Xcode 反过来去找一份不存在的描述文件。若将来给本应用加了 Associated Domains、推送等受管权限，这条即刻失效，必须回到苹果网站注册应用标识并生成描述文件。
- **版本号只有一个来源：`project.yml` 的 `settings.base`。** 宿主与内嵌运行时两个 `Info.plist` 都用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 取值，所以发版脚本不需要像 JotBox 那样做跨文件比对。发版前只改 `project.yml` 一处：展示版本按 SemVer，内部构建号是 Sparkle 判断新旧的唯一权威值、必须严格递增的正整数（当前编码习惯：`0.3.0` → `3000`）。只改展示版本不递增构建号 = 用户端永远提示「已是最新」。
- **两个程序都要签、都要过公证自检。** 每个 WebApp 窗口都是内嵌运行时 `Contents/Library/LoginItems/NeatWebAppRuntime.app` 的一个独立进程。它是嵌套可执行文件，苹果会单独审，缺 Developer ID 签名、加固运行时或带 `get-task-allow` 都会整包被打回。发版脚本对宿主和内嵌运行时各跑一遍签名三连自检，另加一次 `codesign --verify --deep --strict` 兜住 Sparkle 的 XPC 组件。签名顺序由 Xcode 保证（运行时是宿主的构建依赖，先产出先签），**不要在脚本里手工补签，更不要用 `--deep`**。
- **自动更新只装在宿主上，运行时不自更新。** 更新是把整个应用包换掉，内嵌运行时跟着一起被替换。
- **覆盖安装前先收掉所有运行时。** 运行时是从应用包内部启动的独立进程，应用包被替换后它们会继续跑在旧代码上、注册表状态也失效。`AppUpdater` 在 Sparkle 的 `updater(_:willInstallUpdate:)` 与 `updaterWillRelaunchApplication(_:)` 两个回调里（取先到的那次）调用 `AppModel.prepareForApplicationUpdate()` 收尾。**这里不等它们退干净**——宿主马上要退出，等不了；漏网的会在下次启动时被既有的运行时版本迁移逻辑（`WebAppRuntimeCoordinator.migrateOutdatedRuntimesIfNeeded`，依据内嵌运行时可执行文件的修改时间与大小判定）重启到新版本。
- **发版产物必须来自「归档 → 按 Developer ID 导出」，不能取直接构建的产物。** 通用根因见共享文档，这里只记本项目的落地：脚本先 `archive` 到 `build/NeatWebApp.xcarchive`，再用 `method: developer-id` 的最小 `ExportOptions.plist`（脚本内联生成，不额外留文件）导出到 `build/export`，后续公证、装订、打包全部基于导出产物。首次发版时正是踩在这条上——直接构建的产物里 Sparkle 框架内部的 `Updater.app`、`Autoupdate` 与两个 XPC 服务仍是临时签名，苹果逐字打回。
- **内嵌运行时必须设 `SKIP_INSTALL: YES`。** 不设的话它会作为独立产品进归档，`Products/Applications/` 下同时出现宿主与运行时两个应用，Xcode 判定不出分发方式，导出报「`method` 的可选值列表为空」，看起来像参数写错，实际是归档不合法。判据：正常归档的 `Info.plist` 含 `ApplicationProperties`。设了之后运行时照常作为宿主依赖被内嵌进 `Contents/Library/LoginItems`。
- **签名自检必须逐个核对嵌套组件的签发者与时间戳。** `codesign --verify --deep --strict` 对临时签名的嵌套组件照样返回通过（它只看结构完整性），本地查不出任何异常，唯一反馈渠道是几十分钟后苹果的公证结果。脚本的 `assert_nested_helpers_signed` 就是补这个洞的。
- **首装用 dmg、更新用 zip**，两者挂在公开更新仓同一版本的 Release 下；dmg 内不放任何 Gatekeeper 绕过脚本。
- **Sparkle 行为**：每天自动检查，默认自动下载并安装；菜单栏保留「检查更新…」手动入口；宿主是 `LSUIElement`（常驻菜单栏、无主窗口），所以打开了温和提醒——只有用户主动触发时才让更新窗口抢焦点。**后台发现更新时不会弹窗**，只把菜单改成「安装 NeatWebApp x.x.x 更新…」；别把「没弹窗」当成「没更新」。
- **「另一台电脑收不到更新」先查公开 appcast，再查本机构建号。** 匿名打开 `https://forgejo.caozc.top/Max/NeatWebApp-updates/raw/branch/main/appcast.xml`，看最新 `sparkle:version`；若本地 `project.yml` 已抬版本但 appcast 仍是旧号，说明**还没跑完整 `publish-release.sh`**，不是客户端坏了。本机构建号 ≥ 线上最新时，Sparkle 正确表现为「已是最新」。
- **一上来就开签名清单校验。** `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 成对开启（Sparkle 要求必须成对），不只签更新包，连更新清单本身和版本说明也验签。清单自身的签名不是 XML 属性，而是 `generate_appcast` 追加在文件末尾的 `<!-- sparkle-signatures: … -->` 注释块，发版脚本按这个特征做检查。**开启后不允许再手工改已签名的 appcast**，脚本里不得出现「生成完再 sed 改两下」这种步骤。

## Mac 接手：发 v0.3.2（2026-08-10 会话未完成）

本地已备好 `project.yml` 的 `0.3.2` / `3020` 与 `scripts/release-notes/0.3.2.md`，但公开仓仍停在 **0.3.1**（无 `v0.3.2` tag / Release / zip）。在 Mac 上执行：

```bash
cd ~/Codes/NeatWebApp/app-macos && scripts/publish-release.sh
```

发完后用匿名请求确认 appcast 含 `3020`，再在装有 0.3.1 的机器上点「检查更新…」验证。

## 换发版机时要人手做的两步

这两步已在当前发版机（Mac）完成，只有换机或密钥丢失时才需要重做。

1. **生成 NeatWebApp 专用的更新签名密钥**（私钥只在钥匙串里，换机必须重做，且**换密钥等于所有老客户端收不到更新**，务必先备份原私钥）。先在 Mac 上跑一次 Release 构建让 Sparkle 工具就位，然后：

   ```bash
   build/DerivedData.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account neatwebapp
   ```

   把打印出的公钥填进 `Sources/NeatWebApp/App/Info.plist` 的 `SUPublicEDKey`，替换掉占位值 `REPLACE_WITH_SPARKLE_PUBLIC_KEY`。发版脚本会检查这个占位值是否还在，没换掉直接退出。

2. **确认 Developer ID 证书与公证密钥在位**。证书与 JotBox 共用同一张，公证密钥共用同一把，正常情况下不需要新建。缺失时的恢复方式见共享文档「证书与密钥体系」。

## 发版

```bash
scripts/publish-release.sh              # 完整发版
scripts/publish-release.sh --local-only # 只产出本地已公证的 dmg，不碰 git 与 Forgejo
```

前置：钥匙串有 Developer ID 证书与 account 为 `neatwebapp` 的 Sparkle 签名密钥、`.p8` 公证密钥在位、环境变量 `FORGEJO_REPO_TOKEN`（`--local-only` 不需要）。脚本可重复执行，tag / Release 已存在时走更新路径。

发版前只需改 `project.yml` 里的展示版本与内部构建号。构建号非正整数、或低于公开更新清单上的构建号，脚本都会直接退出。

**签名 / 公证 / `codesign` / `notarytool` 必须在 macOS 本机跑**——Linux 侧（suzhou）没有 `xcrun` 与钥匙串，不能代跑公证，连编译验证都做不了。

**在家里的网络下公证会卡死**，判别与临时绕过（换手机热点）见 [苹果公证上传在家里网络下必定卡死](../../../../.config/agentsync/docs/troubleshooting/2026-07-31-apple-notary-upload-stall.md)；这条修好之前发版要么换网络、要么先解决路由器分流，别误判成签名配置问题反复重交。

## 首次发版的验证结果（2026-08-03）

首次发版时逐条确认过的判断，除最后一条外均已被真机证实：

- 两处 `Info.plist` 的版本号确实取自构建变量，归档 `Info.plist` 的 `ApplicationProperties` 显示 `0.3.0` / `3000`。✅
- 内嵌运行时、Sparkle 框架及其内部 4 个辅助程序，导出后全部为 Developer ID 签名 + 加固运行时 + 可信时间戳。✅（**但这只在走 archive + export 时成立**，见上节）
- `spctl -a -vvv -t exec` 对应用包判定为 `accepted`，正式 dmg 匿名下载后 `stapler validate` 通过。✅
- `generate_appcast` 的构建号取到了实际值，线上 appcast 终检通过，防回退检查有效。✅
- **仍未验证**：Sparkle 的两个安装回调是否真的被调用到（`@objc` 可选协议方法签名写错时不报编译错误，只会静默不触发）。验证方式是从 0.3.1 起观察一次真实的应用内升级，看升级过程中 WebApp 窗口是否被正常收掉。0.3.0 → 0.3.1 是本项目第一次具备验证条件的升级。
