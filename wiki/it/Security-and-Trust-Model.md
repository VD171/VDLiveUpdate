# Modello di Sicurezza e Fiducia

VDLU aggiorna un modulo in loco, tramite rete, come root. È parecchio potere puntato su un file che proviene da un feed, quindi l'intero engine è costruito su un'unica assunzione:

> **Ogni campo nel manifest è input ostile.**

Un feed può essere avvelenato alla sorgente, o scambiato e manomesso in transito da un MITM. Quando questo accade il manifest arriva comunque con l'aspetto di un manifest: porta path di file, stringhe `sha256`, una lista `delete[]`, mode, class e un flag di encoding. VDLU non tratta nessuno di questi come affidabile. Valida l'intero piano prima di scaricare un singolo byte, e non lascia mai che un valore del manifest raggiunga una shell.

Questa pagina è la storia completa della fiducia. Vedi [[Feed Format]] per lo schema del manifest che valida, e [[Engine]] per dove questi controlli si collocano nella transazione DIFF -> FETCH -> APPLY -> COMMIT.

---

## L'idea centrale: fail-closed, prima che accada qualsiasi cosa

`validate_plan()` gira dentro la fase `check`/diff, **prima** di qualsiasi fetch e **prima** di qualsiasi apply. Percorre ogni voce nell'albero di file pianificato e ogni voce in `delete[]`, e se una singola voce è malformata **rifiuta l'intero manifest** e la transazione non parte mai. Non c'è accettazione parziale, nessun "salta quella cattiva e applica il resto". Un campo cattivo avvelena il batch, di proposito.

Un manifest viene accettato solo se **tutte** queste condizioni valgono per **ogni** voce:

| Campo | Regola | Perché |
|---|---|---|
| `path` | non assoluto, nessun componente `..`, nessun componente `.`, nessun `./` iniziale, nessun `/./` incorporato, nessuno slash finale, nessun carattere di controllo (tab / newline) | un path deve restare dentro `MODULE_DIR`; un path assoluto o con `..` è write-anywhere |
| `sha256` | corrisponde a `^[0-9a-f]{64}$` esattamente | uno sha non esadecimale verrebbe altrimenti interpolato in un path di shell; e l'indirizzo del contenuto, quindi deve essere un digest esadecimale puro e nient'altro |
| `mode` | solo ottale (`[0-7]`) | una stringa mode diventa un argomento di `chmod` |
| `size` | solo cifre, e `<=` al tetto di dimensione dell'engine | limita il download e la decompressione |
| `class` | esattamente `live`, `soft` o `reboot` | la classe decide se un file si applica dal vivo o viene messo in staging per il reboot |
| `enc` | esattamente `raw` o `gz` | l'encoding decide se il blob viene gunzippato |
| voci `delete[]` | le stesse regole di path di sopra | una voce `delete[]` pilota una rimozione; un `..` non controllato farebbe `rm` fuori dall'albero |

Poiché questo gira per primo, un manifest avvelenato non può mai scrivere fuori dal modulo, mai cancellare fuori dal modulo, e mai iniettare un token non esadecimale in una riga di comando.

### I valori del manifest non toccano mai una shell

La seconda metà della regola: anche dopo che un valore passa la validazione, non viene mai interpolato in `sh`, e mai dato in pasto ad `awk system()`. Il comando check è stato deliberatamente riscritto per non contenere alcuna chiamata `system()`. Il content addressing fa il resto del lavoro: un blob viene scaricato dal suo `sha256`, scritto in un path di cache nominato da quello stesso `sha256`, e i byte scaricati vengono ri-hashati e confrontati prima che qualsiasi cosa venga applicata. Un valore che non è un pulito digest a 64 esadecimali non arriva mai così lontano, perché `validate_plan()` lo ha già rifiutato.

### Una seconda linea di difesa in fase di apply

`validate_plan()` blocca `..` **lessicalmente**, ma un symlink preesistente già dentro l'albero potrebbe comunque reindirizzare una scrittura. Quindi in fase di apply `contained()` risolve il path target reale e conferma che si trovi sotto la base del modulo, fallendo closed quando non può risolvere. Le scritture sono atomiche (scrivi su un nome temp, poi `rename` sopra il target) e ogni sovrascrittura viene prima salvata in backup in `rollback/`; un backup fallito aborta l'apply invece di sovrascrivere senza una rete di sicurezza.

---

## I due profili

VDLU gira in uno di due profili di fiducia, impostato da `profile=` nella config.

### `hardened` (il default pubblico)

- **La firma è obbligatoria.** Il manifest deve portare una firma ed25519 valida da una chiave nel keyring sul dispositivo, oppure la transazione aborta.
- **Il downgrade è bloccato.** Un manifest la cui `version` è inferiore alla versione installata viene rifiutato. Un attaccante non può riportarti indietro a una build nota come vulnerabile.
- Questo è il profilo per qualsiasi modulo distribuito al pubblico tramite `https://`.

### `trusted` (privato, sorgente SSH-staged)

- La verifica della firma è **best-effort**: la sorgente è un feed privato `file://` o SSH-staged che controlli, quindi una firma mancante o non verificabile non fa abortire a forza.
- **Ma lo `sha256` di ogni blob viene comunque sempre controllato.** `trusted` rilassa *chi ha firmato il manifest*, mai *se i byte corrispondono al piano*. L'integrità del contenuto è non negoziabile in entrambi i profili.

---

## Fail-closed per inversione

Questa è la parte sottile, ed è la parte che la maggior parte dei sistemi sbaglia.

`trusted` è l'**unica** stringa che opta per la verifica rilassata. L'engine non verifica "è `hardened`?" Verifica "è **non** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Quindi **qualsiasi cosa** diversa dal letterale `trusted` si risolve in comportamento hardened:

- la riga è interamente mancante -> hardened
- un typo come `hardend` -> hardened
- `trusted ` con uno spazio finale, o un `\r` da CRLF -> hardened
- `Trusted` con il case sbagliato -> hardened
- un valore manomesso da MITM -> hardened

Una versione precedente faceva defaultare a hardened una riga *mancante*, il che lasciava comunque un *valore* corrotto cadere nel percorso aperto. Quello era un fail-open: una stringa di profilo manomessa poteva accettare silenziosamente un manifest non firmato, e un manifest non firmato significa un `.so` fornito dall'attaccante scambiato in sotto MITM, che è esecuzione di codice remoto a livello root. L'inversione lo chiude. L'unico modo di ottenere la verifica rilassata e scrivere `trusted` esattamente, e anche allora gli hash dei blob vengono controllati. L'engine non è mai a un typo di distanza dall'accettare codice non firmato. (Il `tr -d` elimina gli spazi vaganti così un legittimo `trusted` con spaziatura sciatta non viene erroneamente rifiutato, senza riaprire il buco.)

**Questo test è load-bearing. Deve restare `!= trusted` e mai diventare `== hardened`.**

---

## Il manifest è vincolato al modulo

Una singola chiave di release firma molti moduli. Quindi un manifest validamente firmato, per un modulo *diverso*, potrebbe in linea di principio essere servito a questo (una misconfigurazione del feed, uno scambio di sorgente, o un redirect MITM) e la sua firma risulterebbe valida.

VDLU chiude questo con un vincolo: il campo `module` firmato dentro il manifest deve essere uguale al `MODID` di questa installazione, oppure il manifest viene rifiutato come feed cross-module. Poiché `module` è dentro la forma canonica firmata, un attaccante non può cambiarlo senza rompere la firma. Un feed validamente firmato per il modulo B semplicemente non può essere applicato al modulo A.

---

## Il verificatore leggero sul dispositivo

La verifica sul dispositivo usa **ed25519-mini**, un minuscolo verificatore solo-verifica costruito su TweetNaCl (public domain). **Non c'è `openssl` sul dispositivo**.

- La voce del keyring è la **chiave pubblica raw di 32 byte**, memorizzata come `keyring/<key_id>.pub`. (La chiave pubblica PEM è un artefatto solo lato PC; copiare un PEM nel keyring del dispositivo rompe la verifica, poiché il verificatore si aspetta esattamente 32 byte raw.)
- `vdlu-verify <manifest.json> <keyring_dir>` ricostruisce la forma canonica (il testo del manifest con il campo `sig` rimosso, compatto, chiavi ordinate), lo hasha nel messaggio esadecimale di 64 caratteri che la firma copre, decodifica la firma base64, controlla che sia di 64 byte, e chiede a `ed25519-mini <pub32> <msg> <sig64>` un verdetto. rc 0 = valido, qualsiasi altra cosa = rifiuto.
- Il binario è statico per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), con un `PROVENANCE.json` che fissa le esatte sorgenti TweetNaCl, l'hash del wrapper e i flag di build, così la cosa che gira come root è auditabile.
- Il `key_id` dal manifest è esso stesso sanificato (nessun `/`, nessun `..`, nessuna virgoletta) prima di essere usato per scegliere un file del keyring, così non può evadere dalla directory del keyring.

### Il keyring è flash-only, verify-not-copy, stabile

Il keyring viene spedito dentro il modulo in fase di flash e non viene riscritto dall'engine di aggiornamento. In fase di ri-vendorizzazione la regola è **verify, do not copy**: il keyring cambia solo su una rotazione deliberata di chiave, mai come effetto collaterale di un aggiornamento.

### La rotazione della chiave non bricka le installazioni più vecchie

Quando una chiave di firma viene ruotata, il keyring spedisce **sia la chiave pubblica raw corrente che quella precedente**. Il verificatore seleziona il file di chiave in base al `key_id` del manifest, così un feed ancora firmato dalla vecchia chiave verifica rispetto alla vecchia pubkey, e un feed firmato dalla nuova chiave verifica rispetto a quella nuova. Un dispositivo che non ha aggiornato oltre la rotazione continua a funzionare; nulla resta bloccato.

---

## Cosa chiude il tools-manifest

Il bootstrap di fetch leggero scarica un `curl` statico al primo uso per i moduli che non ne spediscono uno proprio. Poiché quel binario gira come root, la firma del suo stesso manifest (ed25519-mini) e il suo hash sono **obbligatori in qualsiasi profilo**, incluso `trusted`, prima che venga mai installato o eseguito. La webview è solo trasporto; la fiducia viene dal controllo di firma e hash sul dispositivo, mai dal fatto che un download sia riuscito.

---

## Cosa un attaccante NON PUÒ fare

Anche possedendo il feed, o sedendo sul filo come MITM completo, un attaccante non può:

- **Scrivere fuori dal modulo.** Path assoluti, `..`, `.`, caratteri di controllo e slash finali sono tutti rifiutati prima di qualsiasi apply, e il reindirizzamento via symlink viene colto di nuovo in fase di apply.
- **Cancellare fuori dal modulo.** Le voci `delete[]` passano la stessa validazione di path.
- **Iniettare un comando.** Nessun valore del manifest viene interpolato in una shell o in `awk system()`; `sha256` deve essere esadecimale puro a 64 cifre o l'intero manifest viene rifiutato.
- **Spedire codice non firmato a un'installazione pubblica.** `hardened` rende la firma obbligatoria, e il profilo è fail-closed per inversione, così nessun typo o valore manomesso lo declassa.
- **Servire qui il feed firmato di un altro modulo.** Il campo `module` firmato deve essere uguale a questo `MODID`.
- **Riportarti indietro.** Il downgrade è bloccato in `hardened`.
- **Corrompere un blob non rilevato.** Ogni blob scaricato viene ri-hashato rispetto allo `sha256` del manifest in entrambi i profili; una non corrispondenza dopo tre tentativi aborta la fase senza nulla applicato.
- **Scambiare in un falso fetcher root.** Il `curl` bootstrappato viene controllato per firma e hash prima di essere installato o eseguito, in ogni profilo.
- **Applicare a metà un aggiornamento corrotto.** La transazione raggiunge `DONE` solo quando un re-hash di tutto corrisponde; un apply fallito fa rollback invece di sovrascrivere senza un backup.

---

Vedi anche: [[Feed Format]] per lo schema del manifest, [[Engine]] per la transazione in cui vivono questi controlli, e [[Architecture]] per il quadro generale.
