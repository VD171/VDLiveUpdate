# WebUI

VDLU ships an optional drop-in WebUI widget: a small "Updates" panel for a KernelSU or APatch root-manager WebUI. It gives a user a Check button, an Update now button, a live progress toast with cancel, a reboot banner, and a settings panel, all without the user ever touching a terminal.

It is **vanilla JavaScript**: no framework, no build step, no CDN. Three files:

| File | What it is |
|---|---|
| `vdlu.js` | the widget; exposes `window.VDLU` |
| `vdlu.css` | the styles for the toast, banner and panel (dark theme, inherits the host's CSS variables) |
| `demo.html` | a standalone page that mocks the device bridge so the whole UI runs in a plain browser |

The widget is entirely optional. The [[Engine]] runs fine on its own from boot triggers; the WebUI is just a friendly face on top of it. See [[Quick Start]] for wiring it into a module.

---

## How the UI talks to the engine: the `ksu.exec` bridge

The widget never does anything privileged itself. It builds a shell command and hands it to the root manager's `ksu.exec` bridge, which runs it as root and returns stdout / stderr / exit code. Everything the panel shows is read back from files the engine writes.

The widget wraps that bridge in a single `exec(cmd)` function that returns a `Promise`:

- **resolves** with stdout when the command exits 0
- **rejects** with stderr (or `rc=N`) otherwise

Every command carries the contract's environment, assembled by the widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

A few concrete calls:

- **Start an update:** `update.sh run` is launched in the **background** (`(... &)`) so the UI is never blocked by a long download.
- **Read progress:** a light poll (about once a second) of `cat $VDLU_DIR/journal.json`.
- **Cancel:** `touch $VDLU_DIR/cancel` (the engine stops at the next safe point).
- **Config:** read and write `$VDLU_DIR/config` (key=value), preserving order and unknown keys and touching only the keys the user changed.

If the host passes its own `exec`, `toast` and `confirm` helpers to `init()`, the widget routes through the host's own serialized command queue and visuals, so it looks and behaves like the rest of that WebUI. If they are omitted, the widget falls back to calling `ksu.exec` directly and injects its own mini-toast.

---

## The progress toast (with cancel)

Once an update is running, the widget shows a non-blocking corner toast and polls `journal.json`. The toast reflects the engine's state machine:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

It renders a progress bar plus a line of `phase done/total - current file - bytes`, and carries a **Cancel** button throughout. The terminal states each get their own treatment:

- **DONE** -> a green toast, "vX applied - all verified".
- **PENDING_REBOOT** -> a green toast plus a persistent reboot banner (below).
- **ERROR** -> a red toast with the reason from `journal.error` or stderr, offering Retry. It never fakes success.
- **Cancelled** -> an amber toast, "cancelled - N/M applied, resumable", offering **Resume**.
- **DEFERRED** -> a gentle blue info toast, "download deferred, waiting for the allowed network". This is a benign network-policy wait, not an error; it resumes on the next check or boot on the right network.

The poll is defensive. A half-written journal (the engine writes concurrently) is ignored for that tick rather than mis-parsed. If the journal goes absent after progress was seen, that means the commit cleared it: the widget reports DONE. If the journal is absent from the start for 8 ticks, it reports "no response". And if the journal freezes on the same values for 20 ticks, the widget checks the engine's `lock.d`: if the lock is alive it is just a slow single-blob fetch and the toast keeps waiting; if the lock is dead the run died mid-way, so the widget surfaces an error with a Resume button instead of spinning on "updating" forever.

---

## The reboot banner

Some files cannot be swapped on a live system: a `.so`, a `/system` overlay, an `sepolicy.rule`. The engine stages those and marks the transaction `PENDING_REBOOT`. The widget then shows a **persistent top banner**: "Reboot to activate the new `.so` (vX)". It stays until the staged files are swapped at the next boot. On WebUI open the banner is re-evaluated from the journal, so a user who closes and reopens the UI still sees it. See [[Reboot Handling]] for what happens at boot.

Note the banner keys off the terminal state `PENDING_REBOOT`, not off the `reboot_pending` flag (which goes true as soon as any `.so` enters the plan). That keeps the banner from appearing mid-run before anything is actually staged.

---

## The "Updates" panel: independent per-category toggles

`mountUpdatesPanel(el)` renders the settings panel into an empty `<div>` the host provides. It has three sections, and each control is independent and saves on its own:

**Actions**
- **Check for updates** -> runs `check`, shows the result inline (up to date / newer than the feed / update available with file count and a reboot tag).
- **Update now** -> fires `run` plus the progress toast.

**Automation** (independent toggles, each written to `config` the moment it is flipped)
- **On WebUI open** (`auto_on_webui_open`) -> run a quiet update when the UI opens.
- **On reboot** (`auto_on_reboot`) -> apply in pre-zygote at boot.
- **Boot retry every (s)** and **Boot retry up to (min)** -> numeric fields for retrying a manifest fetch when the device boots offline.

**Source**
- `source` (the feed URL), `channel` (stable / canary), `profile` (trusted / hardened), and a **Network** select mapping to `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Toggles and numeric fields save immediately and revert visually if the write fails. The text and select fields in the Source section mark themselves dirty and save together on an explicit Save button. The panel only ever rewrites the keys the user touched, so any unknown or future config keys are preserved.

### Auto-open behaviour

`onWebUIOpen()` is called on host load. It evaluates the journal (showing the reboot banner or offering Resume for a non-terminal transaction left by a previous session), then, if `auto_on_webui_open=1`, it runs a **quiet** `check()` first. The persistent progress toast and the actual `run` only fire when there is a real download to do (`update && fetch > 0`). If the device is up to date or ahead of the feed, the result shows inline in the panel and no toast is left on screen, so the auto-update is as non-intrusive as the manual button.

---

## i18n (per-language strings)

Every UI string defaults to **English**, which is the neutral choice for public multi-language modules. The full key map lives in the `DEFAULT_I18N` object in `vdlu.js` (also exposed as `VDLU.i18n`). A host overrides any subset of keys by passing a map to `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- A **partial** map is fine: any missing key falls back to the English default.
- Phase and state labels use the keys `ph_<phase>` and `st_<STATE>`; the rest are flat keys like `cancel`, `updateNow`.
- A worked translation (`i18n/pt-BR.js`) ships as a template; a new language is just an `i18n/<lang>.js` file in the same shape, or the host builds the map from its own i18n system.

---

## demo.html: run the UI with no device

`demo.html` mocks the `ksu.exec` bridge so the exact same `vdlu.js` and `vdlu.css` run in a plain browser, with no root and no phone:

```sh
xdg-open webui/demo.html
```

The mock simulates `update.sh` and an evolving `journal.json`, and its buttons switch between the scenarios: a live update through to DONE, a `reboot_pending` finish, an error mid-way, and a cancellable run. It is the fastest way to see and iterate on the UI, and it is what you check before vendoring the widget into a module.

---

## Wiring it into a module (the WebUI-open trigger)

The host `index.html` loads the two files and calls three functions:

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

The host only needs to supply the Tier-2 paths and allocate one empty `<div>` for the panel; the toast and banner are injected into `document.body` by the widget. `onWebUIOpen()` is the WebUI-open trigger: it is what evaluates the reboot banner, offers Resume on an interrupted transaction, and runs the quiet auto-update when `auto_on_webui_open` is set.

### Single source, re-vendored byte for byte

`vdlu.js` and `vdlu.css` are the **canonical copy**. A module that embeds the widget re-vendors these files unchanged into its `webroot/`; it never edits its own copy in place. A new feature is born in the canonical files and flows down by re-vendor. Editing a vendored copy produces silent drift (it has happened: a stale copy was missing `net_policy`, the DEFERRED toast and the boot-retry fields). A parity guardian in the source tree finds every copy and flags or re-vendors the ones that diverge, covering the widget only; the keyring has its own verify-not-copy cadence.

---

### Public API (`window.VDLU`)

| Function | Does |
|---|---|
| `init(opts)` | configure the widget; returns `window.VDLU` |
| `onWebUIOpen()` | call on load: banner, Resume offer, and quiet auto-update |
| `mountUpdatesPanel(el)` | render the Updates panel into `el` (id string or element) |
| `check()` | run `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | fire `run` in the background plus the progress toast with Cancel |
| `cancel()` | create `$VDLU_DIR/cancel` (engine stops at a safe point) |
| `resume()` | resume the current transaction plus a toast |
| `refreshBanner()` | re-evaluate the persistent pending-reboot banner |

---

See also: [[Engine]] for the commands the widget drives, [[Quick Start]] for full adoption steps, and [[Reboot Handling]] for what the banner is waiting on.
