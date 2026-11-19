> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · 中文

---

# VDLU - WebUI 小部件（flashless update）

用于 KernelSU/APatch root 管理器 WebUI 的 VDLU（VD Live Update）界面。Vanilla JS，无框架、无
构建、无 CDN。即插即用：宿主的 `index.html` 加载这 2 个文件并调用 API。

收敛：`INTERFACES.md` §9（WEBUI↔ENGINE）、§4（journal.json）、§5（config）。

## 文件

| 文件 | 是什么 |
|---|---|
| `vdlu.js` | 该组件 - 暴露 `window.VDLU` |
| `vdlu.css` | 进度 toast、reboot 横幅、“Updates”标签页（暗色主题，继承宿主的变量） |
| `demo.html` | 带有一个被 mock 的 `ksu.exec` 的独立页面 - 在浏览器中打开，无需设备 |

## 集成到宿主 `index.html`

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### 宿主必须定义什么

- **`moduleDir`** = `$MODULE_DIR`（`/data/adb/modules/<modid>`），engine 被 vendor 之处
  （`vdlu/update.sh`）。
- **`vdluDir`** = `$VDLU_DIR`（`/data/adb/<modid>/vdlu`），Tier-2 状态（`journal.json`、`config`、
  `cancel`）。
- **`modid`** = 模块 id。

小部件组装已经携带契约 env 的 engine 命令（§1）：
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`。`run`/`resume` 进入
**后台**（`(… &)`），进度通过对 `cat $VDLU_DIR/journal.json` 的一次轻量轮询（~1s）读取。

### `exec`/`toast`/`confirm`（可选）

若省略，小部件使用它自己的：
- **`exec(cmd)`** 必须返回一个 `Promise`，它以 stdout **resolve**（rc 0），以 stderr **reject**
  （rc≠0）- 恰好是 Demo `webroot/index.html` 的 `ex()` 的签名。内部回退调用
  `ksu.exec(cmd, '{}', cb)`，使用相同的契约。
- **`toast(msg)`** = 一个简短的瞬时通知（回退注入它自己的 mini-toast）。
- **`confirm(title,msg,ok,danger,fn)`** = 一个 modal（今天仅宿主使用；小部件在任何流程中都不要求
  确认）。

传入宿主自己的，会让小部件通过与 WebUI 其余部分**相同**的序列化队列和视觉效果进行通信。

## 公共 API（`window.VDLU`）

| 函数 | 作用 |
|---|---|
| `init(opts)` | 配置（见上文）。返回 `window.VDLU`。 |
| `onWebUIOpen()` | 在加载时调用它：若 `reboot_pending` 则显示横幅；若存在一个非终止事务则提供 **Resume**；在 `auto_on_webui_open=1` 时它运行一个**静默的 auto-update**（先一个静默的 `check()`；仅当 `update && fetch>0` 时才触发 `run`+持久 toast - 已是最新/领先 = 面板中的内联结果，零 toast）。 |
| `mountUpdatesPanel(el)` | 在 `el`（字符串 id 或 element）内渲染“Updates”标签页：**Check for update**、**Update now**、`auto_on_webui_open`/`auto_on_reboot` 开关、boot-retry 字段、**Network** 下拉（`net_policy`：Wi-Fi+mobile / 仅 Wi-Fi / 仅 mobile）以及 `source`/`channel`/`profile` 字段。 |
| `check()` | 运行 `update.sh check`；`Promise<{update,from,to,fetch,reboot}>`。 |
| `startUpdate()` | 在后台触发 `run` + 一个带 **Cancel** 的进度 toast。 |
| `cancel()` | 创建 `$VDLU_DIR/cancel`（engine 在安全点停止）。 |
| `resume()` | `update.sh resume` + toast（恢复当前阶段）。 |
| `refreshBanner()` | 重新评估持久的 pending-reboot 横幅。 |

Toast（角落浮层，非阻塞）和横幅（顶部，持久）由小部件注入到
`document.body` - 宿主无需为它们提供 HTML。“Updates”标签页是宿主唯一分配的点（一个
空的 `<div>`）。

### toast 反映的状态流（journal.json，§4）

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`；任何时刻的 `ERROR`。
toast 显示**一个进度条 + `phase done/total · current · bytes`**。终止态：
- **`DONE`** → 绿色 toast “v&lt;target&gt; applied”。
- **`PENDING_REBOOT`**（或 `reboot_pending=true`）→ 绿色 toast + **持久横幅** “⚠️ Reboot to
  activate the new `.so` (vX)”。
- **`ERROR`** → 带原因的红色 toast（`journal.error`/stderr）。绝不伪造成功。
- **Cancelled** → “cancelled - N/M, resumable” + 一个 **Resume** 按钮。

## 运行 demo

在浏览器中打开 `demo.html`（`xdg-open webui/demo.html`）。被 mock 的 `ksu.exec` 模拟 `update.sh` 和
不断演进的 `journal.json`；这些按钮在 **LIVE→DONE**、**reboot_pending**、**error mid-way**
和 **cancellable** 场景之间切换。它与设备上的 `vdlu.js`/`vdlu.css` 相同。

## i18n（语言）

小部件字符串默认为 **English**（对公共多语言模块中性）。宿主通过在 `init` 中传入一个 map 来覆盖
任何键：

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **部分**合并即可：缺失的键回退到英语默认值。
- phase/state 键为 `ph_<phase>` / `st_<STATE>`；其余为扁平（`cancel`、`updateNow`、…）。
- 完整的键 map = `vdlu.js` 中的 `DEFAULT_I18N` 对象（也暴露为 `VDLU.i18n`）。
- 作为一个现成示例提供了一份现成翻译：`i18n/pt-BR.js`。新语言 = 一个同样模式的
  `i18n/<lang>.js` 文件，或由宿主从它自己的 i18n 系统构建该 map。

## 单一来源（模块间的一致性）

这些 `vdlu.js`/`vdlu.css` 是**规范副本**。每个嵌入该小部件的模块都
逐字节地将此副本**重新 vendor** 到它的 `webroot/` 中 - 它**从不**就地编辑
它自己的那份。小部件的一个新功能在此诞生，并通过重新 vendor 向下流动；反方向则产生悄无声息的
drift（这在实践中发生过：一份已 vendor 的副本落后了，缺少 `net_policy`、`DEFERRED`
toast 和 `boot_retry` 字段）。

守护者：[`../tools/webui-parity.sh`](../../tools/webui-parity.sh) 查找源码树中的每一份副本，并标记
那些与规范副本不一致的（仅 `vdlu.js`/`vdlu.css`；keyring 是“verify, not copy”）。

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring（`keyring/<id>.pub` RAW 32B）和 engine（`vdlu/update.sh`）有它们自己的重新 vendor
> 节奏；这个守护者仅覆盖 **WebUI 小部件**。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
