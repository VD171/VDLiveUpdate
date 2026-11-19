> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · Nederlands · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI-widget (flashless update)

De VDLU-interface (VD Live Update) voor een KernelSU/APatch root-manager-WebUI. Vanilla JS, geen framework, geen
build, geen CDN. Drop-in: de host-`index.html` laadt de 2 bestanden en roept de API aan.

Convergentie: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Bestanden

| Bestand | Wat |
|---|---|
| `vdlu.js` | de component - exposeert `window.VDLU` |
| `vdlu.css` | voortgangstoast, reboot-banner, "Updates"-tabblad (donker thema, erft de variabelen van de host) |
| `demo.html` | standalone pagina met een gemockte `ksu.exec` - opent in een browser, geen toestel |

## Integratie in de host-`index.html`

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

### Wat de host moet definiëren

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), waar de engine mee-geleverd is
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), de Tier-2-toestand (`journal.json`, `config`,
  `cancel`).
- **`modid`** = de module-id.

De widget stelt het engine-commando samen dat al de env van het contract (§1) draagt:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` gaan naar de
**achtergrond** (`(… &)`), en de voortgang wordt gelezen door een lichte poll (~1s) van `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (optioneel)

Indien weggelaten gebruikt de widget zijn eigen:
- **`exec(cmd)`** moet een `Promise` teruggeven die **resolvet** met stdout (rc 0) en **rejectet** met stderr
  (rc≠0) - exact de signatuur van de `ex()` van de Demo-`webroot/index.html`. De interne fallback roept
  `ksu.exec(cmd, '{}', cb)` aan met hetzelfde contract.
- **`toast(msg)`** = een korte voorbijgaande notificatie (de fallback injecteert zijn eigen mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = een modaal (vandaag alleen door de host gebruikt; de widget vereist geen
  bevestiging in enige flow).

Je eigen host-functies doorgeven laat de widget praten via DEZELFDE geserialiseerde wachtrij en visuals als de rest van de
WebUI.

## Publieke API (`window.VDLU`)

| Functie | Doet |
|---|---|
| `init(opts)` | configureert (zie boven). Geeft `window.VDLU` terug. |
| `onWebUIOpen()` | roep het aan bij load: toont de banner als `reboot_pending`; biedt **Resume** aan als er een niet-terminale transactie is; met `auto_on_webui_open=1` draait het een **STILLE auto-update** (eerst een stille `check()`; vuurt alleen `run`+persistente toast af als `update && fetch>0` - up-to-date/ahead = inline resultaat in het paneel, nul toast). |
| `mountUpdatesPanel(el)` | rendert het "Updates"-tabblad binnen `el` (string-id of element): **Check for update**, **Update now**, de `auto_on_webui_open`/`auto_on_reboot`-toggles, de boot-retry-velden, de **Network**-select (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) en de `source`/`channel`/`profile`-velden. |
| `check()` | draait `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | vuurt `run` af op de achtergrond + een voortgangstoast met **Cancel**. |
| `cancel()` | maakt `$VDLU_DIR/cancel` aan (de engine stopt op het veilige punt). |
| `resume()` | `update.sh resume` + toast (hervat de huidige fase). |
| `refreshBanner()` | herevalueert de persistente pending-reboot-banner. |

De toast (hoekoverlay, niet-blokkerend) en de banner (boven, persistent) worden door de widget geïnjecteerd in
`document.body` - de host heeft er geen HTML voor nodig. Het "Updates"-tabblad is het enige punt dat de host alloceert (een
leeg `<div>`).

### De toestandsflow die de toast weergeeft (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` op elk moment. De
toast toont **een balk + `phase done/total · current · bytes`**. Terminalen:
- **`DONE`** → groene toast "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (of `reboot_pending=true`) → groene toast + **persistente banner** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → rode toast met de reden (`journal.error`/stderr). Veinst nooit succes.
- **Cancelled** → "cancelled - N/M, resumable" + een **Resume**-knop.

## De demo draaien

Open `demo.html` in een browser (`xdg-open webui/demo.html`). De gemockte `ksu.exec` simuleert `update.sh` en
`journal.json` die evolueren; de knoppen schakelen tussen de scenario's **LIVE→DONE**, **reboot_pending**, **error mid-way**
en **cancellable**. Het is dezelfde `vdlu.js`/`vdlu.css` als op het toestel.

## i18n (taal)

De widget-strings staan standaard op **Engels** (neutraal voor de publieke meertalige modules). De host overschrijft
elke sleutel door een map door te geven in `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Een **gedeeltelijke** merge is prima: een ontbrekende sleutel valt terug op de Engelse standaard.
- Fase-/toestandssleutels zijn `ph_<phase>` / `st_<STATE>`; de rest is vlak (`cancel`, `updateNow`, …).
- De volledige sleutelmap = het `DEFAULT_I18N`-object in `vdlu.js` (ook geëxposeerd als `VDLU.i18n`).
- Een kant-en-klare vertaling wordt geleverd als uitgewerkt voorbeeld: `i18n/pt-BR.js`. Nieuwe talen = een
  `i18n/<lang>.js`-bestand in dezelfde mal, of de host bouwt de map uit zijn eigen i18n-systeem.

## Enkele bron (pariteit over modules heen)

Deze `vdlu.js`/`vdlu.css` zijn de **canonieke kopie**. Elke module die de widget inbedt
**her-vendort** deze kopie byte-voor-byte in zijn `webroot/` - hij bewerkt zijn eigen exemplaar **nooit**
ter plekke. Een nieuwe widget-feature wordt hier geboren en stroomt neerwaarts via her-vendoring; het omgekeerde produceert stille
drift (het is in de praktijk gebeurd: een mee-geleverde kopie raakte achterop en miste `net_policy`, de `DEFERRED`-
toast en de `boot_retry`-velden).

Bewaker: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) vindt elke kopie in de bronboom en markeert
degene die afwijken van de canonieke (alleen `vdlu.js`/`vdlu.css`; de keyring is "verifieer, niet kopiëren").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 De keyring (`keyring/<id>.pub` RAW 32B) en de engine (`vdlu/update.sh`) hebben hun eigen her-vendor-
> cadans; deze bewaker dekt **alleen de WebUI-widget**.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom; zie [CONTRIBUTING.md](CONTRIBUTING.md)._
