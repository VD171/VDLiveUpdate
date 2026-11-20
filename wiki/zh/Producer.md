# Producer

**Producer** 是 VDLU 的 PC / 发布端：一小组工具，把一个完成的模块目录树转换成一个已签名、按内容寻址、供设备据以更新的 feed。这里没有任何东西运行在手机上。这些工具运行在你的发布机器上（或者对于可以安全运行的部分，在 CI 中）。

它们共有四个：

| 工具 | 运行于 | 语言 | 职责 |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | 把最终的模块目录树遍历成 `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | 生成一对 ed25519 签名密钥 |
| `vdlu-sign` | PC | sh + openssl | 就地把 `key_id` + 签名注入一个清单 |
| `vdlu-gc` | PC | python3 | 从一个已发布的 feed 中清理孤儿 blob（fail-safe） |

发布流程有三步，每次发布做一次：**pack，然后 sign，然后 publish**。`vdlu-keygen` 是一次性设置，而 `vdlu-gc` 是当 feed 变大时你运行的日常维护。producer 发出的一切都符合 [[Feed Format]]，这正是设备上的引擎所消费的。

---

## vdlu-pack

`vdlu-pack` 取**你的 `.zip` 所交付的那个确切目录树**（最终目录树，在你的构建应用了它自己的白名单和 ABI 裁剪之后），并为它生成 feed。

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

它向 `<out_dir>` 写入两样东西：

- `manifest.json` - 目标目录树的完整描述（每个文件带其 `sha256`、`size`、`mode`、编码和 reboot class），仍是**未签名的**（`key_id` 和 `sig` 字段是空占位符）。
- `blobs/<sha256>`（或 `blobs/<sha256>.gz`）- 每份不同的文件内容一个 blob。

### 按内容寻址且去重

每个 blob 都以其**原始（未压缩）内容的 sha256** 命名。因为名字就是哈希，相同的内容会落到同一个 blob 上。`vdlu-pack` 只在 blob 尚不存在时才写入它，因此：

- 一个没有变化的文件保持相同的 blob 名字，永远不会被重写或再次推送。
- 两个内容相同的不同文件共享一个 blob。
- 一个被回退的文件复用此前就已存在的那个 blob。

因此发布**在构造上即是增量的**：跨版本，`blobs/` 只会增长，而且只有真正的新内容会被添加。设备按同样的哈希拉取，因此它只下载它尚未拥有的那些 blob。

### 压缩（`enc` 字段）

对每个文件，`vdlu-pack` 决定如何存储 blob：

- 当文件至少 4096 字节**且** gzip（确定性的 `-9 -n`）至少节省 10% 时，用 `gz`。
- 否则用 `raw`（小文件在传输时的 gzip 已经覆盖，或者本就不可压缩的数据）。
- 如果构建主机上缺少 `gzip`，一切都以 `raw` 存储。打包绝不会因此失败。

清单中的 `sha256` **始终**是原始内容的；`enc` 只是命名 blob 恰好是如何存储的。设备用 toybox `gunzip` 解压 `gz` blob，然后对照原始内容校验哈希。

### reboot class 与安全

`vdlu-pack` 还会给每个文件打上一个从其路径推导出的 reboot `class`（`live`、`soft`、`reboot`），因此引擎知道什么可以免重启应用、什么必须被 staged。规则以及设备对每个 class 的处理见 [[Reboot Handling]]。

有几件 `vdlu-pack` 刻意**不**做的事：

- 它不跟随符号链接（它跳过它们并给出警告，因此来自目录树之外的内容，例如指向一个系统文件的链接，永远不可能泄漏进一个 blob）。
- 它跳过非普通文件（目录、fifo、设备）。
- 它为 `built` 时间戳尊重 `SOURCE_DATE_EPOCH`，因此清单是可复现的。
- 它从 feed 中完全排除一组固定的路径（信任根、安装器脚手架，以及另外几个）。完整列表以及为什么每一个被排除，见 [[Feed Format]]。

### `delete[]` 列表

传入 `--prev <previous manifest.json>`，`vdlu-pack` 就会计算 `delete[]`：那些存在于上一版本但在本版本中已消失的路径，于是设备会移除它们，而不是把孤儿留在身后。被排除的路径永远不会被发出为删除，即使它们出现在上一个清单里（确切语义见 [[Feed Format]]）。

---

## vdlu-keygen

一个一次性步骤。`vdlu-keygen` 为你的 feed 创建一对 ed25519 签名密钥。

```sh
vdlu-keygen <id> <out_dir>
```

它写入三个文件：

| 文件 | 它是什么 | 它去哪里 |
|---|---|---|
| `<id>.pem` | **私有**签名密钥（mode `0600`） | 留在你的发布机器上。永不外泄。 |
| `<id>.pub` | PEM 形式的公钥 | 仅 PC 端工具 |
| `<id>.pub.raw` | **原始 32 字节**形式的公钥 | 作为模块设备端 keyring 条目交付 |

原始 32 字节公钥是设备校验器所读取的东西（它不携带 `openssl`，因此无法读取 PEM）。你把 `<id>.pub.raw` 内嵌进模块，作为 `vdlu/keyring/<id>.pub`。PEM 仅供 PC 端使用。这种拆分，以及密钥轮换（key rotation）如何工作，在 [[Security and Trust Model]] 中有解释。

> **多密钥 keyring 必须钉定 `key_id`。**如果模块的 keyring 交付不止一个密钥（例如 release 密钥加上一个较低信任的指纹 feed 密钥），引擎不会猜测哪一个可以签名一次模块更新。把 `key_id` 配置设为被允许签名更新的那个密钥，或在轮换窗口期内以逗号分隔的多个密钥；单密钥 keyring 会自动钉定且无需配置。这就是模块更新允许列表，在 [[Security and Trust Model]] 中有讲述。

> 私有的 `.pem` 是整个系统中唯一的秘密。把它从每台设备上、从每次仓库推送中排除出去。见下面关于 CI 的说明。

---

## vdlu-sign

`vdlu-sign` 取 `vdlu-pack` 生成的未签名清单，并**就地**签名它。

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

它设置 `key_id` 字段，计算清单的规范化形式，并把 ed25519 签名（base64）写入 `sig` 字段。该签名是针对清单的一个精确字节变换，以便 PC 和设备在设备上没有任何 JSON 库的情况下推导出完全相同的被签名字节。那个变换（即**规范化**）是该格式中唯一最重要的不变式，并在 [[Feed Format]] 中有完整文档。

私钥只在此处、在你的机器上被读取，且永不离开它。

### 签名密钥始终在 CI 之外

这是一个刻意的设计点。CI 可以运行 `vdlu-pack` 并生成一个完全有效的**无密钥 baseline**（一个未签名的种子清单；见 [[Feed Format]]），因此全新安装一出生即为当前版本，而 CI 从不接触私钥。已发布 feed 的实际签名由你在本地用 `vdlu-sign` 完成。这样，签名密钥 100% 在 CI 之外，而且只有你手动发布的那个 feed 才被签名。

---

## vdlu-gc

由于 blob 是按内容寻址且不可变的，`blobs/` 只会增长：`vdlu-pack` 只增不删。经过许多次发布，feed（以及托管它的 Pages 站点）会积累一些不再被任何当前清单引用的 blob。`vdlu-gc` 清理这些孤儿。

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

它构建清单的**保留集**：当前的 `manifest.json`，加上按版本计的最近 `N` 个归档清单（默认 `N=3`，给出一个回滚余量），再加上你用 `--keep` 指名的任何清单。一个**没有**被任何保留清单引用的 blob 就是孤儿，是移除的候选。保留集是一个并集，因此只要任何保留的发布仍需要某个 blob，它就会留下；一台停留在较旧保留版本上的设备永远不会失去它的拉取。

`vdlu-gc` 被构建得很安全：

- **默认为试运行（dry-run）。**没有 `--apply` 时，它只打印它*将会*移除什么。你加上 `--apply` 才会真正删除。
- **Fail-safe。**如果它根本找不到任何保留清单，它会拒绝清理，而不是冒着清空一个 feed 的风险。
- **按引用保留，而非按日期。**一个 blob 之所以被保留，是因为一个保留清单指向它，绝不是因为一个时间戳。

清理之后，把更小的 feed 推送到你的主机。如果你的主机对批量写入做速率限制，就把写入在时间上分散开。

---

## 把它们拼在一起

一次典型的发布，端到端：

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

关于把 VDLU 引入一个模块的完整示例演练，见 [[Quick Start]]。关于 producer 发出的一切在传输时的形态，见 [[Feed Format]]。关于密钥处理背后的理由以及什么被排除在 feed 之外，见 [[Security and Trust Model]]。
