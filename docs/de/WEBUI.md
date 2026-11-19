> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · Deutsch · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI-Widget (flashloses Update)

Die VDLU-(VD Live Update-)Oberflaeche fuer eine KernelSU/APatch-Root-Manager-WebUI. Vanilla JS, kein Framework, kein
Build, kein CDN. Drop-in: das Host-`index.html` laedt die 2 Dateien und ruft die API auf.

Konvergenz: `INTERFACES.md` §9 (WEBUI<->ENGINE), §4 (journal.json), §5 (config).

## Dateien

| Datei | Was |
|---|---|
| `vdlu.js` | die Komponente - exponiert `window.VDLU` |
| `vdlu.css` | Fortschritts-Toast, Reboot-Banner, "Updates"-Tab (Dark Theme, erbt die Variablen des Hosts) |
| `demo.html` | eigenstaendige Seite mit einem gemockten `ksu.exec` - oeffnet in einem Browser, kein Geraet |

## Integration in das Host-`index.html`

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

### Was der Host definieren muss

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), wo die Engine eingebettet ist
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), der Tier-2-State (`journal.json`, `config`,
  `cancel`).
- **`modid`** = die Modul-ID.

Das Widget baut den Engine-Befehl zusammen, der bereits die env des Vertrags traegt (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` gehen in den
**Hintergrund** (`(… &)`), und der Fortschritt wird durch einen leichten Poll (~1s) von `cat $VDLU_DIR/journal.json` gelesen.

### `exec`/`toast`/`confirm` (optional)

Falls weggelassen, verwendet das Widget seine eigenen:
- **`exec(cmd)`** muss ein `Promise` zurueckgeben, das mit stdout **aufloest** (rc 0) und mit stderr **ablehnt**
  (rc≠0) - genau die Signatur des `ex()` von `webroot/index.html` der Demo. Der interne Fallback ruft
  `ksu.exec(cmd, '{}', cb)` mit demselben Vertrag auf.
- **`toast(msg)`** = eine kurze fluechtige Benachrichtigung (der Fallback injiziert seinen eigenen Mini-Toast).
- **`confirm(title,msg,ok,danger,fn)`** = ein Modal (heute nur vom Host verwendet; das Widget verlangt in keinem Flow eine
  Bestaetigung).

Die eigenen des Hosts zu uebergeben laesst das Widget durch dieselbe serialisierte Queue und Optik wie der Rest der
WebUI sprechen.

## Oeffentliche API (`window.VDLU`)

| Funktion | Tut |
|---|---|
| `init(opts)` | konfiguriert (siehe oben). Gibt `window.VDLU` zurueck. |
| `onWebUIOpen()` | beim Laden aufrufen: zeigt das Banner, wenn `reboot_pending`; bietet **Resume** an, wenn es eine nicht-terminale Transaktion gibt; mit `auto_on_webui_open=1` fuehrt es ein **STILLES Auto-Update** aus (zuerst ein lautloser `check()`; feuert `run`+persistenten Toast nur, wenn `update && fetch>0` - aktuell/voraus = Inline-Ergebnis im Panel, kein Toast). |
| `mountUpdatesPanel(el)` | rendert den "Updates"-Tab innerhalb `el` (String-ID oder Element): **Check for update**, **Update now**, die `auto_on_webui_open`/`auto_on_reboot`-Toggles, die Boot-Retry-Felder, das **Network**-Select (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) und die `source`/`channel`/`profile`-Felder. |
| `check()` | fuehrt `update.sh check` aus; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | feuert `run` im Hintergrund + einen Fortschritts-Toast mit **Cancel**. |
| `cancel()` | erzeugt `$VDLU_DIR/cancel` (die Engine stoppt am sicheren Punkt). |
| `resume()` | `update.sh resume` + Toast (nimmt die aktuelle Phase wieder auf). |
| `refreshBanner()` | re-evaluiert das persistente Pending-Reboot-Banner. |

Der Toast (Ecken-Overlay, nicht-blockierend) und das Banner (oben, persistent) werden vom Widget in
`document.body` injiziert - der Host braucht kein HTML dafuer. Der "Updates"-Tab ist der einzige Punkt, den der Host zuteilt (ein
leeres `<div>`).

### Der Zustandsfluss, den der Toast widerspiegelt (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` jederzeit. Der
Toast zeigt **einen Balken + `phase done/total · current · bytes`**. Terminale:
- **`DONE`** → gruener Toast "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (oder `reboot_pending=true`) → gruener Toast + **persistentes Banner** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → roter Toast mit dem Grund (`journal.error`/stderr). Taeuscht nie Erfolg vor.
- **Cancelled** → "cancelled - N/M, resumable" + ein **Resume**-Button.

## Die Demo ausfuehren

Oeffne `demo.html` in einem Browser (`xdg-open webui/demo.html`). Das gemockte `ksu.exec` simuliert `update.sh` und
`journal.json`, die sich entwickeln; die Buttons schalten zwischen den Szenarien **LIVE→DONE**, **reboot_pending**, **error mid-way**
und **cancellable** um. Es ist das gleiche `vdlu.js`/`vdlu.css` wie auf dem Geraet.

## i18n (Sprache)

Die Widget-Strings sind standardmaessig **Englisch** (neutral fuer die oeffentlichen mehrsprachigen Module). Der Host ueberschreibt
jeden Schluessel, indem er eine Map in `init` uebergibt:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Ein **partielles** Merge ist in Ordnung: ein fehlender Schluessel faellt auf den englischen Standard zurueck.
- Phase-/State-Schluessel sind `ph_<phase>` / `st_<STATE>`; der Rest ist flach (`cancel`, `updateNow`, …).
- Die vollstaendige Schluessel-Map = das `DEFAULT_I18N`-Objekt in `vdlu.js` (auch als `VDLU.i18n` exponiert).
- Eine fertige Uebersetzung wird als ausgearbeitetes Beispiel bereitgestellt: `i18n/pt-BR.js`. Neue Sprachen = eine
  `i18n/<lang>.js`-Datei in der gleichen Form, oder der Host baut die Map aus seinem eigenen i18n-System.

## Einzige Quelle (Paritaet ueber Module hinweg)

Diese `vdlu.js`/`vdlu.css` sind die **kanonische Kopie**. Jedes Modul, das das Widget einbettet,
**re-vendored** diese Kopie Byte fuer Byte in sein `webroot/` - es **editiert** seine eigene niemals an Ort und Stelle.
Ein neues Widget-Feature wird hier geboren und fliesst per Re-Vendor nach unten; der umgekehrte Weg erzeugt stillen
Drift (es ist in der Praxis passiert: eine eingebettete Kopie fiel zurueck und es fehlten `net_policy`, der `DEFERRED`-
Toast und die `boot_retry`-Felder).

Waechter: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) findet jede Kopie im Quellbaum und flaggt
die, die von der kanonischen abweichen (nur `vdlu.js`/`vdlu.css`; das Keyring ist "verifizieren, nicht kopieren").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Das Keyring (`keyring/<id>.pub` RAW 32B) und die Engine (`vdlu/update.sh`) haben ihre eigene Re-Vendor-
> Kadenz; dieser Waechter deckt **nur** das WebUI-Widget ab.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen; siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
