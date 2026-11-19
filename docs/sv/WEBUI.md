> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · Svenska · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI-widget (flashless uppdatering)

VDLU-gränssnittet (VD Live Update) för en KernelSU/APatch root-manager-WebUI. Vanilla JS, inget ramverk, ingen
build, ingen CDN. Drop-in: värdens `index.html` laddar de 2 filerna och anropar API:et.

Konvergens: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Filer

| Fil | Vad |
|---|---|
| `vdlu.js` | komponenten - exponerar `window.VDLU` |
| `vdlu.css` | förloppstoast, reboot-banner, "Updates"-flik (mörkt tema, ärver värdens variabler) |
| `demo.html` | fristående sida med en mockad `ksu.exec` - öppnas i en webbläsare, ingen enhet |

## Integration i värdens `index.html`

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

### Vad värden måste definiera

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), där motorn är vendorad
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), Tier-2-tillståndet (`journal.json`, `config`,
  `cancel`).
- **`modid`** = modulens id.

Widgeten sätter samman motorkommandot som redan bär kontraktets env (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` går till
**bakgrunden** (`(… &)`), och förlopp läses av en lätt poll (~1 s) av `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (valfritt)

Om de utelämnas använder widgeten sina egna:
- **`exec(cmd)`** måste returnera ett `Promise` som **resolvar** med stdout (rc 0) och **rejectar** med stderr
  (rc≠0) - exakt signaturen för Demons `webroot/index.html`:s `ex()`. Den interna reservlösningen anropar
  `ksu.exec(cmd, '{}', cb)` med samma kontrakt.
- **`toast(msg)`** = en kort övergående notis (reservlösningen injicerar sin egen minitoast).
- **`confirm(title,msg,ok,danger,fn)`** = en modal (idag använd endast av värden; widgeten kräver ingen
  bekräftelse i något flöde).

Att skicka in värdens egna gör att widgeten pratar genom SAMMA serialiserade kö och visuals som resten av
WebUI:et.

## Publikt API (`window.VDLU`)

| Funktion | Gör |
|---|---|
| `init(opts)` | konfigurerar (se ovan). Returnerar `window.VDLU`. |
| `onWebUIOpen()` | anropa det vid laddning: visar bannern om `reboot_pending`; erbjuder **Resume** om det finns en icke-terminal transaktion; med `auto_on_webui_open=1` kör den en **TYST autouppdatering** (en tyst `check()` först; avfyrar `run`+beständig toast endast om `update && fetch>0` - aktuell/före = inline-resultat i panelen, noll toast). |
| `mountUpdatesPanel(el)` | renderar "Updates"-fliken inuti `el` (sträng-id eller element): **Check for update**, **Update now**, `auto_on_webui_open`/`auto_on_reboot`-togglarna, boot-retry-fälten, **Network**-väljaren (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) och `source`/`channel`/`profile`-fälten. |
| `check()` | kör `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | avfyrar `run` i bakgrunden + en förloppstoast med **Cancel**. |
| `cancel()` | skapar `$VDLU_DIR/cancel` (motorn stoppar vid den säkra punkten). |
| `resume()` | `update.sh resume` + toast (återupptar den aktuella fasen). |
| `refreshBanner()` | omvärderar den beständiga pending-reboot-bannern. |

Toasten (hörnoverlay, icke-blockerande) och bannern (topp, beständig) injiceras av widgeten i
`document.body` - värden behöver ingen HTML för dem. "Updates"-fliken är den enda punkt värden allokerar (en
tom `<div>`).

### Tillståndsflödet som toasten återspeglar (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` när som helst. Toasten
visar **en stapel + `phase done/total · current · bytes`**. Terminaler:
- **`DONE`** → grön toast "v&lt;target&gt; tillämpad".
- **`PENDING_REBOOT`** (eller `reboot_pending=true`) → grön toast + **beständig banner** "⚠️ Starta om för att
  aktivera den nya `.so` (vX)".
- **`ERROR`** → röd toast med orsaken (`journal.error`/stderr). Fejkar aldrig framgång.
- **Cancelled** → "avbruten - N/M, återupptagbar" + en **Resume**-knapp.

## Köra demon

Öppna `demo.html` i en webbläsare (`xdg-open webui/demo.html`). Den mockade `ksu.exec` simulerar `update.sh` och
`journal.json` som utvecklas; knapparna växlar mellan scenarierna **LIVE→DONE**, **reboot_pending**, **error mid-way**
och **cancellable**. Det är samma `vdlu.js`/`vdlu.css` som på enheten.

## i18n (språk)

Widgetsträngarna är som standard **engelska** (neutralt för de publika flerspråkiga modulerna). Värden åsidosätter
valfri nyckel genom att skicka en map i `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- En **partiell** sammanslagning är okej: en saknad nyckel faller tillbaka på den engelska standarden.
- Fas-/tillståndsnycklar är `ph_<phase>` / `st_<STATE>`; resten är platt (`cancel`, `updateNow`, …).
- Den fullständiga nyckel-mappen = `DEFAULT_I18N`-objektet i `vdlu.js` (exponeras även som `VDLU.i18n`).
- En färdig översättning tillhandahålls som ett utarbetat exempel: `i18n/pt-BR.js`. Nya språk = en
  `i18n/<lang>.js`-fil i samma form, eller så bygger värden mappen från sitt eget i18n-system.

## Enda källa (paritet över moduler)

Dessa `vdlu.js`/`vdlu.css` är den **kanoniska kopian**. Varje modul som bäddar in widgeten
**om-vendorar** den här kopian byte för byte till sin `webroot/` - den redigerar **aldrig**
sin egen på plats. En ny widgetfunktion föds här och flödar nedåt genom om-vendoring; det omvända producerar tyst
drift (det har hänt i praktiken: en vendorad kopia hamnade på efterkälken och saknade `net_policy`, `DEFERRED`-
toasten och `boot_retry`-fälten).

Väktare: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) hittar varje kopia i källträdet och flaggar
dem som avviker från den kanoniska (endast `vdlu.js`/`vdlu.css`; keyringen är "verifiera, inte kopiera").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyringen (`keyring/<id>.pub` RAW 32B) och motorn (`vdlu/update.sh`) har sin egen om-vendorings-
> kadens; den här väktaren täcker **endast** WebUI-widgeten.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas; se [CONTRIBUTING.md](CONTRIBUTING.md)._
