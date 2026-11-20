# Producer

De **producer** is de pc- / release-zijde van VDLU: de kleine set tools die een afgewerkte moduleboom veranderen in een gesigneerde, inhoudsgeadresseerde feed waarvan het apparaat kan updaten. Niets hiervan draait op de telefoon. Deze tools draaien op je release-machine (of, voor de delen die dat veilig toelaten, in CI).

Er zijn er vier:

| Tool | Draait op | Taal | Taak |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | De definitieve moduleboom doorlopen tot `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Een ed25519-signeringssleutelpaar genereren |
| `vdlu-sign` | PC | sh + openssl | `key_id` + handtekening in een manifest injecteren, ter plekke |
| `vdlu-gc` | PC | python3 | Wees-blobs uit een gepubliceerde feed opschonen (fail-safe) |

De release-flow is drie stappen, eenmaal per release gedaan: **packen, dan signeren, dan publiceren**. `vdlu-keygen` is een eenmalige opzet, en `vdlu-gc` is huishouding die je draait wanneer de feed groeit. Alles wat de producer uitzendt voldoet aan de [[Feed Format]], wat is wat de engine op het apparaat verbruikt.

---

## vdlu-pack

`vdlu-pack` neemt de **exacte boom die je `.zip` meelevert** (de definitieve boom, nadat je build zijn eigen whitelist en ABI-snoei heeft toegepast) en produceert de feed ervoor.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Het schrijft twee dingen in `<out_dir>`:

- `manifest.json` - de complete beschrijving van de doelboom (elk bestand met zijn `sha256`, `size`, `mode`, encoding en herstartklasse), nog steeds **ongesigneerd** (de `key_id`- en `sig`-velden zijn lege placeholders).
- `blobs/<sha256>` (of `blobs/<sha256>.gz`) - één blob per afzonderlijke bestandsinhoud.

### Inhoudsgeadresseerd en dedupliceert

Elke blob is genoemd naar de **sha256 van zijn originele (ongecomprimeerde) inhoud**. Omdat de naam de hash is, landt identieke inhoud op dezelfde blob. `vdlu-pack` schrijft een blob alleen als die nog niet aanwezig is, dus:

- Een bestand dat niet veranderde behoudt dezelfde blobnaam, en wordt nooit herschreven of herpusht.
- Twee verschillende bestanden met identieke inhoud delen één blob.
- Een teruggedraaid bestand hergebruikt de blob die er al was van tevoren.

Publiceren is daarom **incrementeel door constructie**: over releases heen groeit `blobs/` alleen maar, en alleen echt nieuwe inhoud wordt toegevoegd. Het apparaat haalt op aan de hand van dezelfde hashes, dus het downloadt alleen de blobs die het nog niet heeft.

### Compressie (het `enc`-veld)

Voor elk bestand beslist `vdlu-pack` hoe de blob wordt opgeslagen:

- `gz` wanneer het bestand minstens 4096 bytes is **en** gzip (deterministisch `-9 -n`) minstens 10 procent bespaart.
- `raw` anders (kleine bestanden die on-the-wire gzip al dekt, of al-incompressibele data).
- Als `gzip` ontbreekt op de build-host, wordt alles `raw` opgeslagen. Packen faalt hier nooit op.

De `sha256` in het manifest is **altijd** van de originele inhoud; `enc` benoemt alleen hoe de blob toevallig wordt opgeslagen. Het apparaat decomprimeert `gz`-blobs met toybox `gunzip` en controleert dan de hash tegen het origineel.

### Herstartklasse en veiligheid

`vdlu-pack` tagt elk bestand ook met een herstart-`class` (`live`, `soft`, `reboot`) afgeleid van zijn pad, zodat de engine weet wat zonder herstart kan worden toegepast en wat moet worden gefaseerd. De regels en wat het apparaat met elke class doet worden behandeld in [[Reboot Handling]].

Een paar dingen die `vdlu-pack` bewust **niet** doet:

- Het volgt geen symlinks (het slaat ze over met een waarschuwing, zodat inhoud van buiten de boom, zoals een link naar een systeembestand, nooit in een blob kan lekken).
- Het slaat niet-reguliere bestanden over (directories, fifo's, devices).
- Het respecteert `SOURCE_DATE_EPOCH` voor de `built`-tijdstempel, zodat manifesten reproduceerbaar zijn.
- Het sluit een vaste set paden volledig uit van de feed (de trust-root, installer-steigers, en een paar andere). De volledige lijst, en waarom elk is uitgesloten, staat in [[Feed Format]].

### De `delete[]`-lijst

Geef `--prev <previous manifest.json>` door en `vdlu-pack` berekent `delete[]`: de paden die in de vorige release bestonden maar in deze weg zijn, zodat het apparaat ze verwijdert in plaats van wezen achter te laten. Uitgesloten paden worden nooit als deletes uitgezonden, zelfs niet wanneer ze in het vorige manifest voorkomen (zie [[Feed Format]] voor de exacte semantiek).

---

## vdlu-keygen

Een eenmalige stap. `vdlu-keygen` maakt het ed25519-signeringssleutelpaar voor je feed.

```sh
vdlu-keygen <id> <out_dir>
```

Het schrijft drie bestanden:

| Bestand | Wat het is | Waar het heen gaat |
|---|---|---|
| `<id>.pem` | De **private** signeringssleutel (mode `0600`) | Blijft op je release-machine. Nooit. |
| `<id>.pub` | De publieke sleutel als PEM | Alleen pc-zijdige tooling |
| `<id>.pub.raw` | De publieke sleutel als **rauwe 32 bytes** | Meegeleverd als de keyring-entry op het apparaat van de module |

De rauwe publieke sleutel van 32 bytes is wat de verifier op het apparaat leest (die draagt geen `openssl`, dus kan de PEM niet lezen). Je bedt `<id>.pub.raw` in de module in als `vdlu/keyring/<id>.pub`. De PEM is alleen voor pc-zijdig gebruik. Deze splitsing, en hoe sleutelrotatie werkt, wordt uitgelegd in [[Security and Trust Model]].

> De private `.pem` is het enige geheim in het hele systeem. Houd hem van elk apparaat en buiten elke repository-push. Zie de CI-noot hieronder.

---

## vdlu-sign

`vdlu-sign` neemt het ongesigneerde manifest dat `vdlu-pack` produceerde en signeert het **ter plekke**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Het zet het `key_id`-veld, berekent de canonieke vorm van het manifest, en schrijft de ed25519-handtekening (base64) in het `sig`-veld. De handtekening is over een precieze byte-transformatie van het manifest, zodat de pc en het apparaat exact dezelfde gesigneerde bytes afleiden zonder JSON-library op het apparaat. Die transformatie (de **canonicalisatie**) is de allerbelangrijkste invariant in het formaat, en is volledig gedocumenteerd in [[Feed Format]].

De private sleutel wordt alleen hier gelezen, op jouw machine, en verlaat die nooit.

### De signeringssleutel blijft buiten CI

Dit is een bewust ontwerppunt. CI kan `vdlu-pack` draaien en een perfect geldige **keyless baseline** produceren (een ongesigneerd seed-manifest; zie [[Feed Format]]), zodat een verse installatie current wordt geboren zonder dat CI ooit een private sleutel aanraakt. Het daadwerkelijke signeren van de gepubliceerde feed doe jij, lokaal, met `vdlu-sign`. Op die manier is de signeringssleutel 100 procent buiten CI, en alleen de feed die je met de hand publiceert is gesigneerd.

---

## vdlu-gc

Omdat blobs inhoudsgeadresseerd en onveranderlijk zijn, groeit `blobs/` alleen maar: `vdlu-pack` voegt toe, het verwijdert nooit. Over vele releases heen hoopt de feed (en de Pages-site die die host) blobs op waarnaar geen huidig manifest meer verwijst. `vdlu-gc` snoeit die wezen weg.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Het bouwt de **behouden set** manifesten: het huidige `manifest.json`, plus de laatste `N` gearchiveerde manifesten op versie (standaard `N=3`, wat een rollback-marge geeft), plus alle die je met `--keep` noemt. Een blob waarnaar **geen** behouden manifest verwijst is een wees en is een kandidaat voor verwijdering. De behouden set is een vereniging, dus een blob blijft zolang een behouden release die nog nodig heeft; een apparaat dat op een oudere behouden versie zit verliest zijn fetch nooit.

`vdlu-gc` is gebouwd om veilig te zijn:

- **Dry-run standaard.** Zonder `--apply` print het alleen wat het *zou* verwijderen. Je voegt `--apply` toe om daadwerkelijk te verwijderen.
- **Fail-safe.** Als het helemaal geen behouden manifest vindt, weigert het te snoeien in plaats van te riskeren een feed leeg te maken.
- **Retentie per referentie, niet per datum.** Een blob wordt bewaard omdat een behouden manifest ernaar wijst, nooit vanwege een tijdstempel.

Push na het snoeien de kleinere feed naar je host. Spreid de schrijfbewerkingen uit als je host batch-schrijfbewerkingen rate-limit.

---

## Alles samengenomen

Een typische release, van begin tot eind:

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

Voor het volledige uitgewerkte voorbeeld van VDLU in een module overnemen, zie [[Quick Start]]. Voor de on-wire vorm van alles wat de producer uitzendt, zie [[Feed Format]]. Voor de redenering achter de sleutelbehandeling en wat buiten de feed wordt gehouden, zie [[Security and Trust Model]].
