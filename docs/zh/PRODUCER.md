> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · 中文

---

# VDLU producer + 签名层

为一个模块构建内容寻址的分发（清单 + blob）并对其签名。
遵从 [`INTERFACES.md`](INTERFACES.md) §3/§6/§7。

| 工具 | 运行于 | 语言 | 任务 |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | 遍历最终模块树 -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 密钥对（`<id>.pem` priv、`<id>.pub` PEM、用于精简 keyring 的 `<id>.pub.raw` RAW 32B） |
| `producer/vdlu-sign` | PC | sh + openssl | 就地将 `key_id` + `sig` 注入清单 |
| `engine/vdlu-verify` | **设备** | sh + ed25519-mini | 通过内嵌的 ed25519-mini 验证 `sig`；keyring = RAW 32B 公钥（设备上无 openssl） |

## 流水线

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` 是内容寻址且去重的：`<sha256>` 已存在的 blob 不会被
重写，因此发布是增量的，未改变 / 已回退的内容从不被重新 push。

### `enc` 决策（vdlu-pack）

`sha256` **始终**是原始（未压缩）内容的；`enc` 仅命名 blob 如何存储。

- `gz`：当 `size >= 4096` **且** gzip（`-9 -n`，确定性）至少节省 10%（`comp <= raw*0.90`）时。
- `raw`：否则（HTTP gzip 已覆盖的小文本，或已不可压缩的数据）。
- 构建主机上缺少 gzip -> 一切 `raw`（从不失败）。

一个 blob 只存储一次，一种格式：`blobs/<sha256>`（raw）或 `blobs/<sha256>.gz`（gz）。设备
用 toybox `gunzip`（始终存在）解压，因此不捆绑 zstd。

### `class` 决策（vdlu-pack）- reboot 分类法

从路径派生（INTERFACES §3，doc §4）。仅为默认值；路径规则从不将 `reboot`->`live` 降级。

| class | 匹配于 | 应用 |
|---|---|---|
| `reboot` | `system/**`、`zygisk/**/*.so`、`*.rule` | 暂存 `.vdlu-new`，启动时交换 |
| `soft` | 根 `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | 写 live，下次启动运行 |
| `live` | 其余一切（webroot、bin、lib、confs、module.prop、...） | 写 live，原子 |

符号链接**不被跟随**（从不泄露树外的内容，例如一个指向
`/etc/shadow` 的链接）并带一个警告被跳过，因为清单 schema 没有 symlink 类型。
非常规文件（目录、fifo、设备）被跳过。`built` 尊重 `SOURCE_DATE_EPOCH` 以获得
可复现的清单。

### Baseline（安装种子）- 未签名、无密钥

`baseline.json`（在模块 zip 中以 `vdlu/baseline.json` 发布）在全新安装时播种 `current.json`，
使设备诞生即“最新”（无 from:0，无重新抓取）。engine 将其视为一个**本地受信种子**
（它随刷入的 zip 到达，而刷入 zip 正是安装信任边界）并**不验证其签名** -
只有从 feed **抓取**的清单才经过 `vdlu-verify`。因此 baseline **不需要密钥**：它
只是 `vdlu-pack` 对发布树的输出（未签名；`sig`/`key_id` 保持为空）。因此 CI 可以
**无密钥**地生成它，让签名密钥 100% 处于 CI 之外 - 只有已发布的 FEED 被签名（由操作员，
在本地）。`vdlu-pack` 将 `baseline.json` 从它自己的清单中排除（防自引用）。缺失时非致命：
设备只是在首次更新时从 from:0 开始，绝不会损坏。

## 规范化（收敛点）

`vdlu-sign` 和 `engine/vdlu-verify` 必须从一个清单在两个
不同的运行时（PC openssl 对 device toybox）上派生出**相同的字节**。该规则刻意是一个
字节变换，而非一次 JSON 重新序列化，因此它在设备上不需要 JSON 库：

1. `vdlu-pack` 以**紧凑、键已排序、UTF-8** 写入 `manifest.json`
   （`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`），始终包含
   `key_id` 和 `sig` 字段（签名前为空字符串占位符）。这是规范的
   存储形式。
2. **规范形式 = 移除了 `"sig"` 字段的那段文本。** 因为键已排序，`sig`
   总是以 `,"sig":"<value>",` 的形式出现，被 `"schema"`（之前）和 `"version"`（之后）括住，
   两者始终存在。移除它会留下格式良好的 `...,"schema":N,"version":...`。
   JSON 将字符串值内的每个 `"` 转义为 `\"`，因此结构 token `"sig":"` 即使面对
   一个字面包含 `"sig":"` 的文件名也是无歧义的（已测试）。
3. 被签名/验证的消息是规范形式的 **sha256 hex**（64 个 ASCII 字符，无换行）。
   在该 hex 上的 ed25519（`openssl pkeyutl -sign/-verify -rawin`）。

POSIX sh 中的移除（两个工具中相同的函数，无 `sed`/`jq`）：

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` 是规范形式的一部分（只有 `sig` 被剥除）；`vdlu-sign` 在哈希**之前**设置 `key_id`。
值占位符为空（`"sig":""`，签名时）或已填充（验证时）产生
相同的规范字节，因此 sign 和 verify 按构造达成一致。

Python 将它复现为 `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` 然后 sha256 - 仅
用于交叉校验；权威的生产者是两个 sh 工具。

## 签名（ed25519）

- `vdlu-keygen`（PC）：`openssl genpkey -algorithm ed25519`（priv `0600`）+ `openssl pkey -pubout`（pub **PEM**，
  用于签名/openssl）+ `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw`（RAW 32B）**（ed25519
  SPKI DER 是一个 12 字节前缀 + 32 字节密钥，因此 `tail -c 32` 就是密钥）。它两者都发出。
- `vdlu-sign`（PC）：在规范 sha256 hex 上 `openssl pkeyutl -sign -rawin`；签名以 base64 存储。
- `vdlu-verify`（**设备，slim**）：`ed25519-mini <pubkey32> <msg> <sig64>` - 将 keyring 读作 **RAW 32B**
  公钥，设备上无 openssl。`key_id` 经过路径净化（无 `/`、`.`、`..`、`"`）。🚨 keyring 发布
  **`.pub.raw`（32B）**，绝不是 `.pub` PEM（113B）：PEM 仅在 PC 侧，且 `ed25519-mini` 无法读取它。

信任模型（INTERFACES §6，doc §11/§13）：`profile=hardened`（public）使 verify 强制 - 一个
失败或缺失的签名会中止更新。`profile=trusted`（private，SSH-staged 来源）将
verify 视为尽力而为，但每个 blob 的 sha256 无论如何都被检查。

## Keyring + 轮换

keyring 是一个 `<key_id>.pub` 文件的目录，每个文件是 **RAW 32B** 的 ed25519 公钥（来自 `keygen` 的
`.pub.raw`），**不是** PEM - `ed25519-mini` 读取原始 32 字节。发布当前**以及**上一个原始公钥
（doc §13），使一个已轮换的密钥不会使较旧的安装变砖。`vdlu-sign` 用新 `key_id`，设备
选取 `<keyring>/<key_id>.pub`（原始），这就是整个轮换机制 - 无需更改 engine。keyring 跨
release 是**稳定的**（只有密钥轮换才改变它）：重新 vendor 必须**验证而非复制**它，且绝不
用 PC 侧的 `.pub` PEM 覆盖它。

`vdlu-pack` **将 keyring 和 `verify/` 二进制从 feed 中排除**（信任根仅在刷入中，绝不通过网络传输），连同 `baseline.json`、安装器脚手架（`META-INF/`、`customize.sh`）、`.vd/` 刷入闸、由 CI 填充的 `update.json`/`update-mmrl.json`，以及每文件的 `.sha256` 伴随文件。只有模块自身的内容可经 feed 更新，因此清单绝不能重写设备上的信任锚。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
