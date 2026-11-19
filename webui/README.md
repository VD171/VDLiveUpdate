# VDLU - WebUI widget (flashless update)

The VDLU (VD Live Update) interface for a KernelSU/APatch root manager WebUI. Vanilla JS, no framework, no
build, no CDN. Drop-in: the host `index.html` loads the 2 files and calls the API.

Convergence: `../INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Files

| File | What |
|---|---|
| `vdlu.js` | the component - exposes `window.VDLU` |
| `vdlu.css` | progress toast, reboot banner, "Updates" tab (dark theme, inherits the host's variables) |
| `demo.html` | standalone page with a mocked `ksu.exec` - opens in a browser, no device |

## Integration into the host `index.html`

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

### What the host must define

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), where the engine is vendored
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), the Tier-2 state (`journal.json`, `config`,
  `cancel`).
- **`modid`** = the module id.

The widget assembles the engine command already carrying the contract's env (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` go to the
**background** (`(… &)`), and progress is read by a light poll (~1s) of `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (optional)

If omitted, the widget uses its own:
- **`exec(cmd)`** must return a `Promise` that **resolves** with stdout (rc 0) and **rejects** with stderr
  (rc≠0) - exactly the signature of the Demo `webroot/index.html`'s `ex()`. The internal fallback calls
  `ksu.exec(cmd, '{}', cb)` with the same contract.
- **`toast(msg)`** = a short transient notification (the fallback injects its own mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = a modal (today used only by the host; the widget requires no
  confirmation in any flow).

Passing the host's own makes the widget talk through the SAME serialized queue and visuals as the rest of the
WebUI.

## Public API (`window.VDLU`)

| Function | Does |
|---|---|
| `init(opts)` | configures (see above). Returns `window.VDLU`. |
| `onWebUIOpen()` | call it on load: shows the banner if `reboot_pending`; offers **Resume** if there is a non-terminal transaction; with `auto_on_webui_open=1` it runs a **QUIET auto-update** (a silent `check()` first; only fires `run`+persistent toast if `update && fetch>0` - up-to-date/ahead = inline result in the panel, zero toast). |
| `mountUpdatesPanel(el)` | renders the "Updates" tab inside `el` (string id or element): **Check for update**, **Update now**, the `auto_on_webui_open`/`auto_on_reboot` toggles, the boot-retry fields, the **Network** select (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) and the `source`/`channel`/`profile` fields. |
| `check()` | runs `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | fires `run` in the background + a progress toast with **Cancel**. |
| `cancel()` | creates `$VDLU_DIR/cancel` (the engine stops at the safe point). |
| `resume()` | `update.sh resume` + toast (resumes the current phase). |
| `refreshBanner()` | re-evaluates the persistent pending-reboot banner. |

The toast (corner overlay, non-blocking) and the banner (top, persistent) are injected by the widget into
`document.body` - the host needs no HTML for them. The "Updates" tab is the only point the host allocates (an
empty `<div>`).

### The state flow the toast reflects (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` at any moment. The
toast shows **a bar + `phase done/total · current · bytes`**. Terminals:
- **`DONE`** → green toast "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (or `reboot_pending=true`) → green toast + **persistent banner** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → red toast with the reason (`journal.error`/stderr). Never fakes success.
- **Cancelled** → "cancelled - N/M, resumable" + a **Resume** button.

## Running the demo

Open `demo.html` in a browser (`xdg-open webui/demo.html`). The mocked `ksu.exec` simulates `update.sh` and
`journal.json` evolving; the buttons switch between the **LIVE→DONE**, **reboot_pending**, **error mid-way**
and **cancellable** scenarios. It is the same `vdlu.js`/`vdlu.css` as on the device.

## i18n (language)

The widget strings default to **English** (neutral for the public multi-language modules). The host overrides
any key by passing a map in `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- A **partial** merge is fine: a missing key falls back to the English default.
- Phase/state keys are `ph_<phase>` / `st_<STATE>`; the rest is flat (`cancel`, `updateNow`, …).
- The full key map = the `DEFAULT_I18N` object in `vdlu.js` (also exposed as `VDLU.i18n`).
- A ready translation is provided as a worked example: `i18n/pt-BR.js`. New languages = an
  `i18n/<lang>.js` file in the same mold, or the host builds the map from its own i18n system.

## Single source (parity across modules)

These `vdlu.js`/`vdlu.css` are the **canonical copy**. Every module that embeds the widget
**re-vendors** this copy byte-for-byte into its `webroot/` - it **never** edits
its own in place. A new widget feature is born here and flows down by re-vendor; the reverse produces silent
drift (it has happened in practice: a vendored copy fell behind and was missing `net_policy`, the `DEFERRED`
toast and the `boot_retry` fields).

Guardian: [`../tools/webui-parity.sh`](../tools/webui-parity.sh) finds every copy in the source tree and flags
those that diverge from the canonical one (only `vdlu.js`/`vdlu.css`; the keyring is "verify, not copy").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 The keyring (`keyring/<id>.pub` RAW 32B) and the engine (`vdlu/update.sh`) have their own re-vendor
> cadence; this guardian covers **only the WebUI widget**.

---
_Generated with Claude._
