# Architecture

VDLU 有两侧，由中间的一样东西连接。在 PC 上，[[Producer]] 把一个模块目录树转换成一个已签名、按内容寻址的 feed。在设备上，[[Engine]] 读取该 feed，弄清楚什么发生了变化，并应用它。两者之间的接缝是**已签名的清单加上 blob 存储**（即 [[Feed Format]]）。除此之外没有别的东西跨越这道缝隙。

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

两侧从不共享运行时。Producer 使用 `python3` 和 `openssl`；Engine 是纯 POSIX `sh`，配合 toybox 和一个内嵌的 `ed25519-mini`。它们之所以能达成一致，仅仅是因为两者都从一个清单推导出**相同的规范化（canonical）字节**（参见 [[Security and Trust Model]]）。WebUI 是一个薄薄的、纯 JS 面板，它通过 root 管理器桥驱动引擎并读取其进度日志；它本身不包含任何更新逻辑。参见 [[WebUI]]。

## 两侧

| 一侧 | 运行于 | 构建自 | 职责 |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | 把模块目录树遍历成 `manifest.json` + `blobs/`，签名，清理孤儿 |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | 将已安装的目录树与 feed 做 diff，拉取差量，应用，提交 |
| [[WebUI]] | device (webview) | vanilla JS/CSS | 触发更新、显示进度、编辑配置、显示重启横幅 |

## 更新流水线

每次更新都是一笔事务，按固定顺序运行：

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF**（`update.sh check` 就是这个阶段，只读）。引擎只下载清单，在触碰任何东西**之前**对每个字段运行 `validate_plan()`，然后将 feed 与 `current.json` 比较以构建一个按文件的计划。它不会改动磁盘上的任何内容。设备领先于 feed 是一个良性的 "ahead" 结果，而不是错误。
- **FETCH。**只下载计划中缺失的 blob，存入 `<sha>.part`，解压 `gz`，对照清单校验 `sha256sum`，并把每个已验证的 blob 原子地 `mv` 进缓存。已在缓存中（或由未变化的本地文件播种）的 blob 会被跳过，因此一次回退或一个共享文件不会有任何开销。某个 blob 上的三次失败会中止该阶段，不应用任何内容。被网络策略阻止的下载会以 `DEFERRED`（可续传）退出，而不是错误。
- **APPLY。**普通（`live` / `soft`）文件现在就写入：备份到 `rollback/<v>/`，写入一个 `.vdlu-tmp`，`chmod`，校验，然后原子地 `rename` 覆盖到目标上。reboot 类文件被物化（materialize）到 `staged/<path>.vdlu-new`，而在用的 inode 保持不动。一个 `delete[]` 条目会先备份，再移除。每一步都是幂等的：已处于目标哈希的文件会被跳过。
- **COMMIT。**重新哈希每个 live 文件；只有在一切都匹配时，引擎才把 `target.json` 提升为 `current.json`。如果有任何内容被 staged，事务以 `PENDING_REBOOT` 结束；否则为 `DONE`。

## 按内容寻址的清单与 blob

Feed 是按内容寻址的：清单列出**完整**的目标目录树，每个文件由其 `sha256` 承载，而 blob 存储在 `blobs/<sha256>`（或 `blobs/<sha256>.gz`）下为每一份不同内容保存一份副本。

- **去重。**目录树中任何位置、或跨版本的相同内容，都是同一个 blob。发布是增量的：`sha256` 已存在于主机上的 blob 永远不会被再次推送，设备也永远不会重新拉取它已经拥有的内容。
- **sha256 是原始内容的。**哈希始终命名未压缩的内容；`enc`（`raw` 或 `gz`）只记录该 blob 恰好是如何存储的。设备用 toybox `gunzip` 解压 `gz`，因此不会捆绑额外的压缩器。
- **版本变体稳定。**由于设备是与实际已安装的内容做 diff，feed 可以承载整个模块家族；每次安装只拉取补全其自身变体所需的那些 blob。

逐字段的完整布局见 [[Feed Format]]。

## 可续传的日志

每笔事务都能抵御崩溃，因为其进度存在于一个日志（`journal.json`）中，而进行中事务的固定目标（pinned target）存在于 `target.json` 中。状态机按固定顺序运行：

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| 状态 | 含义 |
|---|---|
| `PLANNED` | 计划已构建，尚未拉取任何内容 |
| `FETCHING` / `FETCHED` | 正在下载 blob / 所有 blob 已到位并已验证 |
| `APPLYING` / `APPLIED_LIVE` | 正在写入文件 / 所有 live 文件已写入 |
| `PENDING_REBOOT` | 某个 reboot 类文件已被 staged，等待启动时交换 |
| `DONE` | 对一切的重新哈希已匹配；`current.json` 已提升 |
| `ERROR` | 严重失败；模块保持未损坏，live 文件从 `rollback/` 回退 |
| `DEFERRED` | 下载被网络策略拦下；计划得以保留，稍后续传 |

`DONE` **只有**在对一切的一次重新哈希匹配之后才会到达，因此日志永远不会声称一次半应用的更新已完成。一次崩溃、一次掉线或中途重启会留下一个可续传的日志；`update.sh resume`（或 `boot`）会从当前阶段接续。命令集与设备端的状态文件参见 [[Engine]]。

## 原子性与回滚

没有任何东西会被就地覆盖，也没有任何东西会丢失：

- **原子写入。**每个文件都经由一个临时文件（`.vdlu-tmp`）和一次原子 `rename` / `mv` 落地，因此读者永远不会看到一个写了一半的文件。
- **覆盖前备份。**在新文件被 rename 覆盖之前，先前的内容会进入 `rollback/<version>/<path>`（保留最近几个版本）。如果一次应用失败，live 文件会从回滚副本恢复，而不是留下损坏状态。一次失败的备份会**中止**应用，而不是在没有安全网的情况下覆盖。
- **串行化。**一个基于 `mkdir` 的锁（`lock.d/`，因为 `flock` 在 toybox 上不可行，并通过 PID 进行陈旧锁恢复）将并发运行串行化。

## 免重启原则

大多数文件可以在模块处于运行状态时被交换，因此 VDLU 会立即应用它们。只有三类需要重启，因为一个运行中的进程已经把它们映射（map）进了内存：一个 `.so`（由 Zygisk 加载）、一个 `/system` overlay，以及一个 `sepolicy.rule`。这些文件会被 **staged，绝不写在一个在用的 inode 上**，并在下一次启动时的单个 pre-zygote 步骤中交换。完整的分类法与启动流程见 [[Reboot Handling]]。

## 故障即关闭的信任态势

Feed 是唯一从 PC 跨越到设备的东西，因此引擎把它的每个字节都当作敌对的。`validate_plan()` 在 DIFF 阶段运行，先于任何下载，并在任何畸形字段上拒绝整个清单。签名验证使用一个内嵌的 `ed25519-mini`（设备上没有 `openssl`），私钥从不接触任何设备或 CI，而 `hardened` 配置档通过反向判断实现故障即关闭，因此一个被损坏的配置档值永远不可能悄悄接受一个未签名的 feed。完整模型、两个配置档，以及每个配置档所应对的威胁见 [[Security and Trust Model]]。
