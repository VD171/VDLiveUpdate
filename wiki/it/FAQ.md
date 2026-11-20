# FAQ

Risposte brevi alle domande che vengono poste più spesso. Ciascuna rimanda alla pagina con
la storia completa.

## Cosa significa "flashless"? Devo comunque flashare la prima volta?

Si, flashi una volta. Il modulo viene installato nel modo normale (flasha lo zip nel
tuo root manager). "Flashless" descrive ogni aggiornamento successivo a quello: VDLU scarica
solo i file che sono cambiati e li applica in loco, così non riflashi mai uno zip
completo solo per spedire poche righe modificate. Vedi [[Architecture]].

## Un aggiornamento richiede un riavvio?

Di solito no. La maggior parte dei file (la tua WebUI, binari, librerie, config, `module.prop`)
sono di classe **live** e si applicano atomicamente senza riavvio. Solo i file di classe reboot
(un `.so` sotto `zygisk/`, un overlay `/system/**`, un file sepolicy `*.rule`) vengono
**messi in staging** e scambiati al boot successivo, perché un processo in esecuzione ha già
mappato l'inode live. Quando questo accade la WebUI mostra un banner persistente "reboot to
activate". Vedi [[Reboot Handling]].

## È sicuro se il feed è MITM'd o avvelenato?

Si, su un feed `hardened`. Ogni campo del manifest è trattato come input ostile.
Il manifest deve portare una firma ed25519 valida sulla sua forma canonica, e
`validate_plan()` gira fail-closed **prima di qualsiasi download**: rifiuta l'intero
manifest su un path assoluto o con `..`, un `sha256` che non ha 64 caratteri esadecimali,
o un mode, class o encoding non valido. Il manifest è anche vincolato al tuo id di modulo,
così un feed validamente firmato per un modulo diverso non può essere servito al suo posto.
Lo sha256 di ogni blob viene verificato dopo il download indipendentemente dal profilo. Vedi
[[Security and Trust Model]].

## Cosa serve sul dispositivo (dipendenze)?

Molto poco. `sh` POSIX puro (mksh / busybox / toybox) più `sha256sum`,
`gzip`, `base64` e `date` di toybox; il verificatore `ed25519-mini` embedded; e, solo per
una sorgente `https`, un `curl` statico scaricato una volta e messo in cache in Tier-2.
Una sorgente `file://` non richiede alcun curl. **Non c'è dipendenza da `jq`**: l'
engine fa il parsing del JSON con un flattener in stile gron scritto in `awk`. Vedi [[Engine]].

## È richiesto openssl sul dispositivo?

No. `openssl` viene usato solo sul lato PC/release (`vdlu-keygen`, `vdlu-sign`).
Sul dispositivo, la verifica della firma usa il leggero binario `ed25519-mini` embedded,
che legge una chiave pubblica RAW di 32 byte. Vedi [[Producer]] e
[[Security and Trust Model]].

## Come ruoto la chiave di firma?

Genera una nuova coppia di chiavi con `vdlu-keygen`, aggiungi la nuova chiave pubblica RAW di 32 byte al
keyring del dispositivo accanto a quella precedente, e inizia a firmare con il nuovo
`key_id`. Il dispositivo sceglie `<keyring>/<key_id>.pub` in base al `key_id` del manifest,
quindi non serve alcuna modifica all'engine. Spedire sia la chiave pubblica corrente che quella precedente
significa che una chiave ruotata non bricka mai le installazioni più vecchie. Poiché una rotazione lascia più di una chiave nel keyring, devi anche vincolare quale chiave può firmare un aggiornamento di modulo: imposta la config `key_id` (separate da virgola durante la finestra di rotazione). Un keyring a chiave singola si vincola automaticamente e non richiede alcuna config. Vedi [[Security and Trust Model]].

## hardened vs trusted - quale uso?

Usa `hardened` per qualsiasi feed pubblico (servito tramite `https`, per esempio GitHub Pages).
Rende la firma obbligatoria e blocca i downgrade. Usa `trusted` solo per una
sorgente privata `file://` o SSH-staged che già controlli, dove la firma
è best-effort (l'hash di ogni blob viene comunque controllato). Nel dubbio, usa `hardened`:
è il default fail-closed, e qualsiasi valore non-`trusted` viene trattato come
`hardened`. Vedi [[Security and Trust Model]].

## Cosa succede se un blob è manomesso o il manifest è malformato?

L'aggiornamento aborta e nulla viene applicato. Un manifest malformato viene rifiutato per intero
da `validate_plan()` prima di qualsiasi fetch. Un blob il cui sha256 non corrisponde al
manifest viene rifiutato; tre fallimenti sullo stesso blob abortiscono la fase di fetch con
nulla applicato. Su qualsiasi fallimento grave il journal registra `ERROR` e il modulo
viene lasciato intatto. Vedi [[Engine]].

## Un aggiornamento può cancellare i miei file o brickare il dispositivo?

Il rischio è contenuto per design. I file sovrascritti e cancellati vengono prima salvati in
backup in `rollback/<version>/`, e `apply` aborta invece di sovrascrivere senza
un backup riuscito. Le cancellazioni girano solo quando una transazione raggiunge `DONE`, mai
mentre un riavvio è ancora pendente. Un apply fallito ripristina i file live che ha già
scritto. I path vengono validati per il containment dentro la directory del modulo prima dell'uso,
così un manifest non può scrivere o cancellare fuori dall'albero. Vedi [[Engine]] e
[[Security and Trust Model]].

## Funziona su KernelSU E Magisk E APatch?

Sì. VDLU è semplice `sh` POSIX più una WebUI, vendorizzato nel modulo, quindi gira su
KernelSU, APatch e Magisk allo stesso modo. Usa il bridge WebUI del root manager
(`ksu.exec`) per pilotare l'engine e fare il poll dell'avanzamento. Vedi [[Architecture]] e
[[WebUI]].

## Quanto è grande l'impronta sul dispositivo?

Piccola. L'engine è fatto di script; gli unici binari sono il verificatore `ed25519-mini`
per-ABI (minuscolo) e, per una sorgente `https`, un `curl` statico (~1MB) che viene
scaricato una volta e messo in cache. Un modulo che già include il proprio `curl` lo riusa
e non aggiunge alcun download. La cache dei blob Tier-2 contiene il contenuto verificato più
le ultime 3 versioni di rollback. Vedi [[Engine]] e [[Architecture]].
