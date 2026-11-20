# Reboot Handling

L'intero scopo di VDLU è aggiornare un modulo senza riflasharlo, e, ovunque possibile, senza riavviare affatto. La maggior parte dei file in un modulo può essere sostituita mentre il dispositivo è in esecuzione. Alcuni genuinamente non possono, perché il kernel o il processo zygote li ha già mappati e non noterà un cambiamento fino al boot successivo.

Il compito di VDLU è distinguere automaticamente quei due gruppi, applicare dal vivo tutto ciò che può in sicurezza, e rinviare solo i file genuinamente legati al boot a un riavvio che segnala chiaramente. Questa pagina spiega come.

Per la meccanica dell'engine sottostante, vedi [[Engine]]. Per il quadro generale, vedi [[Architecture]].

## Perché non riavviare semplicemente ogni volta

Un riavvio è la cosa più costosa che un aggiornamento possa chiedere a qualcuno. Interrompe qualunque cosa stiano facendo, richiede un minuto o più, e abitua le persone a temere gli aggiornamenti. Un buon aggiornatore incrementale dovrebbe sembrare invisibile: tocchi update, alcuni file cambiano sotto il sistema in esecuzione, e sei già sulla nuova versione.

Quindi VDLU inverte l'assunzione usuale. Il default è live. Un file viene rinviato a un riavvio solo quando è provabilmente uno dei tipi legati al kernel o a zygote, e anche allora solo quel file attende. Tutto ciò che gli sta attorno si aggiorna comunque immediatamente.

## Le tre classi

A ogni file nel feed è assegnata una classe. Il producer può impostarla esplicitamente nel manifest, ma in pratica la classe è derivata dal path, e l'engine farà solo upgrade di un file verso `reboot`, mai downgrade verso `live`. Le classi sono:

**LIVE** è il caso comune: asset della web UI, binari, script letti su richiesta, file di config, `module.prop`, e qualsiasi altra cosa non catturata dalle regole sotto. Un file live viene salvato in backup e poi rinominato atomicamente sopra il target mentre il sistema è in esecuzione. Nessun riavvio, e il cambiamento ha effetto nel momento in cui il rename atterra.

**SOFT** sono gli script di lifecycle propri del modulo: `service.sh`, `post-fs-data.sh` e `boot-completed.sh`. Questi vengono applicati dal vivo esattamente come i file LIVE, così la nuova copia è già su disco. Il motivo per cui ricevono la propria classe e che il sistema in esecuzione ha già eseguito la vecchia copia in questo boot; la nuova semplicemente gira al boot successivo, senza staging e senza banner. Non c'è nulla da rinviare, solo un passaggio di consegne naturale.

**REBOOT-hard** è il piccolo insieme che non può cambiare sotto un sistema in esecuzione:

- librerie native, `*.so` (qualsiasi cosa sotto un path `zygisk/`), perché zygote le mappa in ogni app all'avvio;
- file di overlay `/system`, perché l'overlay viene montato al boot;
- file `sepolicy.rule`, perché la policy SELinux viene caricata presto.

Un file REBOOT-hard non viene mai scritto sopra il suo inode live mentre il sistema è attivo. Sovrascrivere un `.so` che zygote ha già mappato è il modo in cui ottieni crash e stato incoerente. Invece il nuovo contenuto viene **messo in staging** accanto alla directory di stato e scambiato al boot successivo, prima che qualcosa possa mapparlo.

## Dal path alla classe, a colpo d'occhio

L'engine deriva la classe dal path così:

| Pattern di path | Classe | Applicato |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (i file `.so`) | REBOOT-hard | in staging, scambiato pre-zygote al boot |
| `system/**` (overlay) | REBOOT-hard | in staging, scambiato al boot |
| `*.rule` (sepolicy) | REBOOT-hard | in staging, scambiato al boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | scritto dal vivo, gira al boot successivo |
| `webroot/**`, `bin/**`, `lib/**`, config, `module.prop`, tutto il resto | LIVE | scritto dal vivo, effettivo immediatamente |

Il manifest può portare una `class` esplicita per file, ma la classe derivata agisce come un pavimento: se un file sembra REBOOT-hard dal suo path, viene trattato come REBOOT-hard anche se il manifest dice altrimenti. Questo evita che un feed mal etichettato provi mai a fare hot-swap di un `.so`.

## Come un'esecuzione gestisce entrambi i gruppi insieme

Durante un normale `run` (il ciclo da DIFF a FETCH a APPLY a COMMIT descritto in [[Engine]]), i due gruppi vengono gestiti nella stessa transazione:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Quindi dopo un'esecuzione che ha toccato un `.so`, sei già sulla nuova versione per ogni file live, e solo i pezzi in staging stanno attendendo. Il journal riporta `reboot_pending`, e la WebUI mostra un banner persistente che invita a un riavvio per attivare i file in staging. Non c'è alcun "done" fasullo: un'esecuzione con file in staging termina in `PENDING_REBOOT`, non `DONE`.

## Lo swap al boot

I file in staging vengono applicati dal comando `boot`, che il modulo host collega a `post-fs-data.sh` così gira in modo sincrono e **pre-zygote**, prima che qualsiasi processo possa mappare il nuovo `.so`.

`boot` fa un `resume` (per finire qualsiasi fase interrotta) e poi lo swap. Per ogni file REBOOT-hard in staging:

1. conferma che il path in staging resti dentro la directory del modulo (un controllo di containment);
2. ri-hasha `staged/<path>.vdlu-new` rispetto all'hash del manifest;
3. salva in backup il file live corrente;
4. `mv -f` il file in staging sopra quello live e gli fa `chmod`;
5. ri-hasha il file ora al suo posto, per confermare che lo swap sia atterrato correttamente;
6. lo marca come applicato.

Solo una volta che ogni file in staging è stato scambiato e ri-verificato la transazione chiude da `PENDING_REBOOT` a `DONE`. Se un qualunque passo fallisce, il journal registra l'errore e il modulo mantiene i suoi file precedenti; nulla viene lasciato scambiato a metà.

Poiché lo swap è una sequenza di re-hash e rename atomici, eseguire `boot` è sicuro anche se è stato interrotto l'ultima volta. Semplicemente riprende i file in staging.

## auto_on_reboot

Lo staging è solo metà di un feel reboot-free; l'altra metà è che l'utente non dovrebbe mai dover ricordarsi di eseguire lo swap. Con `auto_on_reboot=1` nella config, il `post-fs-data.sh` del modulo host chiama `update.sh boot` a ogni boot. Questo significa:

- se una transazione è in pending reboot, i file in staging vengono scambiati automaticamente prima che zygote parta, e l'utente si ritrova semplicemente pienamente sulla nuova versione;
- se non c'è nulla di pendente, `boot` può eseguire un ciclo fresco e applicare tutto, incluso un `.so`, in quel singolo boot, poiché sta già girando pre-zygote.

In altre parole, un `.so` in staging non costa all'utente nulla oltre a un riavvio che avrebbe fatto comunque. Non deve toccare nulla la seconda volta.

## Offline al boot, senza scaricare la batteria

A volte `boot` vuole controllare il feed ma il dispositivo non ha ancora rete. VDLU può attendere, pazientemente ed economicamente, controllato da `boot_retry_minutes` (0 lo disattiva). L'attesa è deliberatamente battery-safe:

- fra un tentativo e l'altro semplicemente `sleep`, che si congela nel deep sleep, così il dispositivo dorme normalmente e il retry riprende solo una volta che il dispositivo è già sveglio;
- non tiene alcun wakelock e non tiene il lock dell'engine mentre attende, così un'esecuzione manuale non è mai bloccata;
- prima di ogni tentativo controlla se la rete è consentita con un lookup della route del kernel che non invia alcun pacchetto e non sveglia la radio;
- non ritenta mai un fallimento deterministico come una firma errata o un downgrade bloccato, solo una genuina condizione di rete assente.

Il check del manifest stesso resta gratuito su qualsiasi rete, così scopri sempre che un aggiornamento esiste; solo il download attende che la network policy sia soddisfatta, rinviando in modo pulito invece di dare errore.

## Vedi anche

- [[Engine]]: la transazione, la logica di apply-per-classe, e il comando `boot` per intero.
- [[Architecture]]: dove si colloca l'engine fra il producer e la WebUI.
