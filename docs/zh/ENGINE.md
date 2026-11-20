> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · 中文

---

# VDLU engine（`update.sh`）

面向 KSU/Magisk 模块的免刷写、增量更新客户端。将
`DIFF -> FETCH -> APPLY -> COMMIT` 周期实现为一个可恢复的事务。遵从 `INTERFACES.md`（收敛
法则）。

纯 POSIX sh（mksh/busybox/toybox）。**SLIM：** 它仅依赖 toybox（`sha256sum`/`gzip`/`base64`/`date`）+
内嵌的 `ed25519-mini`（ed25519 verify；**设备上无 openssl**）+ 在首次 https 更新时**抓取**的一个
静态 `curl`（WebUI 执行 `fetch()`，将其持久化到 Tier-2，而 `install-tool` 在使用前验证其
签名+哈希）。`file://` 不需要 curl。对 `jq` 零依赖。

## 调用

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok；`rc != 0` = 错误（原因在 stderr）。`vdlu-verify` 由另一个组件提供
（签名在 `INTERFACES.md §6`）；engine 只调用它。

| cmd | 作用 |
|---|---|
| `check` | 只读 DIFF；打印 `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`；不改变任何东西 |
| `run` | 完整的 LIVE 周期 + 暂存 REBOOT-hard；遵从 `cancel`；进度在 `journal.json` |
| `resume` | 从当前阶段恢复待处理事务（`target.json`）；幂等；**不**交换 `.so` |
| `boot` | pre-zygote 模式：resume **+** 交换 `staged/*.vdlu-new` → 关闭 `PENDING_REBOOT`→`DONE`。若无待处理事务，它运行一个全新周期并在单次启动中应用所有东西（包括 `.so`） |
| `status` | 打印 `journal.json`（或 `{"state":"idle"}`） |
| `cancel` | 创建 `$VDLU_DIR/cancel`；进行中的 `run` 在下一个安全点停止 |

## 状态机（journal.json）

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` 仅当对所有内容的重新哈希匹配时。若任何 REBOOT-hard 被暂存 ⇒ `PENDING_REBOOT`（绝不是虚假的
`DONE`）。任何失败时 `ERROR`，而不损坏模块（已应用的 LIVE 文件从 `rollback/<v>/` 回滚；
没有任何“半应用却对此撒谎”的东西）。`fetch` 阶段的良性退出：**`DEFERRED`** -
下载被 `net_policy` 延迟（网络不被允许）；plan/target 持久化且它在下一次
check/boot 时恢复（WebUI 显示一个蓝色 info toast“等待 X 网络”，而非错误）。

## 严谨性保证

- **FETCH：** 受 `net_policy` 控制（any/wifi/mobile；仅 http/https，`file://` 从不）- 一个不被允许的网络 ⇒
  `DEFERRED`（可恢复），不花费流量。只把缺失的下载到 `<sha>.part`（curl 带
  `--connect-timeout` + `--speed-time`，从不挂起），解压 `gz`（toybox `gunzip`），检查 `sha256sum` ==
  清单，原子 `mv` 到 `blobs/<sha>`。已缓存+ok 的 blob 被跳过。它可以从一个未改变的本地文件
  播种 blob（dedup/offline）。**同一 blob 上 3 次失败 = 该阶段中止，不应用任何东西。** 它
  仅在计划的所有 blob 都存在+已校验时才变为 `FETCHED`。
- **APPLY**（仅从 `FETCHED`）：`live`/`soft` → 备份到 `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  原子 `rename`。`reboot` → 物化到 `staged/<path>.vdlu-new`（不触碰 live inode）。
  `delete[]` → 备份 → 移除。幂等（已在目标哈希的文件被跳过）。
- **COMMIT：** 对每个 `live`/`soft` 重新哈希；然后才写 `current.json`。有暂存文件时 ⇒
  `PENDING_REBOOT`。`boot` 执行 `mv -f staged/....vdlu-new $MODULE_DIR/<path>`（pre-zygote）+ 重新验证 +
  `DONE`。
- **cancel：** 在文件之间检查（安全点）；移除在途的 `.vdlu-tmp`/`.part`，删除 `cancel`，
  使 journal 保持可恢复（`cancelled:true`，`error:null`）。
- **mkdir-lock `$VDLU_DIR/lock.d`** 进行串行化（flock 在 toybox 上不可行；按 PID 恢复过期锁）。
  耐心 boot-retry 在等待期间既不持有锁（各次尝试之间 `acquire_lock_try`+release）也不持有
  wakelock - 省电。中途崩溃/网络/重启 → `resume`/`boot` 继续。
- **profile=hardened** ⇒ 使用前在清单上强制 `vdlu-verify`；失败 = abort；降级被阻止
  （单调版本）。**trusted** ⇒ verify 尽力而为，但每个 blob 的哈希始终被检查。
- **module-update 密钥 allowlist（两个 profiles）：** `verify_manifest` 在 pubkey 选取之前，fail-closed 地拒绝任何 `key_id` 不在已配置 `key_id` allowlist（见 INTERFACES §5/§6）中的清单，因此仅仅待在 keyring 中的较低信任密钥（例如一个 fingerprint-feed 密钥）绝不能签署 flashless root 更新。未设置时默认安全：单密钥 keyring = 仅那一个密钥；多密钥 keyring = 在 `key_id` 被固定前拒绝。
- 优雅降级：缺少二进制 / 网络中断 / 磁盘已满 → stderr 上一个清晰的错误 + journal 中的
  `state:ERROR`，而不损坏模块。

## 无 jq 的 JSON 解析

`awk` 中一个 gron 风格的 flattener（纯 POSIX：`substr`/`index`/`gsub`/`split`/`printf` + 作为
参数传递的局部变量）逐字符地标记化清单，并为每个标量叶子发出一行 `path<TAB>value`
（`files/0/sha256<TAB>ab..`、`version<TAB>6`、`delete/0<TAB>etc/x`）。对紧凑或美化打印的
JSON 都健壮。`sh` 用 `grep`/`cut` 消费它；逐文件计划在第 2 个 `awk` 中重组为 TSV
（`class st mode enc sha size path`），它成为 `$VDLU_DIR/plan.tsv`。

## 状态文件（在 `$VDLU_DIR`，Tier-2）

| 文件 | 角色 |
|---|---|
| `config` | key=value（`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…；见 INTERFACES §5） |
| `current.json` | 当前 ACTIVE 版本的清单（diff 基准）；缺失 = 从未更新过 |
| `target.json` | 在途事务的固定清单（存在 = 活动事务）；`DONE` 时变为 `current.json` |
| `plan.tsv` / `plan.del` | 计划 + 逐文件进度（st）/ 要删除的路径 |
| `journal.json` | 给 WebUI 的进度（每次转换时重新生成） |
| `blobs/<sha256>` | 已校验原始内容的缓存 |
| `rollback/<version>/<path>` | 被覆盖文件的备份（undo；保留最近 3 个） |
| `staged/<path>.vdlu-new` | 等待在启动时交换的 REBOOT-hard |
| `lock.d/` | mkdir-lock（flock 在 toybox 上不可行；按 PID 恢复过期锁） |
| `tools/<abi>/curl` | 抓取的静态 curl（slim bootstrap）；跨更新持久化 |
| `cancel` | 取消请求 |

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
