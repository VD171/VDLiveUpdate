# Feed Format

**Feed** 是 VDLU 通过网络提供、设备据以更新的东西。它是一个纯静态目录，任何东西都能提供（GitHub Pages、一个 rsync 目标、一个 `file://` 路径）：

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

模块本身还会在 `.zip` 内部交付一个额外文件 `baseline.json`（不从 feed 提供）。构建这一切的 producer 在 [[Producer]] 中描述；本页是传输时的契约。

---

## manifest.json

清单是对一个版本的完整描述：目标目录树中的每个文件、要删除什么，以及对整体的签名。

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### 字段

| 字段 | 含义 |
|---|---|
| `schema` | 清单本身的格式版本（当前为 `1`）。 |
| `module` | 模块 id。如果它与设备自己的模块 id 不匹配，设备就拒绝该清单，因此一个为不同模块有效签名的 feed 无法被用来替换它。 |
| `version` | 整数版本。引擎只向前更新；一个比设备更旧的 feed 是一个良性的 "ahead" 状态，不是错误。 |
| `version_name` | 人类可读的版本字符串（例如 `v106`）。 |
| `built` | ISO 8601 构建时间戳。为可复现性尊重 `SOURCE_DATE_EPOCH`。 |
| `engine_min` | 应用此清单所需的最低引擎版本。 |
| `channel` | 发布通道（例如 `stable`）。 |
| `key_id` | 设备 keyring 中的哪个密钥签署了此清单。为验证选择公钥。 |
| `files[]` | **完整**的目标目录树（不是 diff）。每个条目：`path`、`sha256`、`size`、`mode`、`enc`（`raw`/`gz`）、`class`（`live`/`soft`/`reboot`）。 |
| `delete[]` | 存在于上一版本、如今已不在的路径，供设备移除。 |
| `sig` | ed25519 签名，base64。见下面的规范化。 |

`files[]` 描述**整个**目录树，而不是一个差量。设备自己通过把清单与它已经拥有的内容比较来计算差量，并只拉取它缺失 `sha256` 的那些 blob。`sha256` 始终是原始（未压缩）内容的；`enc` 只说明该 blob 在 `blobs/` 中是如何存储的。`class` 的含义以及设备对每个值的处理在 [[Reboot Handling]] 中有说明。

---

## 规范化（被签名的字节）

这是该格式中唯一最重要的不变式。PC 上的签名器和设备上的校验器运行在完全不同的运行时上（PC 上是 openssl，设备上是 toybox + 一个微小的内嵌校验器，而且设备上**根本没有 JSON 库**）。它们仍必须推导出完全相同的字节来签名和验证。因此该规则是一个刻意的**字节变换**，而不是一次 JSON 的重新序列化。

**第 1 步：一个固定的存储形式。**`vdlu-pack` 把 `manifest.json` 写得紧凑，键已排序，UTF-8，始终包含 `key_id` 和 `sig`（在签名前为空字符串）：

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**第 2 步：只剥掉 `sig`。**规范化形式就是那段确切文本，**仅移除 `"sig"` 字段**。因为键已排序，`sig` 总是以 `,"sig":"<value>",` 的形式出现，前面被 `"schema"`、后面被 `"version"` 括住（两者都始终存在），因此移除它会留下格式良好的文本。JSON 把一个字符串值内部的每个 `"` 转义为 `\"`，因此结构 token `"sig":"` 即使面对一个字面上含有 `"sig":"` 的文件名也毫不含糊。

该移除是少数几个 POSIX 参数扩展，在签名器和校验器中完全相同，不用 `sed` 也不用 `jq`：

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**第 3 步：对它的哈希签名。**被签名/被验证的消息是规范化形式的 **sha256 十六进制**（64 个 ASCII 字符，无换行）。ed25519 签署那个十六进制。

由此在构造上得出两个推论：

- `key_id` 是规范化形式的一部分（只剥掉 `sig`）。`vdlu-sign` 在哈希**之前**设置 `key_id`，因此密钥身份被签名所覆盖。
- 无论 `sig` 占位符是空的（`"sig":""`，在签名时）还是已填充的（在验证时），剥掉它都会产生完全相同的规范化字节。签名与验证自动达成一致。

两个 POSIX sh 工具是权威。一个 Python 等价物，`re.sub(r'"sig":"[^"]*",', '', text, count=1)` 然后 sha256，仅为交叉核对它们而存在。

围绕这一切的信任推理（为什么验证在设备上、`hardened` 如何故障即关闭）存在于 [[Security and Trust Model]]。

---

## baseline.json（安装种子）

当一个模块刚被安装时，它对于自己所交付的版本就应该已经是"当前的"，无需对刚安装的版本做任何多余的自更新。这正是 `baseline.json` 所做的。

`baseline.json` **在模块 zip 内部**交付（位于 `vdlu/baseline.json`），而不是在 feed 上。在一次全新安装时，引擎从它播种自己的 "active version" 记录，因此设备一出生即为当前版本，没有 `from:0`，也不重新拉取它已经拥有的东西。

关键属性：

- 它是所交付版本的**已签名清单的无密钥副本**：同样的 `vdlu-pack` 输出，保持未签名（`key_id` 和 `sig` 保持为空）。
- 它**不被验证**。引擎把它当作一个本地可信种子，因为它是在被刷入的 zip 内部到达的，而那正是安装的信任边界。只有一个*从 feed 拉取的*清单才会经过签名验证。
- 因为它不需要签名，**CI 可以无密钥地生成它**，这正是把签名密钥完全保持在 CI 之外的东西（见 [[Producer]]）。
- `vdlu-pack` **把 `baseline.json` 从它自己的清单中排除**，因此清单从不引用 baseline（那会是一个自引用环：清单到 baseline 到清单）。
- 它**缺失也不致命**。没有它，设备就在其首次更新时简单地从 `from:0` 开始并拉取它所需的东西。永不损坏，只是不那么优化。

---

## Blob

每份不同的文件内容是 `blobs/` 下的一个 blob，以**原始内容的 sha256** 命名：

- `blobs/<sha256>` 用于一个原始 blob。
- `blobs/<sha256>.gz` 用于一个 gzip 过的 blob（gzip 仅在文件至少 4096 字节且压缩至少节省 10% 时才保留）。

一个 blob 只以一种格式存储一次。按内容寻址免费带来去重：未变化的、共享的或被回退的内容映射到一个已经存在的 blob，因此 feed 只因真正的新内容而增长，设备也只下载它缺失的那些哈希。设备在使用之前，会对照清单校验每个下载的 blob 的 `sha256`（在解压一个 `gz` blob 之后）。

---

## 什么被排除在 feed 之外，以及为什么

Feed 只承载**模块自己的内容**。一组固定的路径被刻意地排除在它之外。`vdlu-pack` 在遍历目录树时以及在计算 `delete[]` 时都应用同一个排除谓词。

| 被排除 | 为什么 |
|---|---|
| `vdlu/keyring/`、`vdlu/verify/`（信任根：原始公钥 + 校验器二进制） | **这是核心的安全理由。**信任锚（trust anchor）是**仅经刷入的**。如果 keyring 或校验器可经 feed 交付，一个清单就可能覆盖那个校验它自身的东西。把它们保持在网络之外意味着一个清单永远无法重写设备上的信任锚。 |
| `vdlu/baseline.json` | 它是已签名清单的一份副本（安装种子）；打包它会是一个自引用环。 |
| `.vd/` 刷入基础设施 | 在 zip 中交付的 flash-gate 脚手架，从不实时应用。 |
| `update.json`、`update-mmrl.json` | 它们的 size/sha 由 CI 在 zip 构建*之后*填入，因此所交付的副本与任何 feed 副本都不同。提供它们会在每次安装的首次自更新时导致一次幻影式的单文件拉取，而且它们在设备上无论如何都是残留的（管理器读取远端的原始 update JSON）。 |
| `META-INF/`、`customize.sh`（安装器脚手架） | 在**刷入**时由管理器消费，不保留在已安装的模块中。它们不是 VDLU 内容；提供它们会浪费 blob，而且如果其中一个在版本间曾经变化，它就会被作为一个安装器文件写进在用的模块目录。 |
| 每文件的 `.sha256` 伴随文件 | 它们只属于可刷入的 zip，在一次增量更新后会变陈旧，并且会让清单翻倍。 |
| dev/doc 文件（`RELEASE.md`、`CLAUDE.md`、`.gitignore`） | 从不交付到设备；提供它们会浪费 blob，并在每次文档编辑时搅动已签名的清单。 |

信任根排除背后的推理在 [[Security and Trust Model]] 中有展开。

---

## delete[] 语义

`delete[]` 告诉设备要移除哪些路径，使一个在版本间被丢弃的文件不会作为孤儿在设备上滞留。它通过把 `--prev <previous manifest.json>` 传给 `vdlu-pack` 来计算：一个在上一版本中存在、而在当前版本中不存在的路径会成为一个删除条目。

重要规则：**被排除的路径永远不会被发出为删除，即使带 `--prev`。**每个先前的路径都会经过遍历目录树时所用的同一个排除谓词。如果一个 `--prev` 指向一个仍然列着如今被排除的路径（一个游离的 `baseline.json`、`META-INF/*`、一个 keyring 条目等等）的较旧清单，这些路径**不会**被转成删除条目。一个被排除的路径从来就不是 feed 内容，因此删除它不是 VDLU 的职责，而且设备永远不会被命令去移除一个未经 feed 提供的文件。这正是让排除列表永不反过来变成一条破坏性指令的东西。
