> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · Italiano · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (aggiornamento flashless)

L'interfaccia VDLU (VD Live Update) per una WebUI di root manager KernelSU/APatch. Vanilla JS, nessun framework, nessuna
build, nessun CDN. Drop-in: l'`index.html` host carica i 2 file e chiama l'API.

Convergenza: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## File

| File | Cosa |
|---|---|
| `vdlu.js` | il componente - espone `window.VDLU` |
| `vdlu.css` | toast di progresso, banner di reboot, scheda "Updates" (tema scuro, eredita le variabili dell'host) |
| `demo.html` | pagina standalone con un `ksu.exec` mockato - si apre in un browser, senza dispositivo |

## Integrazione nell'`index.html` host

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

### Cosa deve definire l'host

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), dove l'engine è vendorizzato
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), lo stato Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = l'id del modulo.

Il widget assembla il comando dell'engine già portando l'env del contratto (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` vanno in
**background** (`(… &)`), e il progresso viene letto da un poll leggero (~1s) di `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (opzionali)

Se omessi, il widget usa i propri:
- **`exec(cmd)`** deve restituire una `Promise` che **si risolve** con stdout (rc 0) e **viene rigettata** con stderr
  (rc≠0) - esattamente la firma dell'`ex()` del `webroot/index.html` del Demo. Il fallback interno chiama
  `ksu.exec(cmd, '{}', cb)` con lo stesso contratto.
- **`toast(msg)`** = una breve notifica transiente (il fallback inietta il proprio mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = una modale (oggi usata solo dall'host; il widget non richiede alcuna
  conferma in nessun flusso).

Passare quelli dell'host fa parlare il widget attraverso la STESSA coda serializzata e gli stessi visual del resto della
WebUI.

## API pubblica (`window.VDLU`)

| Funzione | Fa |
|---|---|
| `init(opts)` | configura (vedi sopra). Restituisce `window.VDLU`. |
| `onWebUIOpen()` | chiamala al caricamento: mostra il banner se `reboot_pending`; offre **Resume** se c'è una transazione non terminale; con `auto_on_webui_open=1` esegue un **auto-aggiornamento SILENZIOSO** (prima un `check()` silenzioso; lancia `run`+toast persistente solo se `update && fetch>0` - aggiornato/ahead = risultato inline nel pannello, zero toast). |
| `mountUpdatesPanel(el)` | renderizza la scheda "Updates" dentro `el` (id stringa o elemento): **Check for update**, **Update now**, i toggle `auto_on_webui_open`/`auto_on_reboot`, i campi del boot-retry, il select **Network** (`net_policy`: Wi-Fi+mobile / solo-Wi-Fi / solo-mobile) e i campi `source`/`channel`/`profile`. |
| `check()` | esegue `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | lancia `run` in background + un toast di progresso con **Cancel**. |
| `cancel()` | crea `$VDLU_DIR/cancel` (l'engine si ferma al punto sicuro). |
| `resume()` | `update.sh resume` + toast (riprende la fase corrente). |
| `refreshBanner()` | ri-valuta il banner persistente di pending-reboot. |

Il toast (overlay d'angolo, non bloccante) e il banner (in alto, persistente) vengono iniettati dal widget in
`document.body` - l'host non ha bisogno di HTML per loro. La scheda "Updates" è l'unico punto che l'host alloca (un
`<div>` vuoto).

### Il flusso di stato che il toast riflette (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` in qualsiasi momento. Il
toast mostra **una barra + `phase done/total · current · bytes`**. Terminali:
- **`DONE`** → toast verde "v&lt;target&gt; applicata".
- **`PENDING_REBOOT`** (o `reboot_pending=true`) → toast verde + **banner persistente** "⚠️ Riavvia per
  attivare il nuovo `.so` (vX)".
- **`ERROR`** → toast rosso con il motivo (`journal.error`/stderr). Non finge mai il successo.
- **Cancelled** → "cancelled - N/M, ripristinabile" + un pulsante **Resume**.

## Eseguire il demo

Apri `demo.html` in un browser (`xdg-open webui/demo.html`). Il `ksu.exec` mockato simula `update.sh` e
`journal.json` che evolvono; i pulsanti commutano tra gli scenari **LIVE→DONE**, **reboot_pending**, **error a metà**
e **cancellabile**. È lo stesso `vdlu.js`/`vdlu.css` che sul dispositivo.

## i18n (lingua)

Le stringhe del widget hanno come default l'**inglese** (neutro per i moduli pubblici multilingua). L'host sovrascrive
qualsiasi chiave passando una mappa in `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Un merge **parziale** va bene: una chiave mancante ricade sul default inglese.
- Le chiavi di phase/state sono `ph_<phase>` / `st_<STATE>`; il resto è piatto (`cancel`, `updateNow`, …).
- La mappa completa delle chiavi = l'oggetto `DEFAULT_I18N` in `vdlu.js` (esposto anche come `VDLU.i18n`).
- Una traduzione pronta è fornita come esempio lavorato: `i18n/pt-BR.js`. Nuove lingue = un file
  `i18n/<lang>.js` nello stesso stampo, oppure l'host costruisce la mappa dal proprio sistema i18n.

## Fonte unica (parità tra i moduli)

Questi `vdlu.js`/`vdlu.css` sono la **copia canonica**. Ogni modulo che imbarca il widget
**ri-vendorizza** questa copia byte-per-byte nel proprio `webroot/` - **non** modifica mai
il proprio in place. Una nuova feature del widget nasce qui e scorre giù per re-vendor; il contrario produce un drift
silenzioso (è successo in pratica: una copia vendorizzata era rimasta indietro e mancava di `net_policy`, del toast
`DEFERRED` e dei campi `boot_retry`).

Guardiano: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) trova ogni copia nell'albero sorgente e segnala
quelle che divergono da quella canonica (solo `vdlu.js`/`vdlu.css`; il keyring è "verifica, non copia").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Il keyring (`keyring/<id>.pub` RAW 32B) e l'engine (`vdlu/update.sh`) hanno la propria cadenza di re-vendor;
> questo guardiano copre **solo il widget WebUI**.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti; vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
