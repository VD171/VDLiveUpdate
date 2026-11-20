# Feed Format

De **feed** is wat VDLU over de draad serveert en waarvan het apparaat updatet. Het is een gewone statische directory, serveerbaar door van alles (GitHub Pages, een rsync-doel, een `file://`-pad):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

De module zelf levert ook één extra bestand mee, `baseline.json`, binnen de `.zip` (niet geserveerd vanuit de feed). De producer die dit alles bouwt is beschreven in [[Producer]]; deze pagina is het on-wire-contract.

---

## manifest.json

Het manifest is de complete beschrijving van één release: elk bestand in de doelboom, wat te verwijderen, en de handtekening over het geheel.

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

### Velden

| Veld | Betekenis |
|---|---|
| `schema` | Formaatversie van het manifest zelf (momenteel `1`). |
| `module` | De module-id. Het apparaat verwerpt het manifest als die niet overeenkomt met zijn eigen module-id, zodat een geldig gesigneerde feed voor een andere module niet in plaats daarvan kan worden geserveerd. |
| `version` | Integer-versie. De engine updatet alleen voorwaarts; een feed ouder dan het apparaat is een onschuldige "ahead"-toestand, geen fout. |
| `version_name` | Door mensen leesbare versie-string (bijvoorbeeld `v106`). |
| `built` | ISO 8601-build-tijdstempel. Respecteert `SOURCE_DATE_EPOCH` voor reproduceerbaarheid. |
| `engine_min` | De minimale engine-versie vereist om dit manifest toe te passen. |
| `channel` | Release-kanaal (bijvoorbeeld `stable`). |
| `key_id` | Welke sleutel in de keyring van het apparaat dit manifest signeerde. Selecteert de publieke sleutel voor verificatie, en moet op de module-update-allowlist van de engine staan (zie [[Security and Trust Model]]); een sleutel die slechts in de keyring aanwezig is maar niet op de allowlist staat, wordt afgewezen voordat zijn pubkey wordt geladen. |
| `files[]` | De **complete** doelboom (geen diff). Elke entry: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Paden aanwezig in de vorige release maar nu weg, voor het apparaat om te verwijderen. |
| `sig` | De ed25519-handtekening, base64. Zie de canonicalisatie hieronder. |

`files[]` beschrijft de **hele** boom, geen delta. Het apparaat berekent het delta zelf door het manifest te vergelijken met wat het al heeft, en haalt alleen de blobs op waarvan het de `sha256` mist. De `sha256` is altijd van de originele (ongecomprimeerde) inhoud; `enc` zegt alleen hoe die blob in `blobs/` is opgeslagen. De betekenis van `class` en wat het apparaat met elke waarde doet wordt behandeld in [[Reboot Handling]].

---

## Canonicalisatie (de gesigneerde bytes)

Dit is de allerbelangrijkste invariant in het formaat. De pc-signer en de verifier op het apparaat draaien op volledig verschillende runtimes (openssl op de pc, toybox + een piepkleine ingebedde verifier op het apparaat, en **helemaal geen JSON-library** op het apparaat). Ze moeten toch exact dezelfde bytes afleiden om te signeren en te verifiëren. De regel is daarom een bewuste **byte-transformatie**, geen JSON-herserialisatie.

**Stap 1: een vaste store-vorm.** `vdlu-pack` schrijft `manifest.json` compact, met gesorteerde sleutels, UTF-8, altijd inclusief `key_id` en `sig` (als lege strings tot gesigneerd):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Stap 2: verwijder alleen `sig`.** De canonieke vorm is die exacte tekst met **alleen het `"sig"`-veld verwijderd**. Omdat de sleutels gesorteerd zijn, verschijnt `sig` altijd als `,"sig":"<value>",` omsloten door `"schema"` ervoor en `"version"` erna (beide altijd aanwezig), zodat het verwijderen ervan welgevormde tekst achterlaat. JSON escapet elke `"` binnen een string-waarde als `\"`, zodat het structurele token `"sig":"` ondubbelzinnig is, zelfs tegen een bestandsnaam die letterlijk `"sig":"` bevat.

De verwijdering is een handvol POSIX-parameteruitbreidingen, identiek in de signer en de verifier, zonder `sed` en zonder `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Stap 3: signeer de hash daarvan.** Het gesigneerde/geverifieerde bericht is de **sha256 hex** (64 ASCII-tekens, geen newline) van de canonieke vorm. ed25519 signeert die hex.

Twee gevolgen vallen hieruit door constructie:

- `key_id` is onderdeel van de canonieke vorm (alleen `sig` wordt verwijderd). `vdlu-sign` zet `key_id` **voor** het hashen, zodat de sleutelidentiteit door de handtekening wordt gedekt.
- Of de `sig`-placeholder nu leeg is (`"sig":""`, op sign-tijd) of gevuld (op verify-tijd), het verwijderen ervan levert de identieke canonieke bytes. Signeren en verifiëren komen automatisch overeen.

De twee POSIX-sh-tools zijn gezaghebbend. Een Python-equivalent, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` dan sha256, bestaat alleen om ze te kruiscontroleren.

De vertrouwensredenering rondom dit alles (waarom verificatie op het apparaat is, hoe `hardened` fail-closed is) leeft in [[Security and Trust Model]].

---

## baseline.json (de install-seed)

Wanneer een module vers is geinstalleerd, zou die al "current" moeten zijn voor zijn eigen meegeleverde versie, zonder onnodige zelf-update van de versie die zojuist is geinstalleerd. Dat is wat `baseline.json` doet.

`baseline.json` levert mee **binnen de module-zip** (op `vdlu/baseline.json`), niet op de feed. Bij een verse installatie seedt de engine zijn "actieve versie"-record ervan, zodat het apparaat current wordt geboren, zonder `from:0` en zonder herdownload van wat het al heeft.

Kerneigenschappen:

- Het is een **keyless kopie van het gesigneerde manifest** voor de meegeleverde versie: dezelfde `vdlu-pack`-output, ongesigneerd gelaten (`key_id` en `sig` blijven leeg).
- Het wordt **niet geverifieerd**. De engine behandelt het als een lokale vertrouwde seed omdat het binnen de geflashte zip arriveerde, wat de install-vertrouwensgrens is. Alleen een manifest *opgehaald van de feed* gaat door handtekeningverificatie.
- Omdat het geen handtekening nodig heeft, **kan CI het keyless genereren**, en dat is wat de signeringssleutel volledig buiten CI houdt (zie [[Producer]]).
- `vdlu-pack` **sluit `baseline.json` uit van zijn eigen manifest**, zodat het manifest nooit naar de baseline verwijst (dat zou een zelfverwijzingslus zijn: manifest naar baseline naar manifest).
- Het is **niet-fataal indien afwezig**. Zonder dit start het apparaat simpelweg vanaf `from:0` bij zijn eerste update en haalt op wat het nodig heeft. Nooit kapot, alleen minder optimaal.

---

## Blobs

Elke afzonderlijke bestandsinhoud is één blob onder `blobs/`, genoemd naar de **sha256 van de originele inhoud**:

- `blobs/<sha256>` voor een rauwe blob.
- `blobs/<sha256>.gz` voor een gezipte blob (gzip wordt alleen bewaard wanneer het bestand minstens 4096 bytes is en compressie minstens 10 procent bespaart).

Een blob wordt eenmaal opgeslagen, in één formaat. Inhoudsadressering geeft deduplicatie gratis: ongewijzigde, gedeelde of teruggedraaide inhoud mapt naar een blob die al bestaat, zodat de feed alleen groeit door echt nieuwe inhoud, en het apparaat alleen de hashes downloadt die het mist. Het apparaat controleert de `sha256` van elke gedownloade blob tegen het manifest (na het decomprimeren van een `gz`-blob) voordat het die gebruikt.

---

## Wat van de feed is uitgesloten, en waarom

De feed draagt **alleen de eigen inhoud van de module**. Een vaste set paden wordt er met opzet buiten gehouden. `vdlu-pack` past één uitsluitingspredicaat toe, zowel bij het doorlopen van de boom als bij het berekenen van `delete[]`.

| Uitgesloten | Waarom |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (de trust-root: rauwe publieke sleutels + het verifier-binary) | **Dit is de kernbeveiligingsreden.** Het vertrouwensanker is **flash-only**. Als de keyring of verifier via de feed leverbaar waren, zou een manifest juist datgene kunnen overschrijven dat het valideert. Ze van de draad houden betekent dat een manifest het vertrouwensanker op het apparaat nooit kan herschrijven. |
| `vdlu/baseline.json` | Het is een kopie van het gesigneerde manifest (de install-seed); het packen ervan zou een zelfverwijzingslus zijn. |
| `.vd/` flash-infrastructuur | Flash-gate-steigers die in de zip meeleveren, nooit live toegepast. |
| `update.json`, `update-mmrl.json` | Hun size/sha worden door CI ingevuld *nadat* de zips zijn gebouwd, zodat de meegeleverde kopie afwijkt van elke feed-kopie. Ze voeden zou een fantoom fetch van één bestand veroorzaken bij de eerste zelf-update van elke installatie, en ze zijn op het apparaat toch vestigiaal (de manager leest de externe rauwe update-JSON). |
| `META-INF/`, `customize.sh` (installer-steigers) | Verbruikt door de manager op **flash**-tijd en niet bewaard in de geinstalleerde module. Ze zijn geen VDLU-inhoud; ze serveren verspilt blobs en, als een ervan ooit tussen versies veranderde, zou die als installerbestand in de live moduledirectory worden geschreven. |
| Per-bestand `.sha256`-companions | Ze horen alleen bij de flashbare zip, verschalen na een incrementele update, en zouden het manifest verdubbelen. |
| Dev-/doc-bestanden (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nooit naar het apparaat geleverd; ze serveren verspilt blobs en karnt het gesigneerde manifest bij elke doc-bewerking. |

De redenering achter de trust-root-uitsluiting is uitgewerkt in [[Security and Trust Model]].

---

## delete[]-semantiek

`delete[]` vertelt het apparaat welke paden te verwijderen, zodat een bestand dat tussen releases is weggevallen niet als wees op het apparaat blijft hangen. Het wordt berekend door `--prev <previous manifest.json>` aan `vdlu-pack` door te geven: een pad dat in de vorige release zat en niet in de huidige wordt een delete-entry.

De belangrijke regel: **uitgesloten paden worden nooit als deletes uitgezonden, zelfs niet met `--prev`.** Elk vorig pad wordt door hetzelfde uitsluitingspredicaat gehaald dat wordt gebruikt bij het doorlopen van de boom. Als een `--prev` naar een ouder manifest wijst dat nog nu-uitgesloten paden opsomde (een verdwaalde `baseline.json`, `META-INF/*`, een keyring-entry, enzovoort), worden die paden **niet** in delete-entries omgezet. Een uitgesloten pad was nooit feed-inhoud, dus het is niet aan VDLU om het te verwijderen, en het apparaat wordt nooit opgedragen een bestand te verwijderen dat niet via de feed is geserveerd. Dit is wat voorkomt dat de uitsluitingslijst ooit terugkeert als een destructieve instructie.
