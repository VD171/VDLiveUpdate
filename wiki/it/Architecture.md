# Architettura

VDLU ha due lati uniti da una sola cosa nel mezzo. Sul PC, il [[Producer]] trasforma un albero di modulo in un feed firmato e content-addressed. Sul dispositivo, l'[[Engine]] legge quel feed, capisce cosa è cambiato e lo applica. La cucitura fra i due è il **manifest firmato più il blob store** (il [[Feed Format]]). Nient'altro attraversa il divario.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

I due lati non condividono mai un runtime. Il Producer usa `python3` e `openssl`; l'Engine è `sh` POSIX puro con toybox e un `ed25519-mini` embedded. Concordano solo perché entrambi derivano gli **stessi byte canonici** da un manifest (vedi [[Security and Trust Model]]). La WebUI è un pannello sottile in JS vanilla che pilota il motore attraverso il bridge del root manager e legge il suo journal di avanzamento; non contiene alcuna logica di aggiornamento propria. Vedi [[WebUI]].

## I due lati

| Lato | Gira su | Costruito con | Compito |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Percorrere l'albero del modulo in `manifest.json` + `blobs/`, firmarlo, potare gli orfani |
| [[Engine]] | device | `sh` POSIX + toybox + `ed25519-mini` | Fare il diff dell'albero installato rispetto al feed, scaricare i delta, applicare, fare commit |
| [[WebUI]] | device (webview) | JS/CSS vanilla | Innescare gli aggiornamenti, mostrare l'avanzamento, modificare la config, mostrare il banner di riavvio |

## La pipeline di aggiornamento

Ogni aggiornamento è una transazione, eseguita in un ordine fisso:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` è questa fase, in sola lettura). Il motore scarica solo il manifest, esegue `validate_plan()` su ogni campo **prima** di toccare qualsiasi cosa, poi confronta il feed con `current.json` per costruire un piano file-per-file. Non cambia nulla su disco. Un dispositivo avanti rispetto al feed è un benigno risultato "ahead", non un errore.
- **FETCH.** Scarica solo i blob che il piano ha come mancanti, in `<sha>.part`, decomprime i `gz`, verifica `sha256sum` rispetto al manifest, e sposta atomicamente (`mv`) ogni blob verificato nella cache. Un blob già in cache (o seminato da un file locale invariato) viene saltato, quindi un ripristino o un file condiviso non costa nulla. Tre fallimenti su un singolo blob abortiscono la fase senza applicare nulla. Un download bloccato dalla network policy esce come `DEFERRED` (riprendibile), non un errore.
- **APPLY.** I file ordinari (`live` / `soft`) vengono scritti ora: backup in `rollback/<v>/`, scrittura di un `.vdlu-tmp`, `chmod`, verifica, poi `rename` atomico sopra il target. I file di classe reboot vengono materializzati in `staged/<path>.vdlu-new` e l'inode live viene lasciato intatto. Una voce `delete[]` viene prima salvata in backup, poi rimossa. Ogni passo è idempotente: un file già all'hash target viene saltato.
- **COMMIT.** Fa il re-hash di ogni file live; solo se tutto corrisponde il motore promuove `target.json` a `current.json`. Se qualcosa è stato messo in staging, la transazione termina in `PENDING_REBOOT`; altrimenti `DONE`.

## Manifest e blob content-addressed

Il feed è content-addressed: il manifest elenca l'albero target **completo**, ogni file portato dal suo `sha256`, e il blob store contiene una copia di ciascun contenuto distinto sotto `blobs/<sha256>` (oppure `blobs/<sha256>.gz`).

- **Dedup.** Un contenuto identico ovunque nell'albero, o fra release, è un solo blob. La pubblicazione è incrementale: un blob il cui `sha256` esiste già sull'host non viene mai ri-pushato, e il dispositivo non riscarica mai contenuto che ha già.
- **sha256 è dell'originale.** L'hash nomina sempre il contenuto non compresso; `enc` (`raw` o `gz`) registra solo come quel singolo blob risulta essere memorizzato. Il dispositivo decomprime i `gz` con `gunzip` di toybox, così non viene incluso alcun compressore extra.
- **Stabile rispetto al flavor.** Poiché il dispositivo fa il diff rispetto a ciò che è effettivamente installato, il feed può portare un'intera famiglia di modulo; ogni installazione scarica solo i blob che completano il proprio flavor.

Il layout completo campo per campo è in [[Feed Format]].

## Il journal riprendibile

Ogni transazione è crash-safe perché il suo avanzamento vive in un journal (`journal.json`), e il target fissato della transazione in corso vive in `target.json`. La macchina a stati gira in un ordine fisso:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Stato | Significato |
|---|---|
| `PLANNED` | Piano costruito, ancora nulla scaricato |
| `FETCHING` / `FETCHED` | Download dei blob in corso / tutti i blob presenti e verificati |
| `APPLYING` / `APPLIED_LIVE` | Scrittura dei file / tutti i file live scritti |
| `PENDING_REBOOT` | Un file di classe reboot è in staging, in attesa dello swap al boot |
| `DONE` | Il re-hash di tutto ha corrisposto; `current.json` promosso |
| `ERROR` | Fallimento grave; modulo lasciato non corrotto, file live ripristinati da `rollback/` |
| `DEFERRED` | Download trattenuto dalla network policy; il piano persiste, riprende più tardi |

`DONE` viene raggiunto **solo** una volta che un re-hash di tutto corrisponde, così il journal non dichiara mai completo un aggiornamento applicato a metà. Un crash, una rete caduta o un riavvio a metà lasciano un journal riprendibile; `update.sh resume` (o `boot`) riprende dalla fase corrente. Vedi [[Engine]] per l'insieme dei comandi e i file di stato sul dispositivo.

## Atomicità e rollback

Nulla viene mai sovrascritto in loco e nulla viene perso:

- **Scritture atomiche.** Ogni file atterra tramite un temp (`.vdlu-tmp`) e un `rename` / `mv` atomico, così un lettore non vede mai un file scritto a metà.
- **Backup prima della sovrascrittura.** Il contenuto precedente va in `rollback/<version>/<path>` prima che il nuovo file venga rinominato sopra di esso (vengono mantenute le ultime versioni). Se un apply fallisce, i file live vengono ripristinati dalla copia di rollback invece di essere lasciati corrotti. Un backup fallito **aborta** l'apply invece di sovrascrivere senza una rete di sicurezza.
- **Serializzato.** Un lock basato su `mkdir` (`lock.d/`, poiché `flock` è inutilizzabile su toybox, con recupero degli stale tramite PID) serializza le esecuzioni concorrenti.

## Il principio reboot-free

La maggior parte dei file può essere scambiata mentre il modulo è live, quindi VDLU li applica immediatamente. Solo tre classi richiedono un riavvio, perché un processo live le ha già mappate: un `.so` (caricato da Zygisk), un overlay `/system` e una `sepolicy.rule`. Questi sono **messi in staging, mai scritti sopra un inode live**, e scambiati in un singolo passo pre-zygote al boot successivo. La tassonomia completa e il flusso di boot sono in [[Reboot Handling]].

## La postura di fiducia fail-closed

Il feed è l'unica cosa che attraversa dal PC al dispositivo, quindi il motore tratta ogni suo byte come ostile. `validate_plan()` gira nella fase DIFF, prima di qualsiasi download, e rifiuta l'intero manifest su qualsiasi campo malformato. La verifica della firma usa un `ed25519-mini` embedded (niente `openssl` sul dispositivo), la chiave privata non tocca mai un dispositivo o la CI, e il profilo `hardened` è fail-closed per inversione così un valore di profilo corrotto non può mai accettare silenziosamente un feed non firmato. Il modello completo, i due profili e le minacce a cui ciascuno risponde sono in [[Security and Trust Model]].
