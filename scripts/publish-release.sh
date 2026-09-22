#!/usr/bin/env bash
# NeatWebApp macOS 客户端一条命令发版：
#   Release 归档 → 按 Developer ID 导出 → 宿主、内嵌运行时与自更新框架嵌套组件的签名自检
#   → 苹果公证 → 装订票据
#   → 生成 Sparkle 签名更新包与 appcast → 打 dmg → 公证 dmg
#   → 提交 / 打 tag / 推送 → GitHub Release（先建空再传 dmg/zip）-> appcast 入库
#   -> Homebrew cask -> 匿名终检
#
# 用法：
#   scripts/publish-release.sh              完整发版
#   scripts/publish-release.sh --local-only 只做到「本地产出已公证的 dmg」，不碰 git 与 GitHub
#
# 前置条件（缺任何一项脚本会直接报错退出）：
#   1. 钥匙串里有 "Developer ID Application" 证书及其私钥
#   2. 本地配置 `scripts/publish-local.env`（未入库，模板见 `publish-local.env.example`）
#      提供公证密钥三件套与 Sparkle 签名账号；也可用同名环境变量覆盖
#   3. gh 已登录且有目标仓库权限（--local-only 时不需要）
#
# 必须在 macOS 本机运行：codesign / notarytool / stapler 都依赖本机 xcrun 与钥匙串，
# Linux 开发机上代跑不了，这不是偏好问题而是硬限制。
#
# 可重复执行：tag / Release 已存在时走更新路径，不会中断。

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly APP_NAME="NeatWebApp"
readonly REPO="NeatMacApps/NeatWebApp"
readonly REPO_WEB="https://github.com/${REPO}"
readonly FEED_URL="https://raw.githubusercontent.com/${REPO}/main/appcast.xml"
readonly CASK_NAME="neatwebapp"
readonly TAP_REPO="x0c/homebrew-tap"
# 本地私有配置（不入库）：公证密钥三件套 + Sparkle 签名账号；同名环境变量优先。
local_env="${ROOT_DIR}/scripts/publish-local.env"
[[ -f "${local_env}" ]] && source "${local_env}"
readonly NOTARY_KEY="${NOTARY_KEY:?缺少公证密钥文件路径（NOTARY_KEY），见 scripts/publish-local.env.example}"
readonly NOTARY_KEY_ID="${NOTARY_KEY_ID:?缺少公证 Key ID（NOTARY_KEY_ID）}"
readonly NOTARY_ISSUER="${NOTARY_ISSUER:?缺少公证 Issuer ID（NOTARY_ISSUER）}"
readonly SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:?缺少 Sparkle 签名账号（SPARKLE_ACCOUNT）}"
readonly SIGN_IDENTITY="Developer ID Application"
readonly SOURCE_BRANCH="main"
readonly BUILD_DIR="${ROOT_DIR}/build"
readonly DERIVED_DATA="${BUILD_DIR}/DerivedData.noindex"
# 发版产物走「归档 → 按 Developer ID 导出」，不能直接取 Build/Products/Release 下的构建产物：
# 只有导出这一步才会把 Sparkle 框架内部的 Updater.app、Autoupdate 与 XPC 服务重新签名，
# 详见下方 assert_nested_helpers_signed 的注释。
readonly ARCHIVE_PATH="${BUILD_DIR}/NeatWebApp.xcarchive"
readonly EXPORT_DIR="${BUILD_DIR}/export"
readonly APP_PATH="${EXPORT_DIR}/NeatWebApp.app"
# 内嵌运行时：每个 WebApp 窗口都是它的一个独立进程，必须和宿主一样是 Developer ID 签名 + 加固运行时，
# 否则整包公证会被苹果按「嵌套可执行文件不合规」打回。
readonly EMBEDDED_RUNTIME_PATH="${APP_PATH}/Contents/Library/LoginItems/NeatWebAppRuntime.app"
readonly NOTARY_POLL_INTERVAL=30      # 轮询公证结果的间隔（秒）
readonly NOTARY_TIMEOUT=3600          # 单次公证最长等待（秒）

local_only=false
[[ "${1:-}" == "--local-only" ]] && local_only=true

log_step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# 校验单个可执行程序包的签名是否满足公证要求。宿主与内嵌运行时各调一次。
assert_signed_for_distribution() {
  local target="$1" label="$2"
  local sign_info entitlements

  # 先把输出收进变量再 grep：开了 pipefail 时 `… | grep -q` 会因 grep 提前关管道让上游收到
  # SIGPIPE（退出码 141），整条管道被判失败，产生「明明签好了却报没签」的假故障
  sign_info="$(codesign -dv --verbose=2 "${target}" 2>&1)"
  entitlements="$(codesign -d --entitlements - "${target}" 2>/dev/null || true)"

  grep -q "Authority=${SIGN_IDENTITY}" <<<"${sign_info}" \
    || die "${label}不是 Developer ID 签名，检查 project.yml 的 Release 配置"
  grep -q "flags=.*runtime" <<<"${sign_info}" \
    || die "${label}没开加固运行时，苹果公证会打回"
  if grep -q "get-task-allow" <<<"${entitlements}"; then
    die "${label}带调试权限 get-task-allow，苹果公证会打回（检查 CODE_SIGN_INJECT_BASE_ENTITLEMENTS）"
  fi
}

# 校验 Sparkle 框架内部的嵌套辅助程序是否也被 Developer ID 重新签名并带可信时间戳。
#
# 单列一条检查的原因：这类问题**本地一切正常**，只有苹果会拒。
# `codesign --verify --deep --strict` 对临时签名的嵌套组件照样返回通过——临时签名在结构上
# 是合法签名，deep 校验只看结构完整性，不看签发者是谁。所以必须逐个显式核对签发者与时间戳，
# 否则唯一的反馈渠道就是几十分钟后苹果打回来的公证结果。
assert_nested_helpers_signed() {
  local framework="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B"
  local helper sign_info

  [[ -d "${framework}" ]] || die "找不到 Sparkle 框架，导出产物不完整"
  for helper in "${framework}/Updater.app" "${framework}/Autoupdate" \
                "${framework}/XPCServices/Downloader.xpc" "${framework}/XPCServices/Installer.xpc"; do
    [[ -e "${helper}" ]] || continue
    sign_info="$(codesign -dv --verbose=2 "${helper}" 2>&1)"
    grep -q "Authority=${SIGN_IDENTITY}" <<<"${sign_info}" \
      || die "自更新框架的嵌套组件 $(basename "${helper}") 仍是临时签名，苹果公证会打回。
这几乎总是因为产物取自 xcodebuild build 而不是 archive + exportArchive —— 检查上一步的导出是否真的成功。"
    grep -q "^Timestamp=" <<<"${sign_info}" \
      || die "自更新框架的嵌套组件 $(basename "${helper}") 的签名缺少可信时间戳，苹果公证会打回"
  done
}

# 在苹果侧的提交历史里认领「本次刚上传的那一笔」：按文件名匹配，且创建时间不早于本次开始时间。
# history 查询本身也可能被网络打断，所以重试几轮。
claim_submission_id() {
  local basename_file="$1" started_at="$2"
  local history_json claimed
  for _ in 1 2 3 4 5; do
    sleep 10
    history_json="$(xcrun notarytool history --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" \
      --issuer "${NOTARY_ISSUER}" --output-format json 2>/dev/null)" || continue
    claimed="$(jq -r --arg name "${basename_file}" --arg since "${started_at}" \
      '[.history[]? | select(.name==$name and .createdDate >= $since)]
       | sort_by(.createdDate) | last | .id // empty' <<<"${history_json}" 2>/dev/null || true)"
    [[ -n "${claimed}" ]] && { echo "${claimed}"; return 0; }
  done
  return 1
}

# 提交公证并轮询到出结果。
# 家里网络下 notarytool 的长连接会稳定地报 HTTPClientError.deadlineExceeded：
# 不只是 `--wait`，连 `submit` 本身也会——但**文件其实已经上传成功、苹果已受理**，
# 断的只是本地等回执那一段。所以 submit 失败不能当成发版失败，
# 要回头去 history 里认领「刚刚这一笔」的提交编号，再自己轮询状态。
notarize_and_wait() {
  local file="$1"
  local submit_json submission_id status waited=0
  local basename_file started_at
  basename_file="$(basename "${file}")"
  # 往前留 60 秒余量，避免时钟或秒内小数导致漏认领
  started_at="$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ)"

  submit_json="$(xcrun notarytool submit "${file}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" \
    --issuer "${NOTARY_ISSUER}" --output-format json 2>/dev/null)" || submit_json=""
  submission_id="$(jq -r '.id // empty' <<<"${submit_json:-{\}}" 2>/dev/null || true)"

  if [[ -z "${submission_id}" ]]; then
    echo "本地没收到提交回执（大概率是长连接超时），去苹果侧认领刚刚这一笔提交…"
    submission_id="$(claim_submission_id "${basename_file}" "${started_at}")"
    [[ -n "${submission_id}" ]] \
      || die "提交公证失败且苹果侧查不到这一笔：${file}（可用 notarytool history 和同一组公证凭据自查）"
  fi
  echo "提交编号：${submission_id}（苹果排队中，慢的时候可能要几十分钟）"

  local info_out consecutive_failures=0
  while (( waited < NOTARY_TIMEOUT )); do
    sleep "${NOTARY_POLL_INTERVAL}"
    waited=$(( waited + NOTARY_POLL_INTERVAL ))
    # 查询本身可能因网络抖动失败，偶发失败不算数；但连续失败必须报出来，
    # 否则「查不到」和「还在排队」在屏幕上长得一模一样，能空转到超时。
    info_out="$(xcrun notarytool info "${submission_id}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" \
      --issuer "${NOTARY_ISSUER}" --output-format json 2>&1)" || true
    status="$(jq -r '.status // empty' <<<"${info_out}" 2>/dev/null || true)"
    if [[ -z "${status}" ]]; then
      consecutive_failures=$(( consecutive_failures + 1 ))
      if (( consecutive_failures >= 5 )); then
        printf '\n'
        grep -qi "keychain" <<<"${info_out}" \
          && die "公证凭据读取异常：$(head -1 <<<"${info_out}")"
        die "连续 5 次查不到公证状态，先排查网络再重跑。原始报错：$(head -1 <<<"${info_out}")"
      fi
      printf '?'
      continue
    fi
    consecutive_failures=0
    [[ "${status}" == "In Progress" ]] && { printf '.'; continue; }
    printf '\n'
    if [[ "${status}" == "Accepted" ]]; then
      echo "公证通过（已等待约 $(( waited / 60 )) 分钟）"
      return 0
    fi
    xcrun notarytool log "${submission_id}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" \
      --issuer "${NOTARY_ISSUER}" 2>/dev/null | head -40 || true
    die "公证被拒（状态 ${status}），详细原因见上方日志"
  done
  die "公证等待超过 $(( NOTARY_TIMEOUT / 60 )) 分钟仍无结果，稍后用 notarytool info ${submission_id} 继续查"
}

# 打拖拽安装式 dmg。
# 苹果已宣告 hdiutil 在 macOS 27.0 废弃，替代命令 diskutil image 只有 macOS 26+ 才有，
# 所以按发版机的系统版本二选一，别无条件替换。
create_dmg() {
  local stage_dir="$1" volume_name="$2" output="$3"
  local macos_major
  macos_major="$(sw_vers -productVersion | cut -d. -f1)"

  rm -f "${output}"
  if (( macos_major >= 26 )); then
    diskutil image create from "${stage_dir}" "${output}" \
      --format UDZO --volumeName "${volume_name}" >/dev/null
  else
    hdiutil create -volname "${volume_name}" -srcfolder "${stage_dir}" \
      -ov -format UDZO "${output}" >/dev/null
  fi
}

cd "${ROOT_DIR}"

# ---------- 0. 前置检查 ----------
log_step "检查前置条件"
identities="$(security find-identity -v -p codesigning)"
grep -q "${SIGN_IDENTITY}" <<<"${identities}" \
  || die "钥匙串里没有 Developer ID Application 证书，无法对外分发（Xcode → Settings → Accounts → Manage Certificates 创建）"
[[ -f "${NOTARY_KEY}" ]] || die "找不到公证密钥文件：${NOTARY_KEY}"
notary_check="$(xcrun notarytool history --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" \
  --issuer "${NOTARY_ISSUER}" 2>&1)" \
  || die "公证密钥不可用（检查密钥文件、Key ID、Issuer ID 是否匹配）。原始报错：$(head -1 <<<"${notary_check}")"
if [[ "${local_only}" == false ]]; then
  gh auth status >/dev/null 2>&1 || die "gh 未登录"
  gh repo view "${REPO}" --json visibility --jq 'select(.visibility=="PUBLIC")' >/dev/null \
    || die "${REPO} 不存在或不是公开仓库"
fi

# 版本号的唯一来源是 project.yml，两个 Info.plist 都用构建变量取值，所以这里不需要跨文件比对。
version="$(sed -n 's/^ *MARKETING_VERSION: //p' project.yml | tr -d ' ')"
build_number="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: //p' project.yml | tr -d ' ')"
[[ -n "${version}" ]] || die "没能从 project.yml 读出展示版本号"
[[ "${build_number}" =~ ^[0-9]+$ && "${build_number}" -gt 0 ]] \
  || die "内部构建号必须是正整数，当前为：${build_number}"
readonly version
readonly build_number
readonly tag="v${version}"
readonly dmg_path="${BUILD_DIR}/NeatWebApp-${version}.dmg"
readonly update_zip_path="${BUILD_DIR}/NeatWebApp-${version}.zip"
readonly sparkle_bin_dir="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle/bin"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
readonly work_dir

sparkle_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Sources/NeatWebApp/App/Info.plist 2>/dev/null || true)"
[[ -n "${sparkle_public_key}" ]] || die "宿主 Info.plist 缺少 Sparkle 更新公钥 SUPublicEDKey"
[[ "${sparkle_public_key}" != "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]] \
  || die "还没生成 NeatWebApp 专用的更新签名密钥，见 docs/design/release-and-auto-update.md 的换机步骤"

# 防回退：排队错序或重复执行都可能把线上清单写回更低的构建号，用户端表现为「升级变降级」。
if [[ "${local_only}" == false ]] \
  && curl -fsSL "${FEED_URL}" -o "${work_dir}/current-appcast.xml" 2>/dev/null; then
  # 构建号在 appcast 里既可能是元素也可能是 enclosure 上的属性，两种写法都要认，
  # 只认一种的话检查会静默失效，防回退等于没做
  current_published_build="$(xmllint --xpath \
    'string((//*[local-name()="version"] | //@*[local-name()="version"])[1])' \
    "${work_dir}/current-appcast.xml" 2>/dev/null || true)"
  if [[ "${current_published_build}" =~ ^[0-9]+$ ]] \
    && (( build_number < current_published_build )); then
    die "拒绝回退公开更新清单：线上内部构建号 ${current_published_build}，本次为 ${build_number}"
  fi
fi
log_step "本次发布版本：${tag}（内部构建号 ${build_number}）"

# ---------- 1. 归档并导出 Developer ID 版本 ----------
# 这里必须是 archive + exportArchive 两步，不能用 xcodebuild build：
# 直接构建只会给应用包和框架本体签名，Sparkle 框架**内部**的 Updater.app、Autoupdate 与
# XPC 服务会保持 Sparkle 自带的临时（adhoc）签名，苹果公证一定打回
# （The binary is not signed with a valid Developer ID certificate / does not include a secure timestamp）。
# 只有按 Developer ID 导出这一步会把这些嵌套辅助程序逐个重新签名并打上可信时间戳。
# 依据：Sparkle 官方文档明确要求走 Archive + Distribute App (Developer ID)，
# 自动化环境用 xcodebuild archive 与 xcodebuild -exportArchive 等价替代。
log_step "生成 Xcode 工程并做 Release 归档"
xcodegen generate >/dev/null
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
xcodebuild -project NeatWebApp.xcodeproj -scheme NeatWebApp -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA}" \
  -archivePath "${ARCHIVE_PATH}" -allowProvisioningUpdates archive >/dev/null \
  || die "Release 归档失败"

log_step "按 Developer ID 导出（这一步才会重新签名 Sparkle 的嵌套辅助程序）"
export_options="${work_dir}/ExportOptions.plist"
cat > "${export_options}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>SHZQ3MWP3B</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${export_options}" -exportPath "${EXPORT_DIR}" \
  -allowProvisioningUpdates >/dev/null \
  || die "按 Developer ID 导出失败"
[[ -d "${APP_PATH}" ]] || die "导出产物不存在：${APP_PATH}"
[[ -d "${EMBEDDED_RUNTIME_PATH}" ]] || die "内嵌运行时不存在：${EMBEDDED_RUNTIME_PATH}"
[[ -x "${sparkle_bin_dir}/generate_appcast" ]] || die "找不到 Sparkle 的 generate_appcast 工具"
[[ -x "${sparkle_bin_dir}/sign_update" ]] || die "找不到 Sparkle 的 sign_update 工具"
[[ "$("${sparkle_bin_dir}/generate_keys" --account "${SPARKLE_ACCOUNT}" -p 2>/dev/null)" == "${sparkle_public_key}" ]] \
  || die "钥匙串里的 Sparkle 更新签名密钥缺失或与应用公钥不匹配（account: ${SPARKLE_ACCOUNT}）"

# ---------- 2. 签名自检 ----------
log_step "校验宿主与内嵌运行时的签名、加固运行时与权限清单"
assert_signed_for_distribution "${APP_PATH}" "宿主应用"
assert_signed_for_distribution "${EMBEDDED_RUNTIME_PATH}" "内嵌运行时"
assert_nested_helpers_signed
# 内嵌运行时和 Sparkle 的 XPC 服务都是嵌套代码，结构不完整时公证一定打回，这里先在本地拦下来
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>/dev/null \
  || die "嵌套代码签名校验失败（内嵌运行时或 Sparkle 组件），苹果公证会打回"

# ---------- 3. 公证应用本体 ----------
log_step "提交苹果公证（应用本体），首次通常 1-5 分钟"
rm -f "${BUILD_DIR}/NeatWebApp-notarize.zip"
ditto -c -k --keepParent "${APP_PATH}" "${BUILD_DIR}/NeatWebApp-notarize.zip"
notarize_and_wait "${BUILD_DIR}/NeatWebApp-notarize.zip"

log_step "把公证票据装订进应用"
xcrun stapler staple "${APP_PATH}" || die "装订票据失败"

# ---------- 4. 生成 Sparkle 更新包与清单 ----------
# 顺序不能反：Sparkle 下发的 zip 必须是「已装订票据的最终应用」，
# 先打包再公证的话用户装完首次启动仍要联网校验。
log_step "生成 Sparkle 签名更新包与 appcast"
release_notes_file="${work_dir}/release-notes.md"
custom_notes="${ROOT_DIR}/scripts/release-notes/${version}.md"
if [[ -f "${custom_notes}" ]]; then
  cp "${custom_notes}" "${release_notes_file}"
else
  cat > "${release_notes_file}" <<EOF
NeatWebApp macOS ${version}

- 把常用网站装成独立的 macOS 应用，从刘海位置的启动器一键唤出。
- 支持应用内自动检查、下载并安装更新。
- 安装包经过 Developer ID 签名与苹果公证，更新包另有 EdDSA 签名。
- 下载版双击即可打开，不需要执行任何解除限制命令。
EOF
fi

appcast_dir="${work_dir}/appcast"
mkdir -p "${appcast_dir}"
rm -f "${update_zip_path}"
ditto -c -k --keepParent "${APP_PATH}" "${update_zip_path}"
ditto "${update_zip_path}" "${appcast_dir}/NeatWebApp-${version}.zip"
ditto "${release_notes_file}" "${appcast_dir}/NeatWebApp-${version}.md"
if [[ -f appcast.xml ]]; then
  ditto appcast.xml "${appcast_dir}/appcast.xml"
fi

# 应用开了 SURequireSignedFeed，generate_appcast 会连清单本身和版本说明一起签名。
# 这之后不允许再手工改 appcast，改了签名就废。
"${sparkle_bin_dir}/generate_appcast" \
  --account "${SPARKLE_ACCOUNT}" \
  --download-url-prefix "${REPO_WEB}/releases/download/${tag}/" \
  --embed-release-notes \
  --link "${REPO_WEB}" \
  --versions "${build_number}" \
  --maximum-versions 10 \
  -o "${appcast_dir}/appcast.xml" \
  "${appcast_dir}" >/dev/null \
  || die "生成 Sparkle appcast 失败"
xmllint --noout "${appcast_dir}/appcast.xml" || die "Sparkle appcast 不是合法 XML"
grep -q "sparkle:edSignature=" "${appcast_dir}/appcast.xml" \
  || die "Sparkle appcast 缺少更新包的 EdDSA 签名"
"${sparkle_bin_dir}/sign_update" --account "${SPARKLE_ACCOUNT}" --verify "${appcast_dir}/appcast.xml" >/dev/null \
  || die "Sparkle appcast 完整性校验失败：拒绝发布未经签名或已被改写的更新清单"
# 版本说明必须内嵌（外链文件若被引用，必须与 appcast 一并入库并在终检核对长度）
if grep -q "releaseNotesLink" "${appcast_dir}/appcast.xml"; then
  die "appcast 引用了外链版本说明；请确认说明文件已随 appcast 一并提交，并核对 sparkle:length"
fi

# ---------- 5. 打 dmg ----------
log_step "打包 dmg"
stage_dir="${work_dir}/dmg"
mkdir -p "${stage_dir}"
ditto "${APP_PATH}" "${stage_dir}/NeatWebApp.app"
ln -s /Applications "${stage_dir}/Applications"
create_dmg "${stage_dir}" "NeatWebApp ${version}" "${dmg_path}" || die "打 dmg 失败"

log_step "公证 dmg 并装订票据"
notarize_and_wait "${dmg_path}"
xcrun stapler staple "${dmg_path}" || die "dmg 装订票据失败"

log_step "模拟首次打开做最终校验"
gatekeeper_result="$(spctl -a -vvv -t exec "${APP_PATH}" 2>&1 || true)"
grep -q "accepted" <<<"${gatekeeper_result}" \
  || die "Gatekeeper 校验未通过，别人机器上仍会被拦。原始输出：$(head -3 <<<"${gatekeeper_result}")"
xcrun stapler validate "${dmg_path}" >/dev/null || die "dmg 票据校验失败"
echo "✓ 已产出可双击直接打开的 dmg：${dmg_path}"

if [[ "${local_only}" == true ]]; then
  log_step "已按 --local-only 结束，未推送、未发布"
  exit 0
fi

# ---------- 6. 提交与打 tag ----------
log_step "提交改动并打 tag"
# 一并纳入工作区里其他 Agent 的改动，不挑拣
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: 发布 ${tag}"
else
  echo "工作区无改动，跳过提交"
fi
if git rev-parse "${tag}" >/dev/null 2>&1; then
  echo "tag ${tag} 已存在，沿用"
else
  git tag -a "${tag}" -m "${tag}"
fi
git push origin "${SOURCE_BRANCH}"
git push origin "${tag}"

# ---------- 7. GitHub Release ----------
# 禁止 create 时带附件：uploads.github.com 会 404，Release 可能留下空壳或根本不存在。
# 先建空 Release，再用 upload --clobber 传文件（可重复执行）。
log_step "发布 GitHub Release（先建空再传 dmg + 更新 zip）"
if ! gh release view "${tag}" --repo "${REPO}" >/dev/null 2>&1; then
  gh release create "${tag}" --repo "${REPO}" \
    --title "${tag}" --notes-file "${release_notes_file}" \
    || die "创建 GitHub Release 失败"
fi
gh release upload "${tag}" --repo "${REPO}" "${dmg_path}" --clobber \
  || die "上传 dmg 失败"
gh release upload "${tag}" --repo "${REPO}" "${update_zip_path}" --clobber \
  || die "上传 zip 失败"

# 两条一起传时，GitHub 可能回报成功但只留下其中一个。逐个传完必须回读确认。
python3 - "${REPO}" "${tag}" "NeatWebApp-${version}.dmg" "NeatWebApp-${version}.zip" <<'PY' \
  || die "GitHub Release 附件回读失败：dmg 或 zip 不在发行页上"
import json, subprocess, sys
repo, tag, *need = sys.argv[1:]
raw = subprocess.check_output(
    ["gh", "api", f"repos/{repo}/releases/tags/{tag}"],
    text=True,
)
names = {a["name"] for a in json.loads(raw).get("assets", []) if a.get("state") == "uploaded"}
missing = [n for n in need if n not in names]
if missing:
    raise SystemExit("missing " + ", ".join(missing))
PY

log_step "更新公开 appcast（随源码仓发布）"
ditto "${appcast_dir}/appcast.xml" appcast.xml
git add appcast.xml
if ! git diff --cached --quiet; then
  git commit -m "chore: 发布 ${tag} 更新清单" >/dev/null
  git push origin "${SOURCE_BRANCH}"
fi

# ---------- 8. Homebrew cask ----------
log_step "更新 Homebrew cask（防版本回退）"
dmg_sha="$(shasum -a 256 "${dmg_path}" | awk '{print $1}')"
tap_dir="${work_dir}/homebrew-tap"
git clone --depth 20 "git@github.com:${TAP_REPO}.git" "${tap_dir}"
cask_file="${tap_dir}/Casks/${CASK_NAME}.rb"
existing_version=""
if [[ -f "${cask_file}" ]]; then
  existing_version="$(python3 - "${cask_file}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'version\s+"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
fi
if [[ -n "${existing_version}" ]]; then
  python3 - "${existing_version}" "${version}" <<'PY' || die "拒绝回退 Homebrew 配方：线上 ${existing_version}，本次 ${version}"
import sys
def parse(v):
    parts = []
    for piece in v.split("."):
        n = ""
        for ch in piece:
            if ch.isdigit():
                n += ch
            else:
                break
        parts.append(int(n or "0"))
    return tuple(parts)
old, new = sys.argv[1], sys.argv[2]
raise SystemExit(0 if parse(new) >= parse(old) else 1)
PY
fi
python3 - "${cask_file}" "${version}" "${dmg_sha}" <<'PY'
import pathlib, re, sys
path, version, sha = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
text, n1 = re.subn(r'version\s+"[^"]+"', f'version "{version}"', text, count=1)
text, n2 = re.subn(r'sha256\s+"[^"]+"', f'sha256 "{sha}"', text, count=1)
if n1 != 1 or n2 != 1:
    raise SystemExit("Homebrew 配方缺少 version 或 sha256 行")
path.write_text(text, encoding="utf-8")
PY
git -C "${tap_dir}" add "Casks/${CASK_NAME}.rb"
if git -C "${tap_dir}" diff --cached --quiet; then
  echo "Homebrew 配方已是 ${version}，无需更新"
else
  git -C "${tap_dir}" commit -m "${CASK_NAME} ${version}"
  git -C "${tap_dir}" push origin HEAD
fi

# ---------- 9. 匿名终检 ----------
log_step "匿名下载与更新清单终检"
# raw.githubusercontent.com/main 常有 CDN 延迟，推送后立刻读可能仍是旧清单；重试并在末次回退到 GitHub Contents API。
appcast_ok=0
for attempt in 1 2 3 4 5 6 7 8; do
  if curl -fsSL "${FEED_URL}" -o "${work_dir}/published-appcast.xml" \
    && xmllint --noout "${work_dir}/published-appcast.xml" \
    && grep -q "<sparkle:version>${build_number}</sparkle:version>" "${work_dir}/published-appcast.xml"; then
    appcast_ok=1
    break
  fi
  echo "公开 appcast 尚未见到构建号 ${build_number}（第 ${attempt} 次，多半是 CDN 未刷新）"
  sleep 15
done
if [[ "${appcast_ok}" -ne 1 ]]; then
  curl -fsSL -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/${REPO}/contents/appcast.xml?ref=main" \
    -o "${work_dir}/published-appcast.xml" \
    || die "公开 appcast 无法匿名下载（CDN 与 API 均失败）"
  xmllint --noout "${work_dir}/published-appcast.xml" || die "线上 appcast 不是合法 XML"
  grep -q "<sparkle:version>${build_number}</sparkle:version>" "${work_dir}/published-appcast.xml" \
    || die "线上 appcast 没有当前内部构建号 ${build_number}"
  echo "CDN 仍滞后，已用 GitHub Contents API 核对 appcast 构建号 ${build_number}"
fi
"${sparkle_bin_dir}/sign_update" --account "${SPARKLE_ACCOUNT}" --verify "${work_dir}/published-appcast.xml" >/dev/null \
  || die "线上 appcast 完整性校验失败：公开更新清单未签名或传输后被改写"
curl -fsSL --range 0-0 "${REPO_WEB}/releases/download/${tag}/NeatWebApp-${version}.zip" -o /dev/null \
  || die "Sparkle 更新包无法匿名下载"
curl -fsSL --range 0-0 "${REPO_WEB}/releases/download/${tag}/NeatWebApp-${version}.dmg" -o /dev/null \
  || die "首次安装 dmg 无法匿名下载"
curl -fsSL "https://raw.githubusercontent.com/${TAP_REPO}/HEAD/Casks/${CASK_NAME}.rb" \
  | grep -q "version \"${version}\"" \
  || die "Homebrew 配方未指向 ${version}"

log_step "发布完成"
cat <<EOF
版本：${tag}（内部构建号 ${build_number}）
首次安装：${REPO_WEB}/releases/latest
一键安装：brew tap x0c/tap && brew install --cask ${CASK_NAME}
自动更新：${FEED_URL}
状态：安装包可匿名下载，已完成 Sparkle 签名、Developer ID 签名、苹果公证与票据装订
EOF
