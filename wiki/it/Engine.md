# Engine

L'engine è il lato device di VDLU: la parte che gira sul telefono, decide cosa è cambiato, lo scarica e lo applica. È un singolo script shell POSIX, `engine/update.sh`, più un minuscolo verificatore di firma, `engine/vdlu-verify`. Entrambi sono vendorizzati nel modulo host in `<module>/vdlu/` ed eseguiti da root.

L'intero engine è costruito attorno a una sola idea: un aggiornamento è una **transazione riprendibile**. Se il telefono viene riavviato, ucciso o perde la rete a metà, l'esecuzione successiva riprende esattamente da dove si era fermata, e il modulo non viene mai lasciato applicato a metà fingendo di essere completato.

Se vuoi prima il quadro generale, vedi [[Architecture]]. Per come gli aggiornamenti evitano un riavvio ogni volta che possono, vedi [[Reboot Handling]].

## Scritto per il dispositivo, non per il tuo laptop

`update.sh` è `sh` POSIX puro. Gira sotto mksh, busybox o toybox, senza feature esclusive di bash, e passa `sh -n`. Questo conta perché l'ambiente su un dispositivo Android rooted è piccolo e rigido.

In particolare, non c'è `jq`. VDLU fa il parsing di `manifest.json` con un piccolo flattener in stile gron scritto in `awk`: percorre il JSON un carattere alla volta ed emette una riga `path<TAB>value` per foglia (per esempio `files/0/sha256<TAB>ab..` oppure `version<TAB>6`). La shell poi legge quelle righe con `grep` e `cut`. Questo funziona sia su JSON compatto che pretty-printed, e non invoca mai un tool JSON che non c'è.

L'engine dipende solo da ciò che toybox già include (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), dal verificatore `ed25519-mini` embedded, e, per i feed `https://`, da un piccolo `curl` statico scaricato e verificato una volta sola. Un feed `file://` non richiede alcun `curl`.

## I sei comandi

Invochi l'engine con i path del modulo nell'ambiente è un comando:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Il codice di uscita `0` significa successo; qualsiasi altro codice significa un errore, con il motivo stampato su stderr.

| Comando | Cosa fa |
|---|---|
| `check` | Diff in sola lettura. Scarica il manifest, lo confronta con ciò che è installato, e stampa un riepilogo JSON su una riga: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Non cambia nulla su disco. Se il dispositivo è più recente del feed (un downgrade bloccato) riporta `{"update":false,"ahead":true,...}` con uscita `0`, non un errore. |
| `run` | Il ciclo live completo: DIFF, FETCH, APPLY, COMMIT. Applica immediatamente ogni file live e mette in staging i pochi file di classe reboot. Rispetta `cancel`. Scrive l'avanzamento su `journal.json`. |
| `resume` | Continua una transazione interrotta, partendo da qualunque fase fosse in corso. Idempotente. **Non** scambia un `.so` in staging (questo è riservato a `boot`). |
| `boot` | Il percorso pre-zygote. Esegue un `resume` e poi scambia al loro posto eventuali file `*.vdlu-new` in staging, chiudendo `PENDING_REBOOT` a `DONE`. Se non c'è alcuna transazione pendente, esegue un ciclo fresco e applica tutto, incluso il `.so`, in quel singolo boot. |
| `status` | Stampa `journal.json`, oppure `{"state":"idle"}` quando non c'è nulla in corso. |
| `cancel` | Crea un marcatore `cancel`. Un `run` in corso si ferma in modo pulito al successivo punto sicuro. |

Il comando `check` è deliberatamente economico, così la UI può dirti che esiste un aggiornamento su qualsiasi rete. Il download effettivo è gestito separatamente (vedi la fase fetch più sotto).

## La transazione, passo per passo

Ogni `run` si muove attraverso una macchina a stati fissa, registrata in `journal.json` così la WebUI (e tu) può osservarla:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** L'engine scarica `manifest.json`, valida ogni campo (vedi sotto e [[Security and Trust Model]]), e fa il diff dell'albero target firmato rispetto a `current.json`, il manifest della versione già installata. Il risultato è un piano file-per-file scritto in `plan.tsv`: una riga per file, che porta la sua classe, l'hash target, il mode e lo stato di avanzamento. I file già all'hash target vengono marcati da saltare.

**FETCH.** Per ogni file ancora necessario, l'engine scarica il suo blob content-addressed da `<source>/blobs/<sha>` (oppure `<sha>.gz` quando compresso), in un file `.part`. Se il blob è gzippato viene decompresso, poi il suo SHA-256 viene verificato rispetto al manifest. Solo su corrispondenza viene spostato atomicamente (`mv`) in `blobs/<sha>`. Un blob già in cache con hash corretto viene saltato del tutto, e un file locale invariato può seminare la cache senza alcun download. Tre fallimenti sullo stesso blob abortiscono la fase senza nulla applicato. La fase raggiunge `FETCHED` solo una volta che ogni blob del piano è presente e verificato. Per il [[Feed Format]] da cui provengono questi blob, vedi quella pagina. Al setup della toolchain l'engine registra la trust TLS risolta - il path della CA e se è leggibile, più la dimensione del bundle e il numero di certificati - così un curl `rc 77` all'avvio è autoesplicativo in `boot.log` (distingue uno store di fiducia vuoto da uno illeggibile, il caso del contesto-SELinux all'avvio).

Il fetch è gestito dalla network policy: un feed può essere ristretto a solo Wi-Fi, solo mobile, o qualsiasi rete. Quando la rete corrente non è consentita, il fetch non fallisce; entra nello stato benigno `DEFERRED`, mantiene il piano e il target fissati, e riprende al prossimo check o boot una volta che compare la rete giusta. Nel frattempo non viene consumato alcun dato.

**APPLY.** Si entra sempre e solo da `FETCHED`. Per ogni file l'engine agisce secondo la classe:

- file `live` e `soft`: backup del file corrente in `rollback/<version>/<path>`, scrittura del nuovo contenuto in un fratello `.vdlu-tmp`, `chmod`, verifica del suo hash, poi `rename` atomico sopra il target. Un file già all'hash target viene saltato.
- file `reboot` (un `.so`, un overlay `/system`, una `sepolicy.rule`): materializzati in `staged/<path>.vdlu-new`. L'inode live non viene mai toccato qui. Vedi [[Reboot Handling]].
- cancellazioni: backup, poi rimozione. Le cancellazioni vengono applicate solo alla fine, su un `DONE` pulito, mai mentre un riavvio è ancora pendente.

**COMMIT.** L'engine ri-hasha ogni file live e soft che ha toccato. Solo quando tutti corrispondono scrive `current.json`, rendendo la nuova versione la base del diff. Se un qualunque file di classe reboot è stato messo in staging, lo stato diventa `PENDING_REBOOT` invece di `DONE`; lo swap e la ri-verifica finale avvengono più tardi sotto il comando `boot`.

## Fail-safe per costruzione

Le garanzie che rendono sicuro eseguirlo senza supervisione:

- **Nulla viene marcato `DONE` senza un re-hash corrispondente.** `DONE` viene raggiunto solo dopo che ogni file applicato è stato riletto e il suo SHA-256 confrontato col manifest. Un file di classe reboot in staging forza `PENDING_REBOOT`, mai un `DONE` fasullo.
- **Nulla viene perso.** Ogni file viene salvato in backup in `rollback/<version>/` prima di essere sovrascritto, e le ultime tre versioni vengono mantenute. Se un apply fallisce, i file live vengono ripristinati dal backup; il modulo non viene mai lasciato applicato a metà mentendo al riguardo. `apply_live` aborta del tutto se il passo di backup fallisce, invece di sovrascrivere senza vie di ritorno.
- **Tutto è atomico.** Il nuovo contenuto atterra tramite `rename`/`mv` sopra il target, così un lettore vede sempre o il vecchio file o il nuovo, mai una scrittura troncata.
- **Riprendibile dopo un crash o un kill.** Un crash, una rete persa o un riavvio a metà lasciano un journal valido; `resume` (o `boot`) continua dalla fase registrata. Il design presume che verrà interrotto.
- **Degrada in modo pulito.** Un binario mancante, una rete down o un disco pieno producono un errore chiaro su stderr e `state:ERROR` nel journal, senza corrompere il modulo.
- **L'ancora di fiducia è esclusa (`ENGINE_VERSION` 5).** L'engine ignora ogni path `vdlu/` in un piano recuperato - il proprio `update.sh`, `vdlu-verify`, i binari `verify/`, il keyring e la config - così un feed non può mai scambiare il verificatore o la chiave di firma via cavo; l'ancora cambia solo tramite un re-flash firmato completo. Vedi [[Security and Trust Model]].
- **Un aggiornamento rinvia mentre il modulo è occupato.** Con l'opt-in `apply_busy_file` impostato su un path assoluto che il modulo host tocca durante le proprie operazioni (per esempio un backup in corso), l'APPLY attende finché quel path esiste, così i file non vengono mai scambiati a metà operazione; i blob sono già recuperati, così il prossimo trigger applica senza ri-download.
- **Soglie di dimensione.** Un file è limitato a **128 MiB** e il manifest a **2 MiB**, imposte prima che l'uno o l'altro venga letto sia in `update.sh` che in `vdlu-verify` (anti decompression-bomb / anti-OOM).
- **Un modulo più avanti del feed non viene mai riportato indietro (`ENGINE_VERSION` 7).** Il `versionCode` installato dal vivo, letto dal `module.prop` del modulo stesso, fa da base alla versione "from", quindi un dispositivo aggiornato manualmente oltre un feed obsoleto è letto come *più avanti*: la guardia di downgrade ritorna benigna, senza plan e senza ripristino. `boot` auto-ripara anche un'installazione esistente - un plan persistito il cui target è sotto la versione installata, o un journal obsoleto con `target <= 0` (`ENGINE_VERSION` 6), viene ripulito prima di qualsiasi resume.

## Il lock

Solo una transazione può toccare lo stato alla volta. `flock` non è affidabile su toybox, quindi VDLU serializza con un lock su directory: `mkdir "$VDLU_DIR/lock.d"` riesce per esattamente un chiamante e fallisce per gli altri, il che è atomico su qualsiasi filesystem ragionevole. Un lock stale lasciato da un processo morto viene recuperato controllando il PID registrato.

Il retry paziente al boot (usato quando il dispositivo è offline al boot) **non** tiene questo lock mentre attende. Lo acquisisce e rilascia fra un tentativo e l'altro, così un `run` manuale non è mai bloccato da un boot in attesa della rete, e non tiene mai un wakelock. Battery-safe per design. Altro su questo in [[Reboot Handling]].

## Verifica della firma: `vdlu-verify`

`vdlu-verify` è il verificatore di firma sul dispositivo, tenuto deliberatamente leggero:

```
vdlu-verify <manifest.json> <keyring_dir>
```

L'uscita `0` significa che la firma del manifest è valida rispetto alla chiave pubblica del keyring il cui id corrisponde al `key_id` del manifest; qualsiasi altro codice è un rifiuto.

Ciò che lo rende leggero è che usa **nessun `openssl` sul dispositivo**. Legge la chiave pubblica del keyring come un file di **32 byte raw**, canonicalizza il manifest (il testo del manifest con il campo `sig` rimosso), lo hasha con `sha256sum` di toybox, decodifica in base64 la firma, e passa la chiave raw, il messaggio e la firma di 64 byte al binario `ed25519-mini` embedded. Il verificatore rifiuta anche qualsiasi cosa malformata prima ancora di verificare: un `key_id` o `sig` mancante o vuoto, un `key_id` contenente separatori di path, una chiave pubblica che non è esattamente di 32 byte, o una firma che non è esattamente di 64 byte.

Prima ancora di selezionare una chiave, l'engine applica una **allowlist di `key_id`**: il `key_id` del manifest deve essere una chiave che la config autorizza a firmare un *aggiornamento di modulo*, e una chiave meramente presente nel keyring ma non in allowlist viene rifiutata prima che la sua pubkey venga mai caricata. Un keyring a chiave singola vincola automaticamente quell'unica chiave senza config; un keyring a più chiavi deve vincolare `key_id` oppure l'engine fallisce in modo chiuso. L'insieme autorizzato viene passato a `vdlu-verify` come `VDLU_KEYID_ALLOW`, e si applica in entrambi i profili. Questo impedisce a una chiave a minore fiducia, come una chiave di feed di fingerprint che condivide il keyring, di firmare un aggiornamento root completo; il feed di fingerprint separato mantiene la propria chiave vincolata, `FEED_KEY_ID`. La storia completa è in [[Security and Trust Model]].

La canonicalizzazione è byte-per-byte identica a quella del signer del producer, il che è ciò che fa verificare una firma attraverso i tool. La chiave privata corrispondente non tocca mai un dispositivo o la CI; solo la chiave pubblica raw e embedded. La storia completa della fiducia, i due profili e il perché `hardened` è fail-closed per inversione sono in [[Security and Trust Model]].

L'engine chiama `vdlu-verify` durante la fase di diff. Sotto il profilo `hardened` una verifica fallita aborta l'intero aggiornamento; sotto `trusted` la verifica è best-effort, ma l'hash di ogni blob viene comunque sempre controllato, così il contenuto corrotto viene colto indipendentemente dal profilo.

## Stato su disco

Tutto lo stato dell'engine vive in `$VDLU_DIR` (fuori dalla directory del modulo), così l'albero del modulo stesso contiene sempre solo file finiti:

| Path | Ruolo |
|---|---|
| `config` | impostazioni key=value (source, profile, channel, network policy, boot retry) |
| `current.json` | manifest della versione attiva; questa è la base del diff. Assente significa mai aggiornato |
| `target.json` | il manifest fissato della transazione in corso. La sua presenza marca una transazione attiva; diventa `current.json` al `DONE` |
| `plan.tsv` / `plan.del` | il piano file-per-file e l'avanzamento, e la lista dei path da cancellare |
| `journal.json` | avanzamento per la WebUI, riscritto a ogni cambio di stato |
| `blobs/<sha256>` | cache del contenuto originale verificato e decompresso |
| `rollback/<version>/<path>` | backup dei file sovrascritti; le ultime tre versioni vengono mantenute |
| `staged/<path>.vdlu-new` | un file di classe reboot in attesa dello swap al boot |
| `lock.d/` | il lock mkdir |
| `tools/<abi>/curl` | il curl statico scaricato e verificato; persiste fra gli aggiornamenti |
| `cancel` | una richiesta di cancellazione |

## Vedi anche

- [[Reboot Handling]]: come il sistema di classi mantiene la maggior parte degli aggiornamenti reboot-free, e come un `.so` in staging viene scambiato pre-zygote.
- [[Security and Trust Model]]: i due profili, la validazione fail-closed e la catena ed25519 a chiave raw.
- [[Feed Format]]: il manifest e i blob content-addressed che l'engine consuma.
- [[Architecture]]: come engine, producer e WebUI si incastrano insieme.
