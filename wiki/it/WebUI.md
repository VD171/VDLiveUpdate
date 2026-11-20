# WebUI

VDLU include un widget WebUI opzionale drop-in: un piccolo pannello "Updates" per una WebUI di root manager KernelSU o APatch. Da all'utente un pulsante Check, un pulsante Update now, un toast di avanzamento live con cancel, un banner di riavvio e un pannello impostazioni, tutto senza che l'utente tocchi mai un terminale.

È **JavaScript vanilla**: nessun framework, nessun build step, nessun CDN. Tre file:

| File | Cos'è |
|---|---|
| `vdlu.js` | il widget; espone `window.VDLU` |
| `vdlu.css` | gli stili per il toast, il banner e il pannello (tema scuro, eredita le variabili CSS dell'host) |
| `demo.html` | una pagina standalone che simula il bridge del dispositivo così l'intera UI gira in un browser normale |

Il widget è interamente opzionale. L'[[Engine]] gira bene da solo dai trigger di boot; la WebUI è solo un volto amichevole sopra di esso. Vedi [[Quick Start]] per collegarlo in un modulo.

---

## Come la UI parla con l'engine: il bridge `ksu.exec`

Il widget non fa mai nulla di privilegiato di suo. Costruisce un comando shell e lo passa al bridge `ksu.exec` del root manager, che lo esegue come root e restituisce stdout / stderr / codice di uscita. Tutto ciò che il pannello mostra viene riletto da file che l'engine scrive.

Il widget avvolge quel bridge in una singola funzione `exec(cmd)` che restituisce una `Promise`:

- **risolve** con stdout quando il comando esce con 0
- **rigetta** con stderr (o `rc=N`) altrimenti

Ogni comando porta l'ambiente del contratto, assemblato dal widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Alcune chiamate concrete:

- **Avviare un aggiornamento:** `update.sh run` viene lanciato in **background** (`(... &)`) così la UI non è mai bloccata da un download lungo.
- **Leggere l'avanzamento:** un poll leggero (circa una volta al secondo) di `cat $VDLU_DIR/journal.json`.
- **Cancel:** `touch $VDLU_DIR/cancel` (l'engine si ferma al successivo punto sicuro).
- **Config:** legge e scrive `$VDLU_DIR/config` (key=value), preservando l'ordine e le chiavi sconosciute e toccando solo le chiavi che l'utente ha cambiato.

Se l'host passa i propri helper `exec`, `toast` e `confirm` a `init()`, il widget instrada attraverso la coda di comandi serializzata e la grafica proprie dell'host, così appare e si comporta come il resto di quella WebUI. Se sono omessi, il widget ripiega sul chiamare `ksu.exec` direttamente e inietta il proprio mini-toast.

---

## Il toast di avanzamento (con cancel)

Una volta che un aggiornamento è in esecuzione, il widget mostra un toast d'angolo non bloccante e fa il poll di `journal.json`. Il toast riflette la macchina a stati dell'engine:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Rende una barra di avanzamento più una riga di `phase done/total - current file - bytes`, e porta un pulsante **Cancel** per tutto il tempo. Gli stati terminali ricevono ciascuno il proprio trattamento:

- **DONE** -> un toast verde, "vX applied - all verified".
- **PENDING_REBOOT** -> un toast verde più un banner di riavvio persistente (sotto).
- **ERROR** -> un toast rosso con il motivo da `journal.error` o stderr, che offre Retry. Non finge mai il successo.
- **Cancelled** -> un toast ambra, "cancelled - N/M applied, resumable", che offre **Resume**.
- **DEFERRED** -> un gentile toast info blu, "download deferred, waiting for the allowed network". Questa è un'attesa benigna di network policy, non un errore; riprende al prossimo check o boot sulla rete giusta.

Il poll è difensivo. Un journal scritto a metà (l'engine scrive in concorrenza) viene ignorato per quel tick invece di essere interpretato male. Se il journal sparisce dopo che è stato visto avanzamento, significa che il commit lo ha ripulito: il widget riporta DONE. Se il journal è assente fin dall'inizio per 8 tick, riporta "no response". E se il journal si congela sugli stessi valori per 20 tick, il widget controlla il `lock.d` dell'engine: se il lock è vivo e solo un fetch lento di un singolo blob e il toast continua ad attendere; se il lock è morto l'esecuzione è morta a metà, quindi il widget fa emergere un errore con un pulsante Resume invece di girare su "updating" per sempre.

---

## Il banner di riavvio

Alcuni file non possono essere scambiati su un sistema live: un `.so`, un overlay `/system`, una `sepolicy.rule`. L'engine li mette in staging e marca la transazione `PENDING_REBOOT`. Il widget mostra allora un **banner persistente in alto**: "Reboot to activate the new `.so` (vX)". Resta finché i file in staging non vengono scambiati al boot successivo. All'apertura della WebUI il banner viene rivalutato dal journal, così un utente che chiude e riapre la UI lo vede ancora. Vedi [[Reboot Handling]] per cosa succede al boot.

Nota che il banner si aggancia allo stato terminale `PENDING_REBOOT`, non al flag `reboot_pending` (che diventa true non appena un qualunque `.so` entra nel piano). Questo evita che il banner compaia a metà esecuzione prima che qualcosa sia effettivamente in staging.

---

## Il pannello "Updates": toggle indipendenti per categoria

`mountUpdatesPanel(el)` rende il pannello impostazioni in un `<div>` vuoto che l'host fornisce. Ha tre sezioni, e ogni controllo è indipendente e salva per conto proprio:

**Actions**
- **Check for updates** -> esegue `check`, mostra il risultato inline (aggiornato / più recente del feed / aggiornamento disponibile con il conteggio dei file e un tag reboot).
- **Update now** -> lancia `run` più il toast di avanzamento.

**Automation** (toggle indipendenti, ciascuno scritto su `config` nel momento in cui viene commutato)
- **On WebUI open** (`auto_on_webui_open`) -> esegue un aggiornamento silenzioso quando la UI si apre.
- **On reboot** (`auto_on_reboot`) -> applica in pre-zygote al boot.
- **Boot retry every (s)** e **Boot retry up to (min)** -> campi numerici per ritentare un fetch del manifest quando il dispositivo avvia offline.

**Source**
- `source` (l'URL del feed), `channel` (stable / canary), `profile` (trusted / hardened), e un select **Network** che mappa a `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

I toggle e i campi numerici salvano immediatamente e si ripristinano visivamente se la scrittura fallisce. I campi di testo e select nella sezione Source si marcano come dirty e salvano insieme su un pulsante Save esplicito. Il pannello riscrive sempre e solo le chiavi che l'utente ha toccato, così qualsiasi chiave di config sconosciuta o futura viene preservata.

### Comportamento auto-open

`onWebUIOpen()` viene chiamato al caricamento dell'host. Valuta il journal (mostrando il banner di riavvio o offrendo Resume per una transazione non terminale lasciata da una sessione precedente), poi, se `auto_on_webui_open=1`, esegue prima un `check()` **silenzioso**. Il toast di avanzamento persistente e il `run` effettivo si attivano solo quando c'è un download reale da fare (`update && fetch > 0`). Se il dispositivo è aggiornato o avanti rispetto al feed, il risultato viene mostrato inline nel pannello e nessun toast viene lasciato sullo schermo, così l'auto-aggiornamento è tanto non intrusivo quanto il pulsante manuale.

---

## i18n (stringhe per lingua)

Ogni stringa UI ha come default l'**inglese**, che è la scelta neutra per moduli pubblici multilingua. La mappa di chiavi completa vive nell'oggetto `DEFAULT_I18N` in `vdlu.js` (esposto anche come `VDLU.i18n`). Un host sovrascrive qualsiasi sottoinsieme di chiavi passando una mappa a `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Una mappa **parziale** va bene: qualsiasi chiave mancante ripiega sul default inglese.
- Le label di fase e stato usano le chiavi `ph_<phase>` e `st_<STATE>`; il resto sono chiavi piatte come `cancel`, `updateNow`.
- Una traduzione svolta (`i18n/pt-BR.js`) viene fornita come template; una nuova lingua è solo un file `i18n/<lang>.js` nella stessa forma, oppure l'host costruisce la mappa dal proprio sistema i18n.

---

## demo.html: eseguire la UI senza dispositivo

`demo.html` simula il bridge `ksu.exec` così gli esatti stessi `vdlu.js` e `vdlu.css` girano in un browser normale, senza root e senza telefono:

```sh
xdg-open webui/demo.html
```

Il mock simula `update.sh` e un `journal.json` in evoluzione, e i suoi pulsanti commutano fra gli scenari: un aggiornamento live fino a DONE, un finale `reboot_pending`, un errore a metà, e un'esecuzione cancellabile. È il modo più rapido di vedere e iterare sulla UI, ed è ciò che controlli prima di vendorizzare il widget in un modulo.

---

## Collegarlo in un modulo (il trigger WebUI-open)

L'`index.html` host carica i due file e chiama tre funzioni:

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

L'host deve solo fornire i path Tier-2 e allocare un `<div>` vuoto per il pannello; il toast e il banner vengono iniettati in `document.body` dal widget. `onWebUIOpen()` è il trigger WebUI-open: è ciò che valuta il banner di riavvio, offre Resume su una transazione interrotta, ed esegue l'auto-aggiornamento silenzioso quando `auto_on_webui_open` è impostato.

### Sorgente unica, ri-vendorizzata byte per byte

`vdlu.js` e `vdlu.css` sono la **copia canonica**. Un modulo che incorpora il widget ri-vendorizza questi file invariati nel proprio `webroot/`; non modifica mai la propria copia in loco. Una nuova feature nasce nei file canonici e scende per ri-vendorizzazione. Modificare una copia vendorizzata produce un drift silenzioso (è successo: una copia stale mancava di `net_policy`, del toast DEFERRED e dei campi boot-retry). Un guardiano di parità nell'albero sorgente trova ogni copia e segnala o ri-vendorizza quelle che divergono, coprendo solo il widget; il keyring ha la propria cadenza verify-not-copy.

---

### API pubblica (`window.VDLU`)

| Funzione | Fa |
|---|---|
| `init(opts)` | configura il widget; restituisce `window.VDLU` |
| `onWebUIOpen()` | chiama al caricamento: banner, offerta Resume e auto-aggiornamento silenzioso |
| `mountUpdatesPanel(el)` | rende il pannello Updates in `el` (stringa id o elemento) |
| `check()` | esegue `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | lancia `run` in background più il toast di avanzamento con Cancel |
| `cancel()` | crea `$VDLU_DIR/cancel` (l'engine si ferma a un punto sicuro) |
| `resume()` | riprende la transazione corrente più un toast |
| `refreshBanner()` | rivaluta il banner persistente di pending-reboot |

---

Vedi anche: [[Engine]] per i comandi che il widget pilota, [[Quick Start]] per i passi completi di adozione, e [[Reboot Handling]] per cosa il banner sta attendendo.
