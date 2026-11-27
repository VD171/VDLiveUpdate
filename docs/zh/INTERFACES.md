> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · 中文

---

# VDLU - 接口契约（组件之间的接缝）

**收敛法则：** 每个组件都遵从本文件。来自 4 个 agent 的各个部分必须**相互契合** -
下面的 CLI 签名、文件名和 JSON 键是**不可变的**（更改意味着先在此处对齐）。

从各仓库继承的原则：设备上使用**纯 POSIX sh**（无 bashism；以 toybox/busybox +
toybox 的 `sha256sum`/`gzip`/`base64` + 抓取的 `curl` + 内嵌的 `ed25519-mini` 运行 - 精简、无二进制
捆绑包），**零多余注释**，**始终 release**，**失败时严谨**（可恢复的事务，没有任何东西被虚假地“完成”，
没有任何东西丢失），**不放松任何东西**。

---

## 1. 状态布局（Tier-2，在模块目录之外）

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
journal 中的 `cancelled:true` = engine 因取消而停止（一个非终止、可恢复的状态；`error`
保持 null）。

在模块中 vendor 的 engine：`$MODULE_DIR/vdlu/update.sh`（+ `vdlu-verify`）。`$MODULE_DIR =
/data/adb/modules/<module>`。engine 通过 env 接收：`VDLU_DIR`、`MODULE_DIR`、`MODID`。

## 2. Engine CLI（ENGINE 组件）

`sh update.sh <cmd>` - rc 0 = ok，!=0 = 错误（stderr 含原因）：

| cmd | 作用 |
|---|---|
| `check` | DIFF：下载清单，比较；打印一行 JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`；不改变任何东西。设备领先于 feed（降级被阻止，hardened）= 一个良性状态：`{"update":false,"ahead":true,"from":N,"to":M}` + rc0（永不“check failed”）。do_diff rc：2 fetch/parse，3 verify/meta，4 ahead |
| `run` | 完整周期：DIFF→FETCH→APPLY→COMMIT；遵从 `cancel`；将进度写入 `journal.json`；应用 LIVE，暂存 REBOOT-hard |
| `resume` | 从当前阶段恢复 `journal.json` 事务（幂等） |
| `boot` | pre-zygote 模式：`resume` + 执行 `staged/*.vdlu-new` 的交换（应用 `.so`），关闭 `PENDING_REBOOT`→`DONE` |
| `status` | 打印 `journal.json`（或 `{"state":"idle"}`） |
| `cancel` | 创建 `$VDLU_DIR/cancel`（进行中的 `run` 在下一个安全点停止） |

Blob/清单来源：config 中的 `source`。`<source>` + `/manifest.json`、`/blobs/<sha>`、`/blobs/<sha>.gz`。
`source` 以 `https://` 开头（静态 curl 抓取，TLS）或 `file://`（本地暂存）。

## 3. manifest.json（由 PRODUCER 生成，由 ENGINE 消费）

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = 完整的目标树。`class`：`live`（webroot/bin/lib/confs/scripts-on-demand/module.prop）·
  `soft`（service.sh/post-fs-data.sh/boot-completed.sh）· `reboot`（`zygisk/**/*.so`、`system/**`、`*.rule`）。
  按路径默认；绝不将 `reboot`→`live` 降级。
- `enc`：`gz`（gzip `-9 -n`，确定性；设备上用 toybox gunzip）仅当压缩良好 **且**
  大小可观时；`sha256` 始终是原始内容的。
- `sig`：对不含 `sig` 字段的规范清单的签名（verify 的 §4）。
- **信任锚排除（engine 侧，VDLU#2）：** engine 会从计划中丢弃 `vdlu/` 下的任何 `files[]`/`delete[]` path
  （它自己的 `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config） - 从不抓取、应用或删除 - 即使一个
  已签名的 feed 携带它们。设备上的信任锚只通过一次完整的已签名 re-flash 才改变，而非通过网络；`vdlu-pack`
  也在 producer 侧排除 `vdlu/`，因此这是针对泄露签名密钥的第二道、engine 侧的防护。

## 4. journal.json（ENGINE 写，WEBUI 读 - 进度契约）

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

状态机（固定顺序）：`PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`。
`DONE` 仅当对所有内容的重新哈希匹配时。暂存的 REBOOT-hard ⇒ `PENDING_REBOOT`（非 `DONE`）。从
`fetch` 阶段退出：`ERROR`（硬失败）或 `DEFERRED`（net_policy 阻止了下载 - 良性/可恢复，
非错误）。

## 5. config（key=value，每行一个；在 WEBUI 中可编辑）

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**启动重试（离线）- 耐心、省电：** 仅在 `boot` 时（从不在 check/auto-open 时）。如果清单
抓取因网络而失败（`fetch_offline` 按 fetcher 的退出码分类），它会等待并重试，直到成功
或耗尽 `boot_retry_minutes` 的 AWAKE 时间。一种**不持有任何东西且不耗电**的设计：
- **零 wakelock：** 各次尝试之间是 `sleep`，在 deep-sleep 中冻结 → 设备正常睡眠
  （~零耗电）；重试暂停，待设备已经唤醒后恢复。
- **零持有锁：** 在各次尝试之间 `acquire_lock_try`+release（等待期间不持有锁）→
  `run`/手动 check 从不阻塞；如果期间一次手动 run 暂存了 TARGET，boot 会推迟。
- **不无故唤醒射频：** 一次 `net_allowed` 探测（通过 `net_type`/`ip route get`，一次内核 route
  查找，尊重 Android 的策略路由；无数据包）控制每次尝试 - 它仅在网络出现后才花费一次抓取。
- 从不重试确定性失败（manifest/sig/downgrade）。抓取上有 `--connect-timeout 15`（不会
  卡在 captive portal 上）。`service.sh` 将其放到后台（boot 从不挂起）。
- ⛔ **硬性：开启 `boot_retry_minutes>0` 需要耐心 engine**（即带有
  `net_allowed`+`acquire_lock_try` 的那个，规范 `da7115f4`+）。之前的 boot-retry（整个窗口
  持有锁 + 离线盲 curl 重试）**耗电/唤醒射频** - 在旧 engine 中开启重试
  是一个 footgun。开启它时，vendor 当前的 engine。

**`net_policy`（any|wifi|mobile）：** 按网络类型控制**下载**。`net_type()` 分类
`ip route get` 的出口（蜂窝 iface `rmnet/ccmni/v4-*/clat` = mobile；其余一切 = wifi；内核查找，无
数据包）。`net_allowed()` 与 `net_policy` 比较并控制 `do_fetch`（blob）+ 耐心 boot-retry 探测。
**清单检查保持免费**（极小 → UI 在任何网络上报告有更新）；只有下载
等待被允许的网络。在不被允许的网络上下载 = journal 中的 **`DEFERRED`** 状态
（非 ERROR；一个温和的蓝色 INFO toast“等待 X 网络”；plan/target 持久化，它在正确网络上的下一次
check/boot 时恢复）。`net_policy` **取代** `allow_metered`（后者从未被消费）。
Engine `97baf887`+（`file://` 从不被控制）。

## 6. 签名（PRODUCER 在 PC 上通过 openssl 签名；ENGINE 在设备上通过 ed25519-mini 验证）

- 规范化：不含 `sig` 的清单，键已排序，紧凑 JSON（无多余空格），UTF-8。
  被签名/验证的 = 该规范形式的 `sha256` hex（提供跨工具确定性）。
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → 就地将 `key_id` + `sig`（规范 sha256 的 ed25519 签名的 base64）注入清单。
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → 如果 `sig` 匹配 keyring 中的 `<key_id>.pub` 公钥则 rc 0
  （SLIM：公钥 **RAW 32 字节**）。内部无 openssl：toybox `sha256sum`/`base64 -d` + 内嵌的
  `ed25519-mini` 二进制（CLI `ed25519-mini <pub32> <msg> <sig64>`，rc 0=有效/1=无效/2=usage）。
  rc!=0 = 拒绝。**`profile=hardened` ⇒ verify 强制；失败 = abort。**
  `profile=trusted` ⇒ verify 是尽力而为（来源已经通过 SSH 受信），但每个 blob 的哈希始终被检查。
- **module-update 密钥 allowlist（fail-closed，在 pubkey 选取之前）：** 清单的 `key_id` 必须是已接受的 MODULE-UPDATE 密钥，才会选取 `<key_id>.pub` - config 的 `key_id`（§5）就是这个 allowlist。keyring 也可能携带一个较低信任的密钥（例如一个 fingerprint-feed 密钥，自动化，不同账户）；没有 allowlist，由该密钥签名的清单一旦泄露便会通过验证并应用一次完整的 flashless root 更新。`verify_manifest` 在两个 profiles 中都强制执行，并通过 env `VDLU_KEYID_ALLOW` 将解析出的集合传给 `vdlu-verify`（使独立 verifier 保持一致）。未设置时默认安全（单密钥 keyring：仅该密钥；多密钥 keyring：在 `key_id` 被固定前拒绝）。fingerprint-feed 信任根是一条独立路径，有自己固定的密钥，不受影响。
- `producer/vdlu-keygen <id> <out>` → 生成 `<id>.pem`（priv）+ `<id>.pub`（PEM，用于 PC 上的工具）+
  `<id>.pub.raw`（**RAW 32B** = 设备上精简 keyring 的 `<id>.pub`）。openssl `genpkey -algorithm ed25519`。

## 7. Blob - 校验（ENGINE）

下载 `<source>/blobs/<sha>`（若 `enc=gz` 则为 `.gz`），写入 `.part`，若 `gz` 则解压（`gunzip`），
检查 `sha256sum` == 清单的 `sha256`；匹配 → 原子 `mv` 到 `$VDLU_DIR/blobs/<sha>`。同一 blob 上 3 次失败
= 中止该阶段（不应用任何东西）。`$VDLU_DIR/blobs/<sha>` 中已有且哈希 ok 的 blob =
跳过下载。

## 8. 按 class 的 APPLY（ENGINE）

- `live`/`soft`：备份 `rollback/<v>/<path>` → 从 blob 写 `$MODULE_DIR/<path>.vdlu-tmp` → `chmod mode` →
  原子 `rename` 覆盖目标。已在目标哈希 = 跳过。（在 Zygisk 变体中，写入进入
  挂载目录 = 逐文件合并，绝不对目录 `rm -rf`。）
- `reboot`：物化到 `$VDLU_DIR/staged/<path>.vdlu-new`（不触碰 live 那个）。交换在 `boot` 时。
- `delete[]`：备份 → 移除。

## 9. WEBUI ↔ ENGINE（WEBUI 组件）

- 触发：`ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")`（后台）。
- 进度：轻量轮询 `ksu.exec("cat $VDLU_DIR/journal.json")` 每约 1s；渲染 `{phase,state,total,done,current,bytes}`。
- 存活：journal 缺失 8 个 tick ⇒“无响应”。journal 冻结（相同值）20 个 tick ⇒ 检查 `lock.d`：存活 = 继续（1 个 blob 的缓慢抓取），死亡 = 错误 + Resume。没有这个，一个在抓取中途死掉的 run 会把 toast 冻结在“updating”。
- 取消：`ksu.exec("touch $VDLU_DIR/cancel")`。
- Config：在“Updates”标签页中读/写 `$VDLU_DIR/config`（key=value）。
- Toast：进度条 + `phase done/total · current`；完成时若 `reboot_pending` ⇒ 一个持久横幅“reboot to activate the .so”。
- Auto-open（`auto_on_webui_open=1`）：先做一次静默 `check()`（无进度 toast）；仅当 `update && fetch>0` 时才触发 `run`+持久 toast。已是最新/领先/无新内容 = 面板中的内联结果，零残留 toast。像手动按钮一样不打扰（只有当存在真实下载时 toast 才出现）。curl bootstrap 是一次性的。

## 10. 集成到 demo（INTEGRATION 组件）- 代码片段，不要编辑 live 文件

在 `integration/demo/` 中生成片段 + 一个 `INTEGRATION.md`，说明每个片段放在哪里（不应用）：
- `post-fs-data`/`service.sh` 中的 `auto_on_reboot` hook（pre-zygote → `update.sh boot`）以及 `auto_on_webui_open`。
- `config` 默认值 + 内嵌 keyring + vendor（`modules/<mod>/vdlu/`）。
- PARTIAL 变体（合并到挂载目录）。

## 11. 抓取的工具链 + baseline（SLIM，方案 B）

**模块中的布局（zip）：** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`。**没有** `bin/`（openssl/curl/zstd）。`customize.sh` 可将
`verify/` 精简至设备的 ABI（`vdlu-verify` 在 `<dir>/ed25519-mini` 或 `<dir>/verify/<abi>/ed25519-mini` 处找到 mini）。

**ed25519-mini**（内嵌二进制，仅 verify）：`ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=有效、
1=无效、2=usage/IO。msg = 确切的被签名字节（不重新哈希）。TweetNaCl PD，按 ABI 静态，PROVENANCE。

**tools-feed**（仅 public/https profile）：在 `<tools_source>` 处提供（默认派生：将 `source` 的最后一段
替换为 `vdlu-tools`，例如 `https://<user>.github.io/<repo>/vdlu-tools`）。包含：
- `tools-manifest.json` - 对 `<abi>/curl` 树的一个已签名 `vdlu-pack` 清单，固定每个 curl 的 `sha256`
  （相同的 `release-2026` 密钥）。
- `<abi>/curl` - 原始**静态** curl（自包含，~1MB；curl 8.11.1 + mbedTLS）。🪤 mbedTLS 不
  自带 CA bundle：`fetch_url` 传递 `--capath`（自动检测 Android 信任库：`/system/etc/security/cacerts`
  → APEX conscrypt；`ca_path` 覆盖）。无 capath = 错误 60。完整性是 ed25519；证书检查是纵深防御。

**install-tool**（ENGINE）：`update.sh install-tool <abi>` 读取 `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
（WEBUI 通过 `fetch()` 下载它并写到那里），**验证 tools-manifest 签名（ed25519-mini，
任何 profile 中都强制）** + curl 的哈希 == 清单，然后才将其安装到 `$VDLU_DIR/tools/<abi>/curl`（0755）。
curl 以 root 运行 → exec 前的 sig+hash 关闭了 RCE。在 Tier-2 中持久化：从不重新下载（卸载时除外）。

**fetch-bootstrap**（WEBUI，`ensureToolchain()`）：在 check/run/resume 之前运行。`file://` = no-op；curl 已经
可用（Tier-2，或来自**自捆绑**模块的 `module/bin/<abi>/curl`，或 system）= no-op
（VDLU 复用现有 curl）；只有 `https` **且完全没有 curl** 时才通过 webview 下载 curl + tools-manifest，将
它们写入 `.work`（通过 `ksu.exec` 分块 base64），调用 `install-tool`。信任 = 设备上的检查，而非下载。

> 🪤 **Slim（fetch-bootstrap）≠ 强制。** 其 `bin/` 为其**自身功能**而存在的模块（例如它捆绑
> restic/rclone/age/tar/curl...）**不会**精简到 ~2MB，也不下载 curl - VDLU 采用 slim engine
> （gz、mini、baseline、修复）并**复用**内嵌的工具链。只有没有自身工具链的模块
> 才会增加 ~2MB。

**baseline.json**（from:0 修复）：release 将发布版本的已签名 `manifest.json` 复制到
`vdlu/baseline.json`；在全新安装时 engine 从它播种 `current.json`（`init_paths`，仅当缺失时）→ 设备
诞生即“最新”，不自动更新自身且不重新抓取。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
