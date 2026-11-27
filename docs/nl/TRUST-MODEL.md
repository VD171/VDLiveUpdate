> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · Nederlands · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Beveiligingsbeleid en vertrouwensmodel

VDLiveUpdate (VDLU) past **flashless root-updates** toe op een live module: het schrijft
naar `/data/adb/modules/<mod>` en swapt een Zygisk `.so` bij boot. Elk veld van een
opgehaald manifest (`path`, `sha256`, `delete[]`, `mode`, ...) is **vijandige invoer** - een
vergiftigde feed of een MITM levert het aan. Deze pagina is het vertrouwensmodel en het
beleid voor verantwoorde openbaarmaking. Voor het volledige naadcontract zie
[`INTERFACES.md`](INTERFACES.md), en de engine/producer-interne werking in
[`ENGINE.md`](ENGINE.md) en [`PRODUCER.md`](PRODUCER.md), de wikipagina
**Security-and-Trust-Model** draagt hetzelfde model voor lezers buiten de repo.

## Ondersteunde versies

Beveiligingsfixes landen in de nieuwste `ENGINE_VERSION`, een getekend manifest declareert
de minimale engine die het nodig heeft via `engine_min`, en de engine op het toestel weigert
een manifest dat meer vraagt dan het implementeert. Van oudere gevendorde engines wordt
verwacht dat ze **opnieuw gevendord** worden om een fix op te pikken, niet dat ze ter plekke
worden teruggepatcht.

| ENGINE_VERSION | status |
|---|---|
| 7 (huidig) | ondersteund - een module die voorloopt op de feed nooit terugdraaien (de live geïnstalleerde `versionCode` vormt de ondergrens van de "from"-versie), boot-self-heal van een verouderd downgrade-plan |
| 6 | vervangen - boot-self-heal van een verouderd journal met `target <= 0` (de baseline 0 van een verwijderde stub stuurt geen UI- of boot-actie meer aan) |
| 5 | vervangen - engine-zijdige uitsluiting van het vertrouwensanker (de `vdlu/`-dir wordt genegeerd zelfs als een feed hem meedraagt), plafonds van 128 MiB per bestand / 2 MiB manifest |
| 4 | vervangen - `key_id`-allowlist, afwijzing van pad met dot-segment/afsluitende-slash, groottelimieten, lock bij check-tijd |
| <= 3 | niet ondersteund - vendor de huidige engine opnieuw |

Elke wijziging aan de engine-verificatie of apply-logica verhoogt de `ENGINE_VERSION`.

## Een kwetsbaarheid melden

Meld privé. Open **geen** publieke issue, PR of forumpost voor een beveiligingsbug. Gebruik
de projectcontacten (zie [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanaal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Vermeld alsjeblieft de engine-versie, de `profile` die in gebruik is, en een manifest of feed
die het probleem reproduceert. Fixes worden geleverd als een nieuwe `ENGINE_VERSION` met een
`CHANGELOG.md`-vermelding, coördineer de timing van de openbaarmaking in de meldingsthread.

## Vertrouwensmodel

- **Losgekoppelde ed25519-handtekeningen.** De producer tekent het canonieke manifest op de
  PC (openssl), het toestel verifieert met de ingebedde `ed25519-mini` - **geen openssl op
  het toestel**. Het getekende bericht is de sha256-hex van het manifest zonder zijn `sig`-
  veld (sleutels gesorteerd, compact, UTF-8), zodat signeren en verifiëren dezelfde bytes
  afleiden op twee runtimes zonder een JSON-bibliotheek op het toestel.
- **Keyring = RAW 32-byte pubkeys**, alleen-flash. De keyring van het toestel levert
  `<key_id>.pub` als de raw 32-byte sleutel (nooit de PEM), `vdlu-pack` **sluit** de keyring
  en de `verify/`-binaries **uit** van de feed, zodat een manifest het vertrouwensanker op het
  toestel nooit over de draad kan herschrijven.
- **Engine-zijdige uitsluiting van het vertrouwensanker (VDLU#2).** Onafhankelijk van de producer-zijdige
  uitsluiting hierboven **negeert** de engine op het toestel elk `vdlu/`-pad (`update.sh`, `vdlu-verify`,
  `verify/*`, `keyring/*`, config) in een opgehaald plan - het haalt ze nooit op, past ze nooit toe en
  verwijdert ze nooit, zelfs als een feed ze meedraagt. Een gepubliceerde feed levert de hele moduleboom mee,
  `vdlu/` inbegrepen, dus de engine laat die paden stil vallen in plaats van het manifest te weigeren: de module
  wordt nog steeds geüpdatet, en het vertrouwensanker verandert alleen door een volledige getekende re-flash. Een
  enkele gelekte signeersleutel kan de verifier of de signeersleutel niet langer over de draad omwisselen en root
  laten voortbestaan.
- **Module-update-`key_id`-allowlist (fail-closed, vóór pubkey-selectie).** Een keyring mag
  legitiem meer dan één sleutel dragen (bijvoorbeeld een fingerprint-feed-sleutel van lager
  vertrouwen naast de release-sleutel). Voordat `<key_id>.pub` ooit wordt geselecteerd, weigert
  `verify_manifest` elk manifest waarvan de `key_id` niet in de geconfigureerde allowlist staat,
  in **beide** profiles, en spiegelt het de opgeloste set naar `vdlu-verify` via
  `VDLU_KEYID_ALLOW`. Dit sluit een bypass waar een gelekte sleutel van lager vertrouwen anders
  een volledige flashless root-update zou kunnen tekenen. Standaardveilig wanneer `key_id` niet
  is ingesteld: een keyring met **één sleutel** pint zich automatisch vast op die ene sleutel;
  een keyring met **meerdere sleutels** wordt geweigerd tot `key_id` is vastgepind
  (kommagescheiden voor rotatie).
- **De vertrouwenswortel van de fingerprint-feed is een afzonderlijk, vastgepind pad** met zijn
  eigen sleutel, het is nooit bereikbaar via het module-update-pad hierboven.
- **De baseline is een lokale vertrouwde seed.** `baseline.json` arriveert binnen de geflashte
  zip - de installatie-vertrouwensgrens - dus het is ongetekend en sleutelloos en gaat **niet**
  door `vdlu-verify`, alleen een manifest dat van de feed is **opgehaald** wordt geverifieerd.
  Dit houdt de signeersleutel buiten CI.

## Fail-closed-garanties

- **`validate_plan` draait vóór elke fetch of apply.** In `do_diff`, fail-closed, weigert het
  het **hele** manifest als enig `path` absoluut is, een `..`- of `.`-segment bevat, op `/`
  eindigt, of een controleteken bevat, als enig `sha256` niet `^[0-9a-f]{64}$` is, of als enig
  `mode`/`class`/`enc` ongeldig is. Geen vijandig veld bereikt een shell, en `cmd_check` draagt
  geen `system()`-interpolatie.
- **Padinperking.** Elke schrijf- en verwijderactie is tot `MODULE_DIR` beperkt via
  `contained()` - apply, delete, en de reboot-`stage_file` passeren allemaal dezelfde bewaking.
  Symlinks in de boom worden door de producer overgeslagen (lekken nooit inhoud van erbuiten).
- **Twee profiles, fail-closed door inversie.** `trusted` (privé, SSH-gestagede bron) is de
  **enige** opt-in naar best-effort-verify, **elke** andere waarde - inclusief een typefout, een
  afsluitende spatie/CR, of een ander lettergeval - wordt behandeld als `hardened`, waar een
  geldige handtekening **verplicht** is en een mislukking afbreekt. De `sha256` van elke blob
  wordt in beide profiles gecontroleerd.
- **Handtekening + hash vóór elke tool-exec.** De opgehaalde statische `curl` draait als root,
  dus `install-tool` verifieert de handtekening van het tools-manifest (ed25519-mini, verplicht
  in **elk** profile) en de hash van de curl **voordat** het wordt geïnstalleerd en uitgevoerd -
  sig+hash vóór exec sluit de RCE.
- **Hervatbare, pin-veilige transactie.** Het lopende manifest wordt vastgepind in
  `target.json`, een crash, netwerkverlies, of reboot hervat vanuit het journal zonder het plan
  opnieuw te beslissen. Downgrade is geblokkeerd (monotone `version`), het getekende `module`-
  veld moet gelijk zijn aan `MODID`, en `delete[]` draait alleen bij `finalize_done` (een
  `PENDING_REBOOT` verwijdert niets). Niets is ooit "klaar" zonder een volledige her-hash, niets
  wordt overschreven zonder eerst een `rollback/<v>/`-backup.

## Hardening (verdediging in de diepte)

- **Groottelimieten.** Het manifest, het tools-manifest, en het curl-loze `wget`/`head -c`-
  downloadpad zijn allemaal begrensd voordat ze worden gelezen (anti-OOM / anti-flood). Een blob
  faalt zijn fase na 3 pogingen. De plafonds zijn **128 MiB per bestand** (`MAX_FILE_BYTES`) en **2 MiB voor
  het manifest** (`MAX_MANIFEST_BYTES`), afgedwongen in `update.sh` en gespiegeld in `vdlu-verify`.
- **Lock bij check-tijd.** `check` neemt de mkdir-lock voordat het zijn work-dir herbouwt, zodat
  een gelijktijdige run er niet tegen kan racen.
- **Staging-inperking.** `stage_file` heeft dezelfde `contained()`-bewaking als de live apply-
  primitieven, zodat een gestaged reboot-hard-pad evenmin aan `MODULE_DIR` kan ontsnappen.
- **TLS is verdediging in de diepte, niet de vertrouwenswortel.** De statische curl gebruikt
  mbedTLS met de Android-trust-store (`--capath`, `ca_path`-override), de integriteitsgarantie
  is de ed25519-handtekening, de certcontrole is een tweede laag.

## Zie ook

- [`INTERFACES.md`](INTERFACES.md) - het onveranderlijke naadcontract (§5 config, §6 handtekening, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - de toestelzijdige engine en zijn toestandsmachine.
- [`PRODUCER.md`](PRODUCER.md) - packing, signeren, canonicalisatie, en sleutelrotatie.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom, zie [CONTRIBUTING.md](CONTRIBUTING.md)._
