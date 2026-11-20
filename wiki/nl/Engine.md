# Engine

De engine is de apparaatzijde van VDLU: het deel dat op de telefoon draait, bepaalt wat er is veranderd, het downloadt en het toepast. Het is een enkel POSIX-shellscript, `engine/update.sh`, plus een piepkleine handtekeningcontroleur, `engine/vdlu-verify`. Beide worden in de host-module vendored op `<module>/vdlu/` en door root uitgevoerd.

De hele engine is gebouwd rond één idee: een update is een **hervatbare transactie**. Als de telefoon halverwege wordt herstart, gedood of het netwerk verliest, pakt de volgende run precies op waar die stopte, en de module wordt nooit half toegepast achtergelaten terwijl die doet alsof hij klaar is.

Wil je eerst het grote plaatje, zie [[Architecture]]. Voor hoe updates een herstart vermijden waar het kan, zie [[Reboot Handling]].

## Geschreven voor het apparaat, niet voor je laptop

`update.sh` is puur POSIX `sh`. Het draait onder mksh, busybox of toybox, zonder bash-only functies, en het slaagt voor `sh -n`. Dat is belangrijk omdat de omgeving op een geroot Android-apparaat klein en streng is.

In het bijzonder is er geen `jq`. VDLU parst `manifest.json` met een kleine gron-achtige flattener geschreven in `awk`: het loopt teken voor teken door de JSON en zendt één `path<TAB>value`-regel uit per blad (bijvoorbeeld `files/0/sha256<TAB>ab..` of `version<TAB>6`). De shell leest die regels vervolgens met `grep` en `cut`. Dit werkt op zowel compacte als pretty-printed JSON, en het shelt nooit uit naar een JSON-tool die er niet is.

De engine hangt alleen af van wat toybox al meelevert (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), de ingebedde `ed25519-mini`-verifier, en, voor `https://`-feeds, een kleine statische `curl` die eenmalig wordt opgehaald en geverifieerd. Een `file://`-feed heeft helemaal geen `curl` nodig.

## De zes commando's

Je roept de engine aan met de paden van de module in de omgeving en één commando:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Exitcode `0` betekent succes; elke andere code betekent een fout, met de reden naar stderr geprint.

| Commando | Wat het doet |
|---|---|
| `check` | Alleen-lezen diff. Downloadt het manifest, vergelijkt het met wat er is geinstalleerd, en print een JSON-samenvatting van één regel: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Verandert niets op schijf. Als het apparaat nieuwer is dan de feed (een geblokkeerde downgrade) meldt het `{"update":false,"ahead":true,...}` met exit `0`, geen fout. |
| `run` | De volledige live-cyclus: DIFF, FETCH, APPLY, COMMIT. Past elk live bestand direct toe en faseert de enkele bestanden van de herstartklasse. Respecteert `cancel`. Schrijft voortgang naar `journal.json`. |
| `resume` | Vervolgt een transactie die werd onderbroken, beginnend vanaf de fase waarin die zich bevond. Idempotent. Het wisselt **geen** gefaseerde `.so` om (dat is voorbehouden aan `boot`). |
| `boot` | Het pre-zygote-pad. Doet een `resume` en wisselt vervolgens alle gefaseerde `*.vdlu-new`-bestanden op hun plaats, waarmee `PENDING_REBOOT` sluit tot `DONE`. Als er geen openstaande transactie is, draait het een verse cyclus en past het alles toe, inclusief de `.so`, in die ene boot. |
| `status` | Print `journal.json`, of `{"state":"idle"}` wanneer er niets gaande is. |
| `cancel` | Maakt een `cancel`-marker. Een lopende `run` stopt netjes bij het volgende veilige punt. |

Het `check`-commando is bewust goedkoop, zodat de UI je op elk netwerk kan vertellen dat er een update bestaat. De daadwerkelijke download wordt apart gestuurd (zie de fetch-fase hieronder).

## De transactie, stap voor stap

Elke `run` beweegt door een vaste toestandsmachine, vastgelegd in `journal.json` zodat de WebUI (en jij) kan meekijken:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** De engine haalt `manifest.json` op, valideert elk veld (zie hieronder en [[Security and Trust Model]]), en diffet de gesigneerde doelboom tegen `current.json`, het manifest van de reeds geinstalleerde versie. Het resultaat is een plan per bestand geschreven naar `plan.tsv`: één rij per bestand, met zijn class, doelhash, mode en voortgangstoestand. Bestanden die al op de doelhash staan worden gemarkeerd om over te slaan.

**FETCH.** Voor elk nog benodigd bestand downloadt de engine zijn inhoudsgeadresseerde blob van `<source>/blobs/<sha>` (of `<sha>.gz` indien gecomprimeerd), naar een `.part`-bestand. Als de blob gzipped is wordt die gedecomprimeerd, waarna zijn SHA-256 tegen het manifest wordt gecontroleerd. Alleen bij een match wordt die atomair naar `blobs/<sha>` ge-`mv`-d. Een blob die al gecachet is met een correcte hash wordt volledig overgeslagen, en een ongewijzigd lokaal bestand kan de cache seeden zonder enige download. Drie fouten op dezelfde blob breken de fase af met niets toegepast. De fase bereikt `FETCHED` pas zodra elke blob in het plan aanwezig en geverifieerd is. Voor de [[Feed Format]] waaruit deze blobs komen, zie die pagina.

De fetch wordt door netwerkbeleid gestuurd: een feed kan beperkt zijn tot alleen wifi, alleen mobiel, of elk netwerk. Wanneer het huidige netwerk niet is toegestaan, faalt de fetch niet; het gaat de onschuldige `DEFERRED`-toestand in, houdt het plan en doel vastgezet, en hervat bij de volgende check of boot zodra het juiste netwerk verschijnt. Er worden in de tussentijd geen data verbruikt.

**APPLY.** Alleen ooit ingegaan vanuit `FETCHED`. Voor elk bestand handelt de engine naar class:

- `live`- en `soft`-bestanden: back-up het huidige bestand naar `rollback/<version>/<path>`, schrijf de nieuwe inhoud naar een `.vdlu-tmp`-broer, `chmod` het, verifieer zijn hash, dan atomair `rename` over het doel. Een bestand dat al op de doelhash staat wordt overgeslagen.
- `reboot`-bestanden (een `.so`, een `/system`-overlay, een `sepolicy.rule`): materialiseer in `staged/<path>.vdlu-new`. De live inode wordt hier nooit aangeraakt. Zie [[Reboot Handling]].
- verwijderingen: back-up, dan verwijderen. Verwijderingen worden pas helemaal aan het eind toegepast, op een schone `DONE`, nooit terwijl er nog een herstart in afwachting is.

**COMMIT.** De engine herhasht elk live- en soft-bestand dat het aanraakte. Alleen wanneer die allemaal overeenkomen schrijft het `current.json`, waarmee de nieuwe versie de diff-basis wordt. Als er een bestand van de herstartklasse is gefaseerd, wordt de toestand `PENDING_REBOOT` in plaats van `DONE`; de swap en de laatste herverificatie gebeuren later onder het `boot`-commando.

## Fail-safe door constructie

De garanties die dit veilig maken om onbeheerd te draaien:

- **Niets wordt als `DONE` gemarkeerd zonder een overeenkomende herhash.** `DONE` wordt pas bereikt nadat elk toegepast bestand is teruggelezen en zijn SHA-256 is vergeleken met het manifest. Een gefaseerd herstartbestand dwingt `PENDING_REBOOT` af, nooit een valse `DONE`.
- **Niets gaat verloren.** Elk bestand wordt geback-upt naar `rollback/<version>/` voordat het wordt overschreven, en de laatste drie versies worden bewaard. Als een apply mislukt, worden de live bestanden teruggezet vanuit de back-up; de module wordt nooit half toegepast achtergelaten terwijl die daarover liegt. `apply_live` breekt regelrecht af als de back-upstap mislukt, in plaats van te overschrijven zonder weg terug.
- **Alles is atomair.** Nieuwe inhoud landt via `rename`/`mv` over het doel, zodat een lezer ooit ofwel het oude bestand of het nieuwe ziet, nooit een afgekapte schrijfbewerking.
- **Hervatbaar na een crash of kill.** Een crash, een verloren netwerk of een herstart halverwege laat een geldig journal achter; `resume` (of `boot`) vervolgt vanaf de vastgelegde fase. Het ontwerp gaat ervan uit dat het onderbroken zal worden.
- **Degradeert netjes.** Een ontbrekend binary, een down netwerk of een volle schijf levert een duidelijke fout op stderr op en `state:ERROR` in het journal, zonder de module te beschadigen.

## De lock

Slechts één transactie mag de toestand tegelijk aanraken. `flock` is niet betrouwbaar op toybox, dus VDLU serialiseert met een directory-lock: `mkdir "$VDLU_DIR/lock.d"` slaagt voor precies één aanroeper en faalt voor de rest, wat atomair is op elk normaal bestandssysteem. Een verschaalde lock achtergelaten door een dood proces wordt hersteld door de vastgelegde PID te controleren.

De geduldige boot-tijd-retry (gebruikt wanneer het apparaat offline is bij boot) houdt deze lock **niet** vast terwijl die wacht. Het verwerft en geeft vrij tussen pogingen, zodat een handmatige `run` nooit wordt geblokkeerd door een boot die op het netwerk wacht, en het houdt nooit een wakelock. Batterijveilig door ontwerp. Meer daarover in [[Reboot Handling]].

## Handtekeningcontrole: `vdlu-verify`

`vdlu-verify` is de handtekeningcontroleur op het apparaat, bewust slank gehouden:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Exit `0` betekent dat de handtekening van het manifest geldig is tegen de publieke sleutel in de keyring waarvan de id overeenkomt met de `key_id` van het manifest; elke andere code is een afwijzing.

Wat het slank maakt, is dat het **geen `openssl` op het apparaat** gebruikt. Het leest de publieke sleutel uit de keyring als een **rauw bestand van 32 bytes**, canonicaliseert het manifest (de manifesttekst met het `sig`-veld verwijderd), hasht het met toybox `sha256sum`, base64-decodeert de handtekening, en overhandigt de rauwe sleutel, het bericht en de 64-byte-handtekening aan het ingebedde `ed25519-mini`-binary. De controleur weigert ook alles wat misvormd is voordat het ooit verifieert: een ontbrekende of lege `key_id` of `sig`, een `key_id` die padscheiders bevat, een publieke sleutel die niet precies 32 bytes is, of een handtekening die niet precies 64 bytes is.

De canonicalisatie is byte voor byte identiek aan de signer van de producer, en dat is wat een handtekening over tools heen laat verifiëren. De bijbehorende private sleutel raakt nooit een apparaat of CI aan; alleen de rauwe publieke sleutel is ingebed. Het volledige vertrouwensverhaal, de twee profielen en waarom `hardened` door inversie fail-closed is staan in [[Security and Trust Model]].

De engine roept `vdlu-verify` aan tijdens de diff-fase. Onder het `hardened`-profiel breekt een mislukte verificatie de hele update af; onder `trusted` is verificatie best-effort, maar de hash van elke blob wordt nog altijd gecontroleerd, zodat beschadigde inhoud ongeacht het profiel wordt gevangen.

## Toestand op schijf

Alle toestand van de engine leeft in `$VDLU_DIR` (buiten de moduledirectory), zodat de moduleboom zelf alleen ooit afgewerkte bestanden bevat:

| Pad | Rol |
|---|---|
| `config` | key=value-instellingen (source, profile, channel, netwerkbeleid, boot retry) |
| `current.json` | manifest van de actieve versie; dit is de diff-basis. Afwezig betekent nooit bijgewerkt |
| `target.json` | het vastgezette manifest van de lopende transactie. De aanwezigheid ervan markeert een actieve transactie; het wordt `current.json` bij `DONE` |
| `plan.tsv` / `plan.del` | het plan per bestand en de voortgang, en de lijst met te verwijderen paden |
| `journal.json` | voortgang voor de WebUI, bij elke toestandsverandering herschreven |
| `blobs/<sha256>` | cache van geverifieerde, gedecomprimeerde originele inhoud |
| `rollback/<version>/<path>` | back-ups van overschreven bestanden; de laatste drie versies worden bewaard |
| `staged/<path>.vdlu-new` | een bestand van de herstartklasse dat op de boot-swap wacht |
| `lock.d/` | de mkdir-lock |
| `tools/<abi>/curl` | de opgehaalde, geverifieerde statische curl; blijft bestaan over updates heen |
| `cancel` | een annuleringsverzoek |

## Zie ook

- [[Reboot Handling]]: hoe het class-systeem de meeste updates herstartvrij houdt, en hoe een gefaseerde `.so` pre-zygote wordt omgewisseld.
- [[Security and Trust Model]]: de twee profielen, fail-closed-validatie, en de ed25519-keten met rauwe sleutel.
- [[Feed Format]]: het manifest en de inhoudsgeadresseerde blobs die de engine verbruikt.
- [[Architecture]]: hoe de engine, producer en WebUI in elkaar passen.
