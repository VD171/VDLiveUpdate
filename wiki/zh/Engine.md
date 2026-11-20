# Engine

引擎是 VDLU 的设备端：在手机上运行、判断什么发生了变化、下载它并应用它的那一部分。它是一个单独的 POSIX shell 脚本 `engine/update.sh`，外加一个微小的签名校验器 `engine/vdlu-verify`。两者都被内嵌进宿主模块的 `<module>/vdlu/` 中，并由 root 运行。

整个引擎围绕一个理念构建：一次更新是一笔**可续传的事务**。如果手机在中途被重启、被杀掉或掉线，下一次运行会精确地从它停下的地方接续，而且模块绝不会在假装已完成的同时处于半应用状态。

如果你想先看大局，参见 [[Architecture]]。关于更新如何在可能时避免重启，参见 [[Reboot Handling]]。

## 为设备而写，而非为你的笔记本

`update.sh` 是纯 POSIX `sh`。它在 mksh、busybox 或 toybox 下运行，不使用任何仅 bash 的特性，并能通过 `sh -n`。这很重要，因为一台已 root 的 Android 设备上的环境既小又严格。

特别是，这里没有 `jq`。VDLU 用一个小巧的、gron 风格、用 `awk` 写成的扁平化器来解析 `manifest.json`：它逐字符遍历 JSON，为每个叶子发出一行 `path<TAB>value`（例如 `files/0/sha256<TAB>ab..` 或 `version<TAB>6`）。shell 随后用 `grep` 和 `cut` 读取这些行。这在紧凑的和美化打印的 JSON 上都有效，而且它从不去调用一个根本不存在的 JSON 工具。

引擎只依赖 toybox 已经自带的东西（`sha256sum`、`gzip`/`gunzip`、`base64`、`date`）、内嵌的 `ed25519-mini` 校验器，以及对于 `https://` feed，一个被拉取并校验一次的小型静态 `curl`。一个 `file://` feed 则完全不需要 `curl`。

## 六个命令

你用环境中的模块路径加上一个命令来调用引擎：

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

退出码 `0` 表示成功；任何其他码都表示错误，原因会打印到 stderr。

| 命令 | 作用 |
|---|---|
| `check` | 只读的 diff。下载清单，将其与已安装内容比较，并打印一行 JSON 摘要：`{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`。不改动磁盘上的任何内容。如果设备比 feed 更新（一次被阻止的降级），它以退出码 `0` 报告 `{"update":false,"ahead":true,...}`，而不是错误。 |
| `run` | 完整的实时周期：DIFF、FETCH、APPLY、COMMIT。立即应用每个 live 文件，并把少数 reboot 类文件 staged。尊重 `cancel`。把进度写入 `journal.json`。 |
| `resume` | 续接一笔被中断的事务，从它所处的任何阶段开始。幂等。它**不会**交换一个已 staged 的 `.so`（那是留给 `boot` 的）。 |
| `boot` | pre-zygote 路径。先做一次 `resume`，然后把任何已 staged 的 `*.vdlu-new` 文件交换到位，将 `PENDING_REBOOT` 关闭为 `DONE`。如果没有待处理事务，它会运行一个全新周期并在那一次启动中应用一切，包括 `.so`。 |
| `status` | 打印 `journal.json`，或在没有进行中内容时打印 `{"state":"idle"}`。 |
| `cancel` | 创建一个 `cancel` 标记。进行中的 `run` 会在下一个安全点干净地停止。 |

`check` 命令被刻意设计得很廉价，因此 UI 可以在任何网络上告诉你存在一个更新。实际的下载是单独受控的（见下面的 fetch 阶段）。

## 事务，逐步进行

每个 `run` 都会经过一个固定的状态机，记录在 `journal.json` 中，以便 WebUI（和你）可以观察它：

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF。**引擎下载 `manifest.json`，校验每个字段（见下文及 [[Security and Trust Model]]），并把已签名的目标目录树与 `current.json`（已安装版本的清单）做 diff。结果是一个写入 `plan.tsv` 的按文件计划：每个文件一行，承载其 class、目标哈希、mode 和进度状态。已处于目标哈希的文件会被标记为跳过。

**FETCH。**对每个仍然需要的文件，引擎从 `<source>/blobs/<sha>`（压缩时为 `<sha>.gz`）下载其按内容寻址的 blob，存入一个 `.part` 文件。如果该 blob 被 gzip 过，就解压它，然后对照清单校验其 SHA-256。只有在匹配时，它才会被原子地 `mv` 进 `blobs/<sha>`。已在缓存中且哈希正确的 blob 会被完全跳过，而一个未变化的本地文件可以在无需任何下载的情况下播种缓存。同一个 blob 上的三次失败会中止该阶段，不应用任何内容。只有当计划中的每个 blob 都已到位并已验证时，该阶段才会到达 `FETCHED`。关于这些 blob 来自的 [[Feed Format]]，参见那一页。

fetch 受网络策略控制：一个 feed 可以被限制为仅 Wi-Fi、仅移动网络或任意网络。当当前网络不被允许时，fetch 不会失败；它进入良性的 `DEFERRED` 状态，保持计划和目标被固定，并在正确的网络出现后于下一次 check 或 boot 时续传。其间不消耗任何流量。

**APPLY。**只会从 `FETCHED` 进入。对每个文件，引擎按 class 行事：

- `live` 和 `soft` 文件：把当前文件备份到 `rollback/<version>/<path>`，把新内容写入一个同级的 `.vdlu-tmp`，`chmod` 它，校验其哈希，然后原子地 `rename` 它覆盖目标。已处于目标哈希的文件会被跳过。
- `reboot` 文件（一个 `.so`、一个 `/system` overlay、一个 `sepolicy.rule`）：物化到 `staged/<path>.vdlu-new`。此处绝不触碰在用的 inode。参见 [[Reboot Handling]]。
- 删除：先备份，再移除。删除只在最后、在一个干净的 `DONE` 上应用，绝不会在重启仍在待处理时进行。

**COMMIT。**引擎对它触碰过的每个 live 和 soft 文件重新哈希。只有当它们全部匹配时，它才写入 `current.json`，使新版本成为 diff 的基准。如果有任何 reboot 类文件被 staged，状态会变成 `PENDING_REBOOT` 而不是 `DONE`；交换与最终的重新验证稍后在 `boot` 命令下进行。

## 构造上即安全

让它可以无人值守运行的那些保证：

- **没有匹配的重新哈希就不会被标记为 `DONE`。**`DONE` 只在每个已应用的文件都被回读、且其 SHA-256 已与清单比较之后才会到达。一个被 staged 的 reboot 文件会强制 `PENDING_REBOOT`，绝不会是一个虚假的 `DONE`。
- **没有东西会丢失。**每个文件在被覆盖之前都会备份到 `rollback/<version>/`，并保留最近三个版本。如果一次应用失败，live 文件会从备份恢复；模块绝不会在半应用的同时对此撒谎。如果备份步骤失败，`apply_live` 会直接中止，而不是在没有退路的情况下覆盖。
- **一切都是原子的。**新内容经由 `rename`/`mv` 覆盖到目标上落地，因此读者看到的要么是旧文件、要么是新文件，绝不会是一次被截断的写入。
- **崩溃或被杀后可续传。**一次崩溃、一次掉线或中途重启会留下一个有效的日志；`resume`（或 `boot`）会从记录的阶段续接。该设计假定它会被中断。
- **干净地降级。**缺失的二进制、掉线的网络或满了的磁盘，会在 stderr 上产生一个清晰的错误，并在日志中产生 `state:ERROR`，而不会损坏模块。

## 锁

同一时刻只有一笔事务可以触碰状态。`flock` 在 toybox 上不可靠，因此 VDLU 用一个目录锁来串行化：`mkdir "$VDLU_DIR/lock.d"` 恰好对一个调用者成功、对其余调用者失败，这在任何合理的文件系统上都是原子的。由一个已死进程留下的陈旧锁，通过检查记录的 PID 来恢复。

启动时耐心的重试（在设备于启动时离线时使用）在等待期间**不**持有这个锁。它在各次尝试之间获取和释放，因此一次手动 `run` 永远不会被一个正在等待网络的启动阻塞，而且它从不持有 wakelock。设计上即对电池安全。更多内容见 [[Reboot Handling]]。

## 签名校验：`vdlu-verify`

`vdlu-verify` 是设备端的签名校验器，被刻意保持精简：

```
vdlu-verify <manifest.json> <keyring_dir>
```

退出码 `0` 表示清单的签名相对于 keyring 中 id 与清单 `key_id` 匹配的那个公钥是有效的；任何其他码都是一次拒绝。

让它精简的是它使用**设备上没有 `openssl`**。它把 keyring 公钥读为一个**原始 32 字节**文件，将清单规范化（去掉了 `sig` 字段的清单文本），用 toybox `sha256sum` 对其哈希，base64 解码签名，并把原始密钥、消息和 64 字节签名交给内嵌的 `ed25519-mini` 二进制。该校验器在进行验证之前还会拒绝任何畸形内容：缺失或为空的 `key_id` 或 `sig`、含有路径分隔符的 `key_id`、不恰好是 32 字节的公钥，或者不恰好是 64 字节的签名。

该规范化与 producer 的签名器逐字节相同，这正是让一个签名能跨工具验证的原因。对应的私钥从不接触任何设备或 CI；只有原始公钥被内嵌。完整的信任叙述、两个配置档，以及为什么 `hardened` 通过反向判断实现故障即关闭，见 [[Security and Trust Model]]。

引擎在 diff 阶段调用 `vdlu-verify`。在 `hardened` 配置档下，一次验证失败会中止整个更新；在 `trusted` 下，验证是尽力而为（best-effort），但每个 blob 的哈希始终仍会被校验，因此无论哪个配置档，被损坏的内容都会被抓住。

## 磁盘上的状态

引擎的全部状态都存在于 `$VDLU_DIR`（在模块目录之外），因此模块目录树本身始终只保存已完成的文件：

| 路径 | 角色 |
|---|---|
| `config` | key=value 设置（source、profile、channel、网络策略、boot retry） |
| `current.json` | 当前活动版本的清单；这是 diff 的基准。缺失表示从未更新过 |
| `target.json` | 进行中事务的固定清单。它的存在标志着一笔活动事务；在 `DONE` 时它成为 `current.json` |
| `plan.tsv` / `plan.del` | 按文件的计划与进度，以及要删除的路径列表 |
| `journal.json` | 给 WebUI 的进度，在每次状态变化时重写 |
| `blobs/<sha256>` | 已验证、已解压的原始内容缓存 |
| `rollback/<version>/<path>` | 被覆盖文件的备份；保留最近三个版本 |
| `staged/<path>.vdlu-new` | 等待启动时交换的 reboot 类文件 |
| `lock.d/` | mkdir 锁 |
| `tools/<abi>/curl` | 已拉取、已校验的静态 curl；跨更新保留 |
| `cancel` | 一个取消请求 |

## 另见

- [[Reboot Handling]]：class 系统如何让大多数更新免重启，以及一个已 staged 的 `.so` 如何在 pre-zygote 被交换。
- [[Security and Trust Model]]：两个配置档、故障即关闭的校验，以及原始密钥的 ed25519 链。
- [[Feed Format]]：引擎消费的清单与按内容寻址的 blob。
- [[Architecture]]：引擎、producer 与 WebUI 如何拼合在一起。
