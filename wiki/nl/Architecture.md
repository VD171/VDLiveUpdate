# Architecture

VDLU heeft twee kanten, verbonden door één ding in het midden. Op de pc verandert de [[Producer]] een moduleboom in een gesigneerde, inhoudsgeadresseerde feed. Op het apparaat leest de [[Engine]] die feed, bepaalt wat er is veranderd en past het toe. De naad tussen de twee is het **gesigneerde manifest plus de blob-opslag** (de [[Feed Format]]). Niets anders overbrugt de kloof.

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

De twee kanten delen nooit een runtime. De Producer gebruikt `python3` en `openssl`; de Engine is puur POSIX `sh` met toybox en een ingebedde `ed25519-mini`. Ze zijn het alleen eens omdat beide **dezelfde canonieke bytes** uit een manifest afleiden (zie [[Security and Trust Model]]). De WebUI is een dun, vanilla-JS-paneel dat de engine aanstuurt via de root-manager-brug en zijn voortgangsjournal leest; het bevat geen eigen update-logica. Zie [[WebUI]].

## De twee kanten

| Kant | Draait op | Gebouwd uit | Taak |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | De moduleboom doorlopen tot `manifest.json` + `blobs/`, signeren, wezen opschonen |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | De geinstalleerde boom tegen de feed diffen, delta's ophalen, toepassen, committen |
| [[WebUI]] | device (webview) | vanilla JS/CSS | Updates triggeren, voortgang tonen, config bewerken, de herstartbanner tonen |

## De update-pijplijn

Elke update is één transactie, uitgevoerd in een vaste volgorde:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` is deze fase, alleen-lezen). De engine downloadt alleen het manifest, draait `validate_plan()` over elk veld **voordat** er iets wordt aangeraakt, en vergelijkt de feed daarna met `current.json` om een plan per bestand te bouwen. Het verandert niets op schijf. Een apparaat dat voorloopt op de feed is een onschuldig "ahead"-resultaat, geen fout.
- **FETCH.** Downloadt alleen de blobs die het plan mist, naar `<sha>.part`, decomprimeert `gz`, controleert `sha256sum` tegen het manifest, en `mv`t elke geverifieerde blob atomair naar de cache. Een reeds gecachete blob (of een blob geseed vanuit een ongewijzigd lokaal bestand) wordt overgeslagen, zodat een terugdraaiing of een gedeeld bestand niets kost. Drie fouten op één blob breken de fase af zonder iets toe te passen. Een download die door het netwerkbeleid wordt geblokkeerd eindigt als `DEFERRED` (hervatbaar), niet als fout.
- **APPLY.** Gewone (`live` / `soft`) bestanden worden nu geschreven: back-up naar `rollback/<v>/`, een `.vdlu-tmp` schrijven, `chmod`, verifiëren, dan atomair `rename` over het doel. Bestanden van de herstartklasse worden gematerialiseerd in `staged/<path>.vdlu-new` en de live inode blijft ongemoeid. Een `delete[]`-entry wordt eerst geback-upt en dan verwijderd. Elke stap is idempotent: een bestand dat al op de doelhash staat wordt overgeslagen.
- **COMMIT.** Herhash elk live bestand; alleen als alles overeenkomt promoveert de engine `target.json` naar `current.json`. Als er iets is gefaseerd, eindigt de transactie in `PENDING_REBOOT`; anders `DONE`.

## Inhoudsgeadresseerd manifest en blobs

De feed is inhoudsgeadresseerd: het manifest somt de **volledige** doelboom op, elk bestand gedragen door zijn `sha256`, en de blob-opslag bewaart één kopie van elke afzonderlijke inhoud onder `blobs/<sha256>` (of `blobs/<sha256>.gz`).

- **Dedup.** Identieke inhoud waar dan ook in de boom, of tussen releases, is één blob. Publiceren is incrementeel: een blob waarvan de `sha256` al op de host bestaat wordt nooit opnieuw gepusht, en het apparaat haalt nooit inhoud opnieuw op die het al heeft.
- **sha256 is van het origineel.** De hash benoemt altijd de ongecomprimeerde inhoud; `enc` (`raw` of `gz`) legt alleen vast hoe die ene blob toevallig wordt opgeslagen. Het apparaat decomprimeert `gz` met toybox `gunzip`, zodat er geen extra compressor wordt meegeleverd.
- **Variant-stabiel.** Omdat het apparaat diffet tegen wat er daadwerkelijk is geinstalleerd, kan de feed een hele modulefamilie dragen; elke installatie haalt alleen de blobs op die zijn eigen variant compleet maken.

De volledige indeling veld voor veld staat in [[Feed Format]].

## Het hervatbare journal

Elke transactie is crashbestendig omdat zijn voortgang in een journal leeft (`journal.json`), en het vastgezette doel van de lopende transactie in `target.json` leeft. De toestandsmachine draait in een vaste volgorde:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Toestand | Betekenis |
|---|---|
| `PLANNED` | Plan gebouwd, nog niets opgehaald |
| `FETCHING` / `FETCHED` | Blobs downloaden / alle blobs aanwezig en geverifieerd |
| `APPLYING` / `APPLIED_LIVE` | Bestanden schrijven / alle live bestanden geschreven |
| `PENDING_REBOOT` | Een bestand van de herstartklasse is gefaseerd, wacht op de boot-swap |
| `DONE` | Herhash van alles kwam overeen; `current.json` gepromoveerd |
| `ERROR` | Harde fout; module onbeschadigd gelaten, live bestanden teruggezet vanuit `rollback/` |
| `DEFERRED` | Download tegengehouden door het netwerkbeleid; plan blijft bestaan, hervat later |

`DONE` wordt **alleen** bereikt zodra een herhash van alles overeenkomt, dus het journal beweert nooit dat een half toegepaste update compleet is. Een crash, een weggevallen netwerk of een herstart halverwege laat een hervatbaar journal achter; `update.sh resume` (of `boot`) pakt de draad op vanaf de huidige fase. Zie [[Engine]] voor de commandoset en de toestandsbestanden op het apparaat.

## Atomiciteit en rollback

Niets wordt ooit ter plekke overschreven en niets gaat verloren:

- **Atomaire schrijfbewerkingen.** Elk bestand landt via een temp (`.vdlu-tmp`) en een atomaire `rename` / `mv`, zodat een lezer nooit een half geschreven bestand ziet.
- **Back-up vóór overschrijven.** De vorige inhoud gaat naar `rollback/<version>/<path>` voordat het nieuwe bestand eroverheen wordt hernoemd (de laatste paar versies worden bewaard). Als een apply mislukt, worden de live bestanden teruggezet vanuit de rollback-kopie in plaats van beschadigd achtergelaten. Een mislukte back-up **breekt** het apply af in plaats van te overschrijven zonder vangnet.
- **Geserialiseerd.** Een `mkdir`-gebaseerde lock (`lock.d/`, aangezien `flock` onwerkbaar is op toybox, met herstel van verschaalde locks via PID) serialiseert gelijktijdige runs.

## Het herstartvrije principe

De meeste bestanden kunnen worden omgewisseld terwijl de module live is, dus VDLU past ze direct toe. Slechts drie klassen hebben een herstart nodig, omdat een live proces ze al heeft gemapt: een `.so` (geladen door Zygisk), een `/system`-overlay en een `sepolicy.rule`. Die worden **gefaseerd, nooit over een live inode geschreven**, en in één pre-zygote-stap bij de volgende boot ingewisseld. De volledige taxonomie en de boot-flow staan in [[Reboot Handling]].

## De fail-closed-vertrouwenshouding

De feed is het enige dat van de pc naar het apparaat oversteekt, dus de engine behandelt elke byte ervan als vijandig. `validate_plan()` draait in de DIFF-fase, vóór elke download, en verwerpt het hele manifest bij elk ongeldig veld. Handtekeningverificatie gebruikt een ingebedde `ed25519-mini` (geen `openssl` op het apparaat), de private sleutel raakt nooit een apparaat of CI aan, en het `hardened`-profiel is fail-closed door inversie, zodat een beschadigde profielwaarde nooit stilletjes een niet-gesigneerde feed kan accepteren. Het volledige model, de twee profielen en de dreigingen die elk beantwoordt staan in [[Security and Trust Model]].
