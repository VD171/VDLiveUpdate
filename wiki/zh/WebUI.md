# WebUI

VDLU 附带一个可选的、即插即用的 WebUI 小部件：一个供 KernelSU 或 APatch root 管理器 WebUI 使用的小型 "Updates" 面板。它给用户一个 Check 按钮、一个 Update now 按钮、一个带取消的实时进度 toast、一个重启横幅，以及一个设置面板，而用户全程无需触碰终端。

它是**纯 JavaScript**：没有框架、没有构建步骤、没有 CDN。三个文件：

| 文件 | 它是什么 |
|---|---|
| `vdlu.js` | 小部件；暴露 `window.VDLU` |
| `vdlu.css` | toast、横幅和面板的样式（深色主题，继承宿主的 CSS 变量） |
| `demo.html` | 一个独立页面，模拟设备桥，使整个 UI 能在普通浏览器中运行 |

该小部件完全可选。[[Engine]] 自身通过启动触发器就能良好运行；WebUI 只是叠在其上的一张友好面孔。关于把它接入一个模块，参见 [[Quick Start]]。

---

## UI 如何与引擎对话：`ksu.exec` 桥

小部件本身从不做任何特权操作。它构建一个 shell 命令并把它交给 root 管理器的 `ksu.exec` 桥，后者以 root 运行它并返回 stdout / stderr / 退出码。面板显示的一切都是从引擎写入的文件中回读的。

小部件把那个桥包装进一个单独的 `exec(cmd)` 函数，该函数返回一个 `Promise`：

- 当命令以 0 退出时，带 stdout **resolve**
- 否则带 stderr（或 `rc=N`）**reject**

每个命令都携带由小部件组装的契约环境：

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

几个具体调用：

- **开始一次更新：**`update.sh run` 在**后台**（`(... &)`）启动，因此 UI 永远不会被一次长时间下载阻塞。
- **读取进度：**对 `cat $VDLU_DIR/journal.json` 做轻量轮询（大约每秒一次）。
- **取消：**`touch $VDLU_DIR/cancel`（引擎在下一个安全点停止）。
- **配置：**读写 `$VDLU_DIR/config`（key=value），保留顺序和未知键，只触碰用户改动过的那些键。

如果宿主把它自己的 `exec`、`toast` 和 `confirm` 辅助函数传给 `init()`，小部件就会经由宿主自己的串行化命令队列和视觉元素进行路由，因此它的外观和行为就像那个 WebUI 的其余部分。如果它们被省略，小部件会回退到直接调用 `ksu.exec` 并注入它自己的迷你 toast。

---

## 进度 toast（带取消）

一旦一次更新正在运行，小部件就会显示一个非阻塞的角落 toast 并轮询 `journal.json`。该 toast 反映引擎的状态机：

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

它绘制一个进度条，外加一行 `phase done/total - current file - bytes`，并全程带有一个 **Cancel** 按钮。每个终止状态都有各自的处理：

- **DONE** -> 一个绿色 toast，"vX applied - all verified"。
- **PENDING_REBOOT** -> 一个绿色 toast，外加一个持久的重启横幅（见下文）。
- **ERROR** -> 一个红色 toast，带来自 `journal.error` 或 stderr 的原因，并提供 Retry。它从不伪造成功。
- **Cancelled** -> 一个琥珀色 toast，"cancelled - N/M applied, resumable"，并提供 **Resume**。
- **DEFERRED** -> 一个柔和的蓝色信息 toast，"download deferred, waiting for the allowed network"。这是一次良性的网络策略等待，不是错误；它会在正确网络上的下一次 check 或 boot 时续传。

轮询是防御性的。一个写了一半的日志（引擎并发写入）会在那一拍（tick）被忽略，而不是被错误解析。如果在看到进度之后日志消失了，那意味着 commit 清除了它：小部件报告 DONE。如果日志从一开始就缺席达 8 拍，它报告 "no response"。而如果日志在相同的值上冻结达 20 拍，小部件会检查引擎的 `lock.d`：如果锁还活着，那只是一次缓慢的单 blob 拉取，toast 继续等待；如果锁已死，说明运行在中途死掉了，于是小部件浮现一个带 Resume 按钮的错误，而不是永远在 "updating" 上打转。

---

## 重启横幅

有些文件无法在运行中的系统上交换：一个 `.so`、一个 `/system` overlay、一个 `sepolicy.rule`。引擎把这些 staged 并把事务标记为 `PENDING_REBOOT`。小部件随后显示一个**持久的顶部横幅**："Reboot to activate the new `.so` (vX)"。它会一直留到那些 staged 文件在下一次启动时被交换。在 WebUI 打开时，横幅会从日志重新评估，因此关闭并重新打开 UI 的用户仍然能看到它。关于启动时会发生什么，参见 [[Reboot Handling]]。

注意横幅是依据终止状态 `PENDING_REBOOT`，而不是依据 `reboot_pending` 标志（该标志在任何 `.so` 进入计划的那一刻就变为真）。这使横幅不会在运行中途、在真正有东西被 staged 之前出现。

---

## "Updates" 面板：各类别独立的开关

`mountUpdatesPanel(el)` 把设置面板渲染进宿主提供的一个空 `<div>`。它有三个区段，每个控件都是独立的并各自保存：

**Actions**
- **Check for updates** -> 运行 `check`，就地显示结果（已是最新 / 比 feed 新 / 有可用更新，带文件数量和一个 reboot 标记）。
- **Update now** -> 触发 `run` 外加进度 toast。

**Automation**（独立开关，每个在被切换的那一刻就写入 `config`）
- **On WebUI open**（`auto_on_webui_open`）-> 在 UI 打开时运行一次静默更新。
- **On reboot**（`auto_on_reboot`）-> 在启动时于 pre-zygote 应用。
- **Boot retry every (s)** 和 **Boot retry up to (min)** -> 数字字段，用于在设备离线启动时重试一次清单拉取。

**Source**
- `source`（feed URL）、`channel`（stable / canary）、`profile`（trusted / hardened），以及一个映射到 `net_policy` 的 **Network** 选择（Wi-Fi + mobile / Wi-Fi only / mobile only）。

开关和数字字段会立即保存，并在写入失败时在视觉上回退。Source 区段中的文本和选择字段会把自己标记为脏（dirty），并在一个显式的 Save 按钮上一起保存。面板始终只重写用户触碰过的那些键，因此任何未知或将来的配置键都会被保留。

### 自动打开行为

`onWebUIOpen()` 在宿主加载时被调用。它评估日志（显示重启横幅，或为上一会话遗留的非终止事务提供 Resume），然后，如果 `auto_on_webui_open=1`，它先运行一次**静默**的 `check()`。持久的进度 toast 和实际的 `run` 只有在确有下载要做时（`update && fetch > 0`）才会触发。如果设备已是最新或领先于 feed，结果就就地显示在面板中，屏幕上不会留下任何 toast，因此自动更新与手动按钮一样不打扰。

---

## i18n（各语言字符串）

每个 UI 字符串都默认为**英文**，这是面向公开多语言模块的中立选择。完整的键映射存在于 `vdlu.js` 中的 `DEFAULT_I18N` 对象里（也作为 `VDLU.i18n` 暴露）。宿主通过把一个映射传给 `init({ i18n: ... })` 来覆盖任意键子集：

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- 一个**部分**映射也可以：任何缺失的键会回退到英文默认值。
- 阶段和状态标签使用键 `ph_<phase>` 和 `st_<STATE>`；其余是像 `cancel`、`updateNow` 这样的扁平键。
- 一个演练过的翻译（`i18n/pt-BR.js`）作为模板交付；一种新语言只是一个相同形态的 `i18n/<lang>.js` 文件，或者由宿主从它自己的 i18n 系统构建该映射。

---

## demo.html：无设备运行 UI

`demo.html` 模拟 `ksu.exec` 桥，因此完全相同的 `vdlu.js` 和 `vdlu.css` 能在普通浏览器中运行，无需 root、无需手机：

```sh
xdg-open webui/demo.html
```

该模拟会模拟 `update.sh` 和一个不断演进的 `journal.json`，其按钮在各场景之间切换：一次直到 DONE 的实时更新、一次 `reboot_pending` 结束、一次中途错误，以及一次可取消的运行。这是查看并迭代 UI 的最快方式，也是你在把小部件内嵌进一个模块之前要检查的东西。

---

## 把它接入一个模块（WebUI 打开触发器）

宿主的 `index.html` 加载这两个文件并调用三个函数：

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

宿主只需提供 Tier-2 路径并为面板分配一个空 `<div>`；toast 和横幅由小部件注入 `document.body`。`onWebUIOpen()` 是 WebUI 打开触发器：正是它评估重启横幅、在一笔被中断的事务上提供 Resume，并在设置了 `auto_on_webui_open` 时运行静默的自动更新。

### 单一源，逐字节重新内嵌

`vdlu.js` 和 `vdlu.css` 是**规范副本**。一个内嵌该小部件的模块会把这些文件原封不动地重新内嵌（re-vendor）进它的 `webroot/`；它从不就地编辑自己的副本。一个新特性诞生在规范文件中，并通过重新内嵌向下流动。编辑一个已内嵌的副本会产生悄然的漂移（这发生过：一个陈旧副本缺少 `net_policy`、DEFERRED toast 和 boot-retry 字段）。源目录树中的一个对等性守护者（parity guardian）会找到每一份副本，并标记或重新内嵌那些已偏离的副本，它只覆盖小部件；keyring 有它自己的 verify-not-copy 节奏。

---

### 公开 API（`window.VDLU`）

| 函数 | 作用 |
|---|---|
| `init(opts)` | 配置小部件；返回 `window.VDLU` |
| `onWebUIOpen()` | 在加载时调用：横幅、Resume 提供，以及静默自动更新 |
| `mountUpdatesPanel(el)` | 把 Updates 面板渲染进 `el`（id 字符串或元素） |
| `check()` | 运行 `update.sh check`；`Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | 在后台触发 `run` 外加带 Cancel 的进度 toast |
| `cancel()` | 创建 `$VDLU_DIR/cancel`（引擎在一个安全点停止） |
| `resume()` | 续传当前事务外加一个 toast |
| `refreshBanner()` | 重新评估持久的待重启横幅 |

---

另见：[[Engine]] 了解小部件驱动的命令，[[Quick Start]] 了解完整的引入步骤，以及 [[Reboot Handling]] 了解横幅在等待什么。
