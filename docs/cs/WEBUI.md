> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · Čeština · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI widget (flashless update)

Rozhraní VDLU (VD Live Update) pro WebUI root manažerů KernelSU/APatch. Vanilla JS, žádný framework, žádný
build, žádné CDN. Drop-in: hostitelský `index.html` načte 2 soubory a volá API.

Konvergence: `INTERFACES.md` §9 (WEBUI<->ENGINE), §4 (journal.json), §5 (config).

## Soubory

| Soubor | Co |
|---|---|
| `vdlu.js` | komponenta - exponuje `window.VDLU` |
| `vdlu.css` | progress toast, reboot banner, záložka "Updates" (tmavý motiv, dědí proměnné hostitele) |
| `demo.html` | samostatná stránka s mocknutým `ksu.exec` - otevře se v prohlížeči, bez zařízení |

## Integrace do hostitelského `index.html`

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

### Co musí hostitel definovat

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), kde je engine vložený
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), stav Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id modulu.

Widget sestavi prikaz enginu uz nesouci env kontraktu (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` jdou na
**pozadí** (`(… &)`) a průběh se čte lehkým pollem (~1s) `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (volitelné)

Pokud vynecháno, widget použije své vlastní:
- **`exec(cmd)`** musí vrátit `Promise`, který se **resolvne** s stdout (rc 0) a **rejectne** s stderr
  (rc≠0) - přesně signatura `ex()` z Demo `webroot/index.html`. Interní fallback volá
  `ksu.exec(cmd, '{}', cb)` se stejným kontraktem.
- **`toast(msg)`** = krátké přechodné oznámení (fallback vstřikuje vlastní mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = modal (dnes používaný jen hostitelem; widget nevyžaduje v žádném toku žádné
  potvrzení).

Předání hostitelových vlastních nechá widget mluvit skrze STEJNOU serializovanou frontu a vizuály jako zbytek
WebUI.

## Veřejné API (`window.VDLU`)

| Funkce | Dělá |
|---|---|
| `init(opts)` | konfiguruje (viz výše). Vrací `window.VDLU`. |
| `onWebUIOpen()` | volej při načtení: zobrazí banner pokud `reboot_pending`; nabídne **Resume** pokud existuje nefinální transakce; s `auto_on_webui_open=1` spustí **TICHÝ auto-update** (nejprve tichý `check()`; `run`+trvalý toast spustí jen pokud `update && fetch>0` - aktuální/napřed = inline výsledek v panelu, žádný toast). |
| `mountUpdatesPanel(el)` | renderuje záložku "Updates" uvnitř `el` (string id nebo element): **Check for update**, **Update now**, toggly `auto_on_webui_open`/`auto_on_reboot`, pole boot-retry, select **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) a pole `source`/`channel`/`profile`. |
| `check()` | spustí `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | spustí `run` na pozadí + progress toast s **Cancel**. |
| `cancel()` | vytvoří `$VDLU_DIR/cancel` (engine se zastaví v bezpečném bodě). |
| `resume()` | `update.sh resume` + toast (obnoví aktuální fázi). |
| `refreshBanner()` | znovu vyhodnotí trvalý pending-reboot banner. |

Toast (rohový overlay, neblokující) a banner (nahoře, trvalý) vstřikuje widget do
`document.body` - hostitel pro ně nepotřebuje žádné HTML. Záložka "Updates" je jediný bod, který hostitel alokuje (prázdný
`<div>`).

### Tok stavu, který toast odráží (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` kdykoli.
Toast zobrazuje **lištu + `phase done/total · current · bytes`**. Finály:
- **`DONE`** → zelený toast "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (nebo `reboot_pending=true`) → zelený toast + **trvalý banner** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → červený toast s důvodem (`journal.error`/stderr). Nikdy nepředstírá úspěch.
- **Cancelled** → "cancelled - N/M, resumable" + tlačítko **Resume**.

## Spuštění demo

Otevři `demo.html` v prohlížeči (`xdg-open webui/demo.html`). Mocknuté `ksu.exec` simuluje `update.sh` a
vyvíjející se `journal.json`; tlačítka přepínají mezi scénáři **LIVE→DONE**, **reboot_pending**, **error mid-way**
a **cancellable**. Je to stejné `vdlu.js`/`vdlu.css` jako na zařízení.

## i18n (jazyk)

Řetězce widgetu jsou výchozí **anglicky** (neutrální pro veřejné vícejazyčné moduly). Hostitel přepíše
jakýkoli klíč předáním mapy v `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Částečný** merge je v pořádku: chybějící klíč spadne zpět na anglický výchozí.
- Klíče fáze/stavu jsou `ph_<phase>` / `st_<STATE>`; zbytek je plochý (`cancel`, `updateNow`, …).
- Úplná mapa klíčů = objekt `DEFAULT_I18N` v `vdlu.js` (také exponovaný jako `VDLU.i18n`).
- Hotový překlad je poskytnut jako zpracovaný příklad: `i18n/pt-BR.js`. Nové jazyky = soubor
  `i18n/<lang>.js` ve stejné formě, nebo hostitel sestaví mapu z vlastního i18n systému.

## Jediný zdroj (parita napříč moduly)

Tyto `vdlu.js`/`vdlu.css` jsou **kanonická kopie**. Každý modul, který widget vkládá,
**re-vendoruje** tuto kopii bajt po bajtu do svého `webroot/` - **nikdy** needituje
svou vlastní na místě. Nová featura widgetu se rodí zde a teče dolů re-vendorem; opačný směr plodí tichý
drift (stalo se to v praxi: vložená kopie zaostala a chyběl jí `net_policy`, `DEFERRED`
toast a pole `boot_retry`).

Strážce: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) najde každou kopii ve zdrojovém stromu a označí
ty, které se odchylují od kanonické (jen `vdlu.js`/`vdlu.css`; keyring je "ověřit, ne kopírovat").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) a engine (`vdlu/update.sh`) mají vlastní kadenci
> re-vendoru; tento strážce pokrývá **jen** WebUI widget.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
