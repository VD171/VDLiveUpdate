> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · Čeština · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI widget (flashless update)

Rozhrani VDLU (VD Live Update) pro WebUI root manazeru KernelSU/APatch. Vanilla JS, zadny framework, zadny
build, zadne CDN. Drop-in: hostitelsky `index.html` nacte 2 soubory a vola API.

Konvergence: `INTERFACES.md` §9 (WEBUI<->ENGINE), §4 (journal.json), §5 (config).

## Soubory

| Soubor | Co |
|---|---|
| `vdlu.js` | komponenta - exponuje `window.VDLU` |
| `vdlu.css` | progress toast, reboot banner, zalozka "Updates" (tmavy motiv, dedi promenne hostitele) |
| `demo.html` | samostatna stranka s mocknutym `ksu.exec` - otevre se v prohlizeci, bez zarizeni |

## Integrace do hostitelskeho `index.html`

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

### Co musi hostitel definovat

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), kde je engine vlozeny
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), stav Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id modulu.

Widget sestavi prikaz enginu uz nesouci env kontraktu (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` jdou na
**pozadi** (`(… &)`) a prubeh se cte lehkym pollem (~1s) `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (volitelne)

Pokud vynechano, widget pouzije sve vlastni:
- **`exec(cmd)`** musi vratit `Promise`, ktery se **resolvne** s stdout (rc 0) a **rejectne** s stderr
  (rc≠0) - presne signatura `ex()` z Demo `webroot/index.html`. Interni fallback vola
  `ksu.exec(cmd, '{}', cb)` se stejnym kontraktem.
- **`toast(msg)`** = kratke prechodne oznameni (fallback vstrikuje vlastni mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = modal (dnes pouzivany jen hostitelem; widget nevyzaduje v zadnem toku zadne
  potvrzeni).

Predani hostitelovych vlastnich necha widget mluvit skrze STEJNOU serializovanou frontu a vizualy jako zbytek
WebUI.

## Verejne API (`window.VDLU`)

| Funkce | Dela |
|---|---|
| `init(opts)` | konfiguruje (viz vyse). Vraci `window.VDLU`. |
| `onWebUIOpen()` | volej pri nacteni: zobrazi banner pokud `reboot_pending`; nabidne **Resume** pokud existuje nefinalni transakce; s `auto_on_webui_open=1` spusti **TICHY auto-update** (nejprve tichy `check()`; `run`+trvaly toast spusti jen pokud `update && fetch>0` - aktualni/napred = inline vysledek v panelu, zadny toast). |
| `mountUpdatesPanel(el)` | renderuje zalozku "Updates" uvnitr `el` (string id nebo element): **Check for update**, **Update now**, toggly `auto_on_webui_open`/`auto_on_reboot`, pole boot-retry, select **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) a pole `source`/`channel`/`profile`. |
| `check()` | spusti `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | spusti `run` na pozadi + progress toast s **Cancel**. |
| `cancel()` | vytvori `$VDLU_DIR/cancel` (engine se zastavi v bezpecnem bode). |
| `resume()` | `update.sh resume` + toast (obnovi aktualni fazi). |
| `refreshBanner()` | znovu vyhodnoti trvaly pending-reboot banner. |

Toast (rohovy overlay, neblokujici) a banner (nahore, trvaly) vstrikuje widget do
`document.body` - hostitel pro ne nepotrebuje zadne HTML. Zalozka "Updates" je jediny bod, ktery hostitel alokuje (prazdny
`<div>`).

### Tok stavu, ktery toast odrazi (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` kdykoli.
Toast zobrazuje **listu + `phase done/total · current · bytes`**. Finaly:
- **`DONE`** → zeleny toast "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (nebo `reboot_pending=true`) → zeleny toast + **trvaly banner** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → cerveny toast s duvodem (`journal.error`/stderr). Nikdy nepredstira uspech.
- **Cancelled** → "cancelled - N/M, resumable" + tlacitko **Resume**.

## Spusteni demo

Otevri `demo.html` v prohlizeci (`xdg-open webui/demo.html`). Mocknute `ksu.exec` simuluje `update.sh` a
vyvijejici se `journal.json`; tlacitka prepinaji mezi scenari **LIVE→DONE**, **reboot_pending**, **error mid-way**
a **cancellable**. Je to stejne `vdlu.js`/`vdlu.css` jako na zarizeni.

## i18n (jazyk)

Retezce widgetu jsou vychozi **anglicky** (neutralni pro verejne vicejazycne moduly). Hostitel prepise
jakykoli klic predanim mapy v `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Castecny** merge je v poradku: chybejici klic spadne zpet na anglicky vychozi.
- Klice faze/stavu jsou `ph_<phase>` / `st_<STATE>`; zbytek je plochy (`cancel`, `updateNow`, …).
- Uplna mapa klicu = objekt `DEFAULT_I18N` v `vdlu.js` (take exponovany jako `VDLU.i18n`).
- Hotovy preklad je poskytnut jako zpracovany priklad: `i18n/pt-BR.js`. Nove jazyky = soubor
  `i18n/<lang>.js` ve stejne forme, nebo hostitel sestavi mapu z vlastniho i18n systemu.

## Jediny zdroj (parita napric moduly)

Tyto `vdlu.js`/`vdlu.css` jsou **kanonicka kopie**. Kazdy modul, ktery widget vklada,
**re-vendoruje** tuto kopii bajt po bajtu do sveho `webroot/` - **nikdy** needituje
svou vlastni na miste. Nova featura widgetu se rodi zde a tece dolu re-vendorem; opacny smer plodi tichy
drift (stalo se to v praxi: vlozena kopie zaostala a chybel ji `net_policy`, `DEFERRED`
toast a pole `boot_retry`).

Strazce: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) najde kazdou kopii ve zdrojovem stromu a oznaci
ty, ktere se odchyluji od kanonicke (jen `vdlu.js`/`vdlu.css`; keyring je "overit, ne kopirovat").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) a engine (`vdlu/update.sh`) maji vlastni kadenci
> re-vendoru; tento strazce pokryva **jen** WebUI widget.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
