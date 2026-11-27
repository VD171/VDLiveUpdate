> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · 中文

---

# 从 AI 智能体驱动 VDLU

VDLiveUpdate（VDLU）是 KSU/Magisk 模块随附于 `vdlu/` 的免刷机增量更新器。整个引擎都从 shell 驱动，因此 AI 助手或智能体可以无界面地检查、应用、恢复并完成一次更新，与 WebUI 运行的循环相同，没有 UI，也没有人在回路中。解析它打印的 JSON，绝不抓取文本。

## 契约

单一入口，在设备上以 root 运行，并设置引擎的三个环境变量：

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` 是 Tier-2 状态目录（在模块之外，可在刷入后保留），`MODULE_DIR` 是模块的活动树，`MODID` 是模块 id。
- `rc 0` = 正常，`rc != 0` = 错误，原因在 stderr 上。
- 读取动词（`check`、`status`）在 stdout 上打印**一个 JSON 对象**。解析它，绝不抓取文本。
- 引擎只依赖 toybox（`sha256sum`/`gzip`/`base64`）加一个内嵌的 `ed25519-mini` 加一个在首次 https 更新时获取的静态 `curl`，零 `jq`。

开发期间同一脚本位于本仓库的 `engine/update.sh`，因此设置了三个变量后 `sh engine/update.sh <verb>` 以同样方式驱动一个测试副本。

## 动词

| 动词 | 做什么 | 打印 |
|------|------|--------|
| `check` | 针对 feed 的只读 DIFF，不改变任何东西 | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`，或当设备领先于 feed 时为 `{"update":false,"ahead":true,"from":N,"to":M}`（降级被阻止，良性，rc 0） |
| `run` | 完整 LIVE 循环 DIFF -> FETCH -> APPLY -> COMMIT，应用 LIVE 文件并编排 REBOOT-hard，尊重 `cancel` | 进度在 `journal.json` 中 |
| `resume` | 从当前阶段恢复待处理事务，幂等，绝不替换 `.so` | 更新后的 `journal.json` |
| `boot` | pre-zygote 模式，`resume` 加上已编排 `.so` 的替换，将 `PENDING_REBOOT` 收尾为 `DONE` | 更新后的 `journal.json` |
| `status` | 只读快照，不改变任何东西 | `journal.json`，或当没有事务活动时为 `{"state":"idle"}` |
| `cancel` | 请求停止，进行中的 `run` 在下一个安全点停下 | 创建 `$VDLU_DIR/cancel` |

一次无界面更新是用 `check` 看是否有待处理，用 `run` 应用一切可以上线的内容，然后在下次开机时用 `boot` 替换任何已编排的 `.so`（或用 `resume` 重试被推迟的下载）。每个动词都可安全地再次调用，循环中途崩溃或掉网会留下一个可恢复的 journal，绝不会留下半应用的模块。

## 状态 JSON

`status`（以及 `$VDLU_DIR/journal.json` 处的活动文件）是 WebUI 和智能体都读取的进度契约：

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` 按固定顺序移动：`PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`。
- `DONE` 只有在对一切重新哈希都匹配后才达到。一个已编排的 REBOOT-hard 文件产生 `PENDING_REBOOT`，绝不是假的 `DONE`，运行 `boot` 来完成它。
- `DEFERRED` 表示 `net_policy` 阻止了下载，是一个良性且可恢复的状态而非错误，计划持续存在，下一次 `check`/`boot` 继续。
- `ERROR` 在 `error` 中携带原因，已应用的 LIVE 文件从 `rollback/` 回退，模块绝不会被留在半应用状态。
- `cancelled:true` 带 `error:null` 是一次干净的停止，journal 仍可恢复。

## 接缝契约

每个组件（引擎、生产者、WebUI）都遵从 [`INTERFACES.md`](INTERFACES.md)，收敛之法。那里定义的 CLI 动词、`manifest.json` 模式、`journal.json` 键和 config 键都是**不可变的**，把那个文件当作唯一的事实来源，在更改其中任何一个之前先与它对齐。关于引擎内部（可恢复事务、严谨性保证、trust-anchor 排除）见 [`ENGINE.md`](ENGINE.md)，关于 feed 一侧（构建并签名按内容寻址的 feed）见 [`PRODUCER.md`](PRODUCER.md)。

## 给智能体的规则

- 使用动词和 JSON，绝不抓取 WebUI，也绝不手动编辑状态文件。
- 把 `INTERFACES.md` 当作不可变，一次更改意味着先对齐契约。
- 来自 AI 智能体的补丁与任何其他补丁经过同一道评审关，build 永远 release，不放松任何东西，不丢失任何东西。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
