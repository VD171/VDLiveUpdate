> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · 中文

---

# 安全策略与信任模型

VDLiveUpdate（VDLU）对一个运行中的模块应用**免刷写 root 更新**：它写入 `/data/adb/modules/<mod>`
并在 boot 时交换一个 Zygisk `.so`。被抓取清单的每个字段（`path`、`sha256`、`delete[]`、`mode`、...）
都是**敌意输入** - 一个被投毒的 feed 或一个 MITM 将其送达。本页是信任模型与负责任披露策略。完整的
seam 契约见 [`INTERFACES.md`](INTERFACES.md)，engine/producer 内部见 [`ENGINE.md`](ENGINE.md) 与
[`PRODUCER.md`](PRODUCER.md)；wiki 页面 **Security-and-Trust-Model** 为 repo 之外的读者承载同一模型。

## 受支持的版本

安全修复落入最新的 `ENGINE_VERSION`；一个已签名的清单通过 `engine_min` 声明它所需的最低 engine，
而设备上的 engine 会拒绝一个要求超出其实现的清单。较旧的已 vendor engine 预期应**重新 vendor**
以获取修复，而非就地 back-patch。

| ENGINE_VERSION | 状态 |
|---|---|
| 7（当前） | 受支持 - 绝不回退领先于 feed 的模块（实时安装的 `versionCode` 作为 "from" 版本的下限），启动时自愈陈旧的 downgrade 计划 |
| 6 | 已被取代 - 启动时自愈陈旧的 `target <= 0` journal（被移除的 stub 残留的 baseline 0 不再驱动任何 UI 或启动动作） |
| 5 | 已被取代 - engine 侧信任锚排除（即使一个 feed 携带 `vdlu/` 目录也会被忽略）、每文件 128 MiB / 清单 2 MiB 上限 |
| 4 | 已被取代 - `key_id` allowlist、dot-segment/trailing-slash path 拒绝、size cap、check-time lock |
| <= 3 | 不受支持 - 重新 vendor 当前 engine |

对 engine 验证或 apply 逻辑的任何更改都会提升 `ENGINE_VERSION`。

## 报告漏洞

私下报告。对于安全 bug，**不要**开一个公开的 issue、PR 或论坛帖。请使用项目联系方式
（见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)）：

- Telegram：**@VD_Priv8**（https://t.me/VD_Priv8）
- 频道：**@Priv8_VD**（https://t.me/Priv8_VD）
- 邮箱：**vd.priv8@pm.me**

请附上 engine 版本、使用中的 `profile`，以及一个能复现问题的清单或 feed。修复以一个带有 `CHANGELOG.md`
条目的新 `ENGINE_VERSION` 发布；在报告线程上协调披露时机。

## 信任模型

- **分离式 ed25519 签名。** producer 在 PC 上对规范清单签名（openssl）；设备用内嵌的 `ed25519-mini`
  验证 - **设备上无 openssl**。被签名的消息是去掉其 `sig` 字段后的清单的 sha256 hex（键已排序、紧凑、
  UTF-8），因此 sign 和 verify 在两个运行时上派生相同的字节，设备上无需 JSON 库。
- **Keyring = RAW 32 字节公钥**，仅限 flash。设备 keyring 以原始 32 字节密钥（绝不是 PEM）发布
  `<key_id>.pub`；`vdlu-pack` 将 keyring 和 `verify/` 二进制从 feed 中**排除**，因此一个清单绝不能通过
  网络重写设备上的信任锚。
- **engine 侧信任锚排除（VDLU#2）。** 独立于上面 producer 侧的排除，设备上的 engine 会**忽略**一个被抓取
  计划中的每一个 `vdlu/` path（`update.sh`、`vdlu-verify`、`verify/*`、`keyring/*`、config） - 它从不抓取、
  应用或删除它们，即使一个 feed 携带它们。一个已发布的 feed 会发送整个模块树，包含 `vdlu/`，因此 engine 会
  静默丢弃这些 path 而非拒绝清单：模块仍会更新，而信任锚只通过一次完整的已签名 re-flash 才改变。一个泄露的
  签名密钥再也无法通过网络交换 verifier 或签名密钥并持久化 root。
- **module-update `key_id` allowlist（fail-closed，在 pubkey 选取之前）。** 一个 keyring 可能合法地携带
  多于一个密钥（例如在 release 密钥旁边有一个较低信任的 fingerprint-feed 密钥）。在 `<key_id>.pub`
  被选取之前，`verify_manifest` 在**两个** profiles 中拒绝任何 `key_id` 不在已配置 allowlist 中的清单，
  并通过 `VDLU_KEYID_ALLOW` 将解析出的集合镜像到 `vdlu-verify`。这封堵了一个旁路：泄露的较低信任密钥
  否则可能签署一个完整的 flashless root 更新。`key_id` 未设置时默认安全：**单密钥** keyring 自动固定到
  那一个密钥；**多密钥** keyring 在 `key_id` 被固定之前被拒绝（用逗号分隔以便轮换）。
- **fingerprint-feed 信任根是一个独立的、固定的 path**，有它自己的密钥；它绝不可通过上述 module-update
  路径到达。
- **Baseline 是一个本地受信种子。** `baseline.json` 随刷入的 zip 到达 - 即安装信任边界 - 所以它未签名、
  无密钥，并且**不**经过 `vdlu-verify`；只有从 feed **抓取**的清单才被验证。这让签名密钥留在 CI 之外。

## fail-closed 保证

- **`validate_plan` 在任何 fetch 或 apply 之前运行。** 在 `do_diff` 中，fail-closed 地，若任何 `path` 是
  绝对路径、含有一个 `..` 或 `.` segment、以 `/` 结尾、或持有一个控制字符；若任何 `sha256` 不是
  `^[0-9a-f]{64}$`；或若任何 `mode`/`class`/`enc` 无效，它都会拒绝**整个**清单。没有敌意字段到达一个
  shell，且 `cmd_check` 不带任何 `system()` 插值。
- **Path 包含。** 每一次写入和删除都通过 `contained()` 被限制在 `MODULE_DIR` 内 - apply、delete，以及
  reboot 的 `stage_file` 都通过同一个 guard。树中的符号链接被 producer 跳过（绝不泄露其外部的内容）。
- **两个 profiles，通过反转 fail-closed。** `trusted`（私有、SSH-staged 来源）是对 best-effort verify 的
  **唯一** opt-in；**任何**其他值 - 包括一个 typo、一个 trailing 空格/CR，或一个不同的大小写 - 都被当作
  `hardened` 处理，在其中一个有效签名是**强制的**，一次失败即 abort。每个 blob 的 `sha256` 在两个
  profiles 中都被检查。
- **任何 tool exec 之前先签名 + 哈希。** 被抓取的静态 `curl` 以 root 运行，所以 `install-tool` 在它被
  安装并执行**之前**验证 tools-manifest 签名（ed25519-mini，在**任何** profile 中强制）和 curl 的哈希 -
  exec 之前的 sig+hash 封堵了 RCE。
- **可恢复、pin-安全的事务。** 在途清单被固定在 `target.json`；一次崩溃、网络丢失或 reboot 会从 journal
  恢复，而不重新决定计划。downgrade 被阻止（单调 `version`），已签名的 `module` 字段必须等于 `MODID`，
  且 `delete[]` 仅在 `finalize_done` 时运行（一个 `PENDING_REBOOT` 不删除任何东西）。没有一样东西会在未
  经完整 re-hash 的情况下“完成”；没有一样东西会在没有先备份 `rollback/<v>/` 的情况下被覆盖。

## 加固（纵深防御）

- **Size cap。** 清单、tools-manifest，以及无 curl 的 `wget`/`head -c` 下载路径在被读取之前都受界限约束
  （anti-OOM / anti-flood）。一个 blob 在 3 次尝试后在其阶段失败。上限为**每文件 128 MiB**
  （`MAX_FILE_BYTES`）和**清单 2 MiB**（`MAX_MANIFEST_BYTES`），在 `update.sh` 中强制执行并在 `vdlu-verify`
  中镜像。
- **Check-time lock。** `check` 在重建其 work dir 之前取得 mkdir-lock，因此一个并发运行无法与它竞争。
- **Staging 包含。** `stage_file` 具有与 live apply 原语相同的 `contained()` guard，因此一个已暂存的
  reboot-hard path 也无法逃出 `MODULE_DIR`。
- **TLS 是纵深防御，而非信任根。** 静态 curl 使用 mbedTLS 配合 Android 信任存储（`--capath`、`ca_path`
  覆盖）；完整性保证是 ed25519 签名，证书检查是第二层。

## 另见

- [`INTERFACES.md`](INTERFACES.md) - 不可变的 seam 契约（§5 config、§6 signature、§11 toolchain）。
- [`ENGINE.md`](ENGINE.md) - 设备侧 engine 及其状态机。
- [`PRODUCER.md`](PRODUCER.md) - 打包、签名、规范化，以及密钥轮换。
- Wiki：**Security-and-Trust-Model**。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
