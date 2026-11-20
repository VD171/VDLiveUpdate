# Feed Format

Il **feed** è ciò che VDLU serve sul filo è ciò da cui il dispositivo si aggiorna. È una semplice directory statica, servibile da qualsiasi cosa (GitHub Pages, un target rsync, un path `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Il modulo stesso spedisce anche un file extra, `baseline.json`, dentro lo `.zip` (non servito dal feed). Il producer che costruisce tutto questo è descritto in [[Producer]]; questa pagina è il contratto on-wire.

---

## manifest.json

Il manifest è la descrizione completa di una release: ogni file nell'albero target, cosa cancellare, e la firma sull'intera cosa.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Campi

| Campo | Significato |
|---|---|
| `schema` | Versione di formato del manifest stesso (attualmente `1`). |
| `module` | L'id del modulo. Il dispositivo rifiuta il manifest se non corrisponde al proprio id di modulo, così un feed validamente firmato per un modulo diverso non può essere servito al suo posto. |
| `version` | Versione intera. L'engine aggiorna solo in avanti; un feed più vecchio del dispositivo è un benigno stato "ahead", non un errore. |
| `version_name` | Stringa di versione leggibile dall'uomo (per esempio `v106`). |
| `built` | Timestamp di build ISO 8601. Rispetta `SOURCE_DATE_EPOCH` per la riproducibilità. |
| `engine_min` | La versione minima dell'engine richiesta per applicare questo manifest. |
| `channel` | Canale di release (per esempio `stable`). |
| `key_id` | Quale chiave nel keyring del dispositivo ha firmato questo manifest. Seleziona la chiave pubblica per la verifica, e deve essere nell'allowlist di aggiornamento modulo dell'engine (vedi [[Security and Trust Model]]); una chiave meramente presente nel keyring ma non in allowlist viene rifiutata prima che la sua pubkey venga caricata. |
| `files[]` | L'albero target **completo** (non un diff). Ogni voce: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Path presenti nella release precedente ma ora spariti, da rimuovere per il dispositivo. |
| `sig` | La firma ed25519, base64. Vedi la canonicalizzazione più sotto. |

`files[]` descrive l'**intero** albero, non un delta. Il dispositivo calcola il delta da sé confrontando il manifest con ciò che ha già, e scarica solo i blob il cui `sha256` gli manca. Lo `sha256` è sempre del contenuto originale (non compresso); `enc` dice solo come quel blob è memorizzato in `blobs/`. Il significato di `class` è cosa il dispositivo fa con ciascun valore è trattato in [[Reboot Handling]].

---

## Canonicalizzazione (i byte firmati)

Questo è l'invariante più importante del formato. Il signer su PC e il verificatore sul dispositivo girano su runtime completamente diversi (openssl sul PC, toybox più un minuscolo verificatore embedded sul dispositivo, e **nessuna libreria JSON affatto** sul dispositivo). Devono comunque derivare gli esatti stessi byte da firmare e da verificare. La regola è quindi una deliberata **trasformazione in byte**, non una ri-serializzazione JSON.

**Passo 1: una forma di store fissa.** `vdlu-pack` scrive `manifest.json` compatto, con chiavi ordinate, UTF-8, includendo sempre `key_id` e `sig` (come stringhe vuote fino alla firma):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Passo 2: elimina solo `sig`.** La forma canonica è quell'esatto testo con **solo il campo `"sig"` rimosso**. Poiché le chiavi sono ordinate, `sig` compare sempre come `,"sig":"<value>",` racchiuso da `"schema"` prima e `"version"` dopo (entrambi sempre presenti), quindi rimuoverlo lascia testo ben formato. JSON fa l'escape di ogni `"` dentro un valore stringa come `\"`, quindi il token strutturale `"sig":"` è non ambiguo anche contro un filename che contiene letteralmente `"sig":"`.

La rimozione è una manciata di parameter expansion POSIX, identiche nel signer e nel verificatore, senza `sed` e senza `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Passo 3: firma l'hash di quello.** Il messaggio firmato/verificato è lo **sha256 esadecimale** (64 caratteri ASCII, nessun newline) della forma canonica. ed25519 firma quell'esadecimale.

Due conseguenze derivano da questo per costruzione:

- `key_id` fa parte della forma canonica (solo `sig` viene eliminato). `vdlu-sign` imposta `key_id` **prima** di hashare, così l'identità della chiave è coperta dalla firma.
- Che il placeholder `sig` sia vuoto (`"sig":""`, al momento della firma) o riempito (al momento della verifica), eliminarlo produce i byte canonici identici. Firma e verifica concordano automaticamente.

I due tool sh POSIX sono autoritativi. Un equivalente Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` poi sha256, esiste solo per fare il cross-check di essi.

Il ragionamento di fiducia attorno a tutto questo (perché la verifica è sul dispositivo, come `hardened` fallisce closed) vive in [[Security and Trust Model]].

---

## baseline.json (il seme di installazione)

Quando un modulo viene appena installato, dovrebbe già essere "aggiornato" per la propria versione spedita, senza un inutile self-update della versione appena installata. È ciò che fa `baseline.json`.

`baseline.json` viene spedito **dentro lo zip del modulo** (in `vdlu/baseline.json`), non sul feed. Su un'installazione fresca, l'engine semina il proprio record di "versione attiva" da esso, così il dispositivo nasce aggiornato, senza `from:0` e senza re-fetch di ciò che ha già.

Proprietà chiave:

- È una **copia keyless del manifest firmato** per la versione spedita: lo stesso output di `vdlu-pack`, lasciato non firmato (`key_id` e `sig` restano vuoti).
- **Non viene verificato.** L'engine lo tratta come un seme locale fidato perché è arrivato dentro lo zip flashato, che è il confine di fiducia dell'installazione. Solo un manifest *scaricato dal feed* passa attraverso la verifica della firma.
- Poiché non richiede firma, **la CI può generarlo keyless**, il che è ciò che tiene la chiave di firma interamente fuori dalla CI (vedi [[Producer]]).
- `vdlu-pack` **esclude `baseline.json` dal proprio manifest**, così il manifest non referenzia mai la baseline (sarebbe un loop di auto-riferimento: manifest verso baseline verso manifest).
- È **non fatale se assente**. Senza di esso, il dispositivo semplicemente parte da `from:0` al suo primo aggiornamento e scarica ciò che gli serve. Mai rotto, solo meno ottimale.

---

## Blob

Ogni contenuto di file distinto è un blob sotto `blobs/`, nominato dallo **sha256 del contenuto originale**:

- `blobs/<sha256>` per un blob raw.
- `blobs/<sha256>.gz` per un blob gzippato (il gzip viene mantenuto solo quando il file è di almeno 4096 byte e la compressione risparmia almeno il 10 percento).

Un blob viene memorizzato una volta, in un solo formato. Il content addressing da la deduplicazione gratis: contenuto invariato, condiviso o ripristinato mappa su un blob che esiste già, così il feed cresce solo per contenuto genuinamente nuovo, e il dispositivo scarica solo gli hash che gli mancano. Il dispositivo verifica lo `sha256` di ogni blob scaricato rispetto al manifest (dopo aver decompresso un blob `gz`) prima di usarlo.

---

## Cosa è escluso dal feed, e perché

Il feed porta **solo il contenuto proprio del modulo**. Un insieme fisso di path viene tenuto fuori di proposito. `vdlu-pack` applica un predicato di esclusione sia quando percorre l'albero sia quando calcola `delete[]`.

| Escluso | Perché |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (il trust root: chiavi pubbliche raw + il binario verificatore) | **Questa è la ragione di sicurezza centrale.** L'ancora di fiducia è **flash-only**. Se il keyring o il verificatore fossero consegnabili dal feed, un manifest potrebbe sovrascrivere proprio la cosa che lo valida. Tenerli fuori dal filo significa che un manifest non può mai riscrivere l'ancora di fiducia sul dispositivo. |
| `vdlu/baseline.json` | È una copia del manifest firmato (il seme di installazione); impacchettarlo sarebbe un loop di auto-riferimento. |
| `.vd/` infrastruttura di flash | Impalcatura del flash-gate che viene spedita nello zip, mai applicata dal vivo. |
| `update.json`, `update-mmrl.json` | La loro size/sha vengono riempite dalla CI *dopo* che gli zip sono costruiti, quindi la copia spedita differisce da qualsiasi copia del feed. Darli in pasto causerebbe un fetch fantasma di un singolo file al primo self-update di ogni installazione, e sono comunque vestigiali sul dispositivo (il manager legge il JSON di aggiornamento raw remoto). |
| `META-INF/`, `customize.sh` (impalcatura dell'installer) | Consumati dal manager in fase di **flash** e non mantenuti nel modulo installato. Non sono contenuto VDLU; servirli spreca blob e, se uno dovesse mai cambiare fra versioni, verrebbe scritto come file di installer nella directory live del modulo. |
| Companion `.sha256` per file | Appartengono solo allo zip flashabile, diventano stale dopo un aggiornamento incrementale, e raddoppierebbero il manifest. |
| File di dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Mai spediti al dispositivo; servirli spreca blob e fa churn del manifest firmato a ogni modifica di doc. |

Il ragionamento dietro l'esclusione del trust-root è ampliato in [[Security and Trust Model]].

---

## Semantica di delete[]

`delete[]` dice al dispositivo quali path rimuovere, così un file eliminato fra le release non rimane sul dispositivo come orfano. Viene calcolato passando `--prev <previous manifest.json>` a `vdlu-pack`: un path che era nella release precedente e non è in quella corrente diventa una voce delete.

La regola importante: **i path esclusi non vengono mai emessi come delete, nemmeno con `--prev`.** Ogni path precedente viene fatto passare attraverso lo stesso predicato di esclusione usato quando si percorre l'albero. Se un `--prev` punta a un manifest più vecchio che elencava ancora path ora esclusi (un `baseline.json` vagante, `META-INF/*`, una voce del keyring, e così via), quei path **non** vengono trasformati in voci delete. Un path escluso non è mai stato contenuto del feed, quindi non spetta a VDLU cancellarlo, e al dispositivo non viene mai ordinato di rimuovere un file che non è stato servito attraverso il feed. È questo che evita che la lista di esclusione si ritorca mai come istruzione distruttiva.
