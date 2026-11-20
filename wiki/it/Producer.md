# Producer

Il **producer** è il lato PC / release di VDLU: il piccolo insieme di tool che trasformano un albero di modulo finito in un feed firmato e content-addressed da cui il dispositivo può aggiornarsi. Nulla qui gira sul telefono. Questi tool girano sulla tua macchina di release (o, per le parti che è sicuro farlo, in CI).

Sono quattro:

| Tool | Gira su | Linguaggio | Compito |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Percorrere l'albero finale del modulo in `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Generare una coppia di chiavi di firma ed25519 |
| `vdlu-sign` | PC | sh + openssl | Iniettare `key_id` + firma in un manifest, in loco |
| `vdlu-gc` | PC | python3 | Potare i blob orfani da un feed pubblicato (fail-safe) |

Il flusso di release è di tre passi, fatto una volta per release: **pack, poi sign, poi publish**. `vdlu-keygen` è un setup una tantum, e `vdlu-gc` è manutenzione che esegui quando il feed cresce. Tutto ciò che il producer emette è conforme al [[Feed Format]], che è ciò che l'engine sul dispositivo consuma.

---

## vdlu-pack

`vdlu-pack` prende l'**esatto albero che il tuo `.zip` spedisce** (l'albero finale, dopo che la tua build ha applicato la propria whitelist e la potatura ABI) e produce il feed per esso.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Scrive due cose in `<out_dir>`:

- `manifest.json` - la descrizione completa dell'albero target (ogni file con il suo `sha256`, `size`, `mode`, encoding e classe reboot), ancora **non firmato** (i campi `key_id` e `sig` sono placeholder vuoti).
- `blobs/<sha256>` (oppure `blobs/<sha256>.gz`) - un blob per contenuto di file distinto.

### Content-addressed e deduplicante

Ogni blob è nominato dallo **sha256 del suo contenuto originale (non compresso)**. Poiché il nome è l'hash, un contenuto identico atterra sullo stesso blob. `vdlu-pack` scrive un blob solo se non è già presente, quindi:

- Un file che non è cambiato mantiene lo stesso nome di blob, e non viene mai riscritto o ri-pushato.
- Due file diversi con contenuto identico condividono un solo blob.
- Un file ripristinato riusa il blob che era già li da prima.

La pubblicazione è quindi **incrementale per costruzione**: fra le release, `blobs/` cresce solo, e viene aggiunto solo contenuto genuinamente nuovo. Il dispositivo scarica per gli stessi hash, quindi scarica solo i blob che non possiede già.

### Compressione (il campo `enc`)

Per ogni file, `vdlu-pack` decide come memorizzare il blob:

- `gz` quando il file è di almeno 4096 byte **e** gzip (deterministico `-9 -n`) risparmia almeno il 10 percento.
- `raw` altrimenti (file piccoli che il gzip on-the-wire già copre, o dati già incomprimibili).
- Se `gzip` manca sull'host di build, tutto viene memorizzato `raw`. Il packing non fallisce mai per questo.

Lo `sha256` nel manifest è **sempre** del contenuto originale; `enc` nomina solo come il blob risulta essere memorizzato. Il dispositivo decomprime i blob `gz` con `gunzip` di toybox e poi verifica l'hash rispetto all'originale.

### Classe reboot e sicurezza

`vdlu-pack` etichetta anche ogni file con una `class` reboot (`live`, `soft`, `reboot`) derivata dal suo path, così l'engine sa cosa può essere applicato senza un riavvio e cosa deve essere messo in staging. Le regole e cosa il dispositivo fa con ciascuna classe sono trattate in [[Reboot Handling]].

Alcune cose che `vdlu-pack` deliberatamente **non** fa:

- Non segue i symlink (li salta con un warning, così contenuto esterno all'albero, come un link a un file di sistema, non può mai filtrare in un blob).
- Salta i file non regolari (directory, fifo, device).
- Rispetta `SOURCE_DATE_EPOCH` per il timestamp `built`, così i manifest sono riproducibili.
- Esclude un insieme fisso di path interamente dal feed (il trust root, l'impalcatura dell'installer, e alcuni altri). La lista completa, e il perché ciascuno è escluso, è in [[Feed Format]].

### La lista `delete[]`

Passa `--prev <previous manifest.json>` e `vdlu-pack` calcola `delete[]`: i path che esistevano nella release precedente ma sono spariti in questa, così il dispositivo li rimuove invece di lasciare orfani dietro di se. I path esclusi non vengono mai emessi come delete, anche quando compaiono nel manifest precedente (vedi [[Feed Format]] per la semantica esatta).

---

## vdlu-keygen

Un passo una tantum. `vdlu-keygen` crea la coppia di chiavi di firma ed25519 per il tuo feed.

```sh
vdlu-keygen <id> <out_dir>
```

Scrive tre file:

| File | Cos'è | Dove va |
|---|---|---|
| `<id>.pem` | La chiave di firma **privata** (mode `0600`) | Resta sulla tua macchina di release. Mai altrove. |
| `<id>.pub` | La chiave pubblica come PEM | Solo tooling lato PC |
| `<id>.pub.raw` | La chiave pubblica come **32 byte raw** | Spedita come voce del keyring del modulo sul dispositivo |

La chiave pubblica raw di 32 byte è ciò che il verificatore del dispositivo legge (non porta `openssl`, quindi non può leggere il PEM). Incorpori `<id>.pub.raw` nel modulo come `vdlu/keyring/<id>.pub`. Il PEM è solo per uso lato PC. Questa separazione, e come funziona la rotazione delle chiavi, è spiegata in [[Security and Trust Model]].

> **Un keyring a più chiavi deve vincolare `key_id`.** Se il keyring del modulo spedisce più di una chiave (per esempio la chiave di release più una chiave di feed di fingerprint a minore fiducia), l'engine non indovinerà quale possa firmare un aggiornamento di modulo. Imposta la config `key_id` sulla chiave, o sulle chiavi separate da virgola durante una finestra di rotazione, autorizzata a firmare gli aggiornamenti; un keyring a chiave singola si vincola automaticamente e non richiede alcuna config. Questa è l'allowlist di aggiornamento modulo, trattata in [[Security and Trust Model]].

> Il `.pem` privato è l'unico segreto dell'intero sistema. Tienilo fuori da ogni dispositivo e fuori da ogni push di repository. Vedi la nota sulla CI più sotto.

---

## vdlu-sign

`vdlu-sign` prende il manifest non firmato prodotto da `vdlu-pack` e lo firma **in loco**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Imposta il campo `key_id`, calcola la forma canonica del manifest, e scrive la firma ed25519 (base64) nel campo `sig`. La firma è su una precisa trasformazione in byte del manifest, così che il PC e il dispositivo derivino esattamente gli stessi byte firmati senza alcuna libreria JSON sul dispositivo. Quella trasformazione (la **canonicalizzazione**) è l'invariante più importante del formato, ed è documentata per intero in [[Feed Format]].

La chiave privata viene letta solo qui, sulla tua macchina, e non la lascia mai.

### La chiave di firma resta fuori dalla CI

Questo è un punto di design deliberato. La CI può eseguire `vdlu-pack` e produrre una perfetta **baseline keyless** (un manifest seed non firmato; vedi [[Feed Format]]), così una nuova installazione nasce aggiornata senza che la CI tocchi mai una chiave privata. La firma effettiva del feed pubblicato la fai tu, localmente, con `vdlu-sign`. In questo modo la chiave di firma è al 100 percento fuori dalla CI, e solo il feed che pubblichi a mano viene firmato.

---

## vdlu-gc

Poiché i blob sono content-addressed e immutabili, `blobs/` cresce solo: `vdlu-pack` aggiunge, non rimuove mai. Nel corso di molte release il feed (e il sito Pages che lo ospita) accumula blob che nessun manifest corrente referenzia più. `vdlu-gc` pota quegli orfani.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Costruisce il **set trattenuto** di manifest: il `manifest.json` corrente, più gli ultimi `N` manifest archiviati per versione (default `N=3`, che dà un margine di rollback), più eventuali che nomini con `--keep`. Un blob referenziato da **nessun** manifest trattenuto è un orfano ed è un candidato per la rimozione. Il set trattenuto è un'unione, quindi un blob resta finché una qualunque release trattenuta ne ha ancora bisogno; un dispositivo fermo su una versione trattenuta più vecchia non perde mai il suo fetch.

`vdlu-gc` è costruito per essere sicuro:

- **Dry-run di default.** Senza `--apply`, stampa solo cosa *rimuoverebbe*. Aggiungi `--apply` per cancellare davvero.
- **Fail-safe.** Se non trova alcun manifest trattenuto, rifiuta di potare invece di rischiare di svuotare un feed.
- **Ritenzione per riferimento, non per data.** Un blob viene mantenuto perché un manifest trattenuto punta ad esso, mai a causa di un timestamp.

Dopo la potatura, pusha il feed più piccolo al tuo host. Distanzia le scritture se il tuo host limita il rate delle scritture in batch.

---

## Mettere tutto insieme

Una release tipica, da capo a fine:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Per l'esempio completo e svolto di adozione di VDLU in un modulo, vedi [[Quick Start]]. Per la forma on-wire di tutto ciò che il producer emette, vedi [[Feed Format]]. Per il ragionamento dietro la gestione delle chiavi e cosa viene tenuto fuori dal feed, vedi [[Security and Trust Model]].
