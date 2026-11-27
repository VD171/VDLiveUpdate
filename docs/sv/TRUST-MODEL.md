> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · Svenska · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Säkerhetspolicy och tillitsmodell

VDLiveUpdate (VDLU) tillämpar **flashless root-uppdateringar** på en levande modul: den
skriver till `/data/adb/modules/<mod>` och byter en Zygisk `.so` vid boot. Varje fält i ett
hämtat manifest (`path`, `sha256`, `delete[]`, `mode`, ...) är **fientlig indata** - ett
förgiftat flöde eller en MITM levererar det. Denna sida är tillitsmodellen och policyn för
ansvarsfullt avslöjande. För det fullständiga sömkontraktet se
[`INTERFACES.md`](INTERFACES.md), och engine/producer-interna detaljer i
[`ENGINE.md`](ENGINE.md) och [`PRODUCER.md`](PRODUCER.md), wiki-sidan
**Security-and-Trust-Model** bär samma modell för läsare utanför repot.

## Versioner som stöds

Säkerhetsfixar landar i den senaste `ENGINE_VERSION`, ett signerat manifest deklarerar den
minimala engine det behöver via `engine_min`, och engine på enheten vägrar ett manifest som
ber om mer än den implementerar. Äldre vendorade engine förväntas bli **om-vendorade** för att
plocka upp en fix, inte efterlappade på plats.

| ENGINE_VERSION | status |
|---|---|
| 7 (aktuell) | stöds - aldrig återställa en modul som ligger före flödet (den live-installerade `versionCode` utgör golvet för "from"-versionen), self-heal vid boot av en inaktuell downgrade-plan |
| 6 | ersatt - self-heal vid boot av en inaktuell journal med `target <= 0` (baseline 0 som en borttagen stub lämnade driver inte längre någon UI- eller boot-åtgärd) |
| 5 | ersatt - engine-sidig exkludering av tillitsankaret (`vdlu/`-katalogen ignoreras även om ett flöde bär den), tak på 128 MiB per fil / 2 MiB för manifestet |
| 4 | ersatt - `key_id`-allowlist, avvisning av sökväg med dot-segment/avslutande-snedstreck, storleksgränser, lock vid check-tid |
| <= 3 | stöds inte - om-vendora den aktuella engine |

Varje ändring av engine-verifiering eller apply-logik höjer `ENGINE_VERSION`.

## Rapportera en sårbarhet

Rapportera privat. Öppna **inte** en publik issue, PR eller forumpost för en säkerhetsbugg.
Använd projektkontakterna (se [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-post: **vd.priv8@pm.me**

Inkludera gärna engine-versionen, den `profile` som används, och ett manifest eller flöde som
reproducerar problemet. Fixar levereras som en ny `ENGINE_VERSION` med en `CHANGELOG.md`-post;
samordna tidpunkten för avslöjandet i rapporttråden.

## Tillitsmodell

- **Fristående ed25519-signaturer.** Producern signerar det kanoniska manifestet på PC:n
  (openssl), enheten verifierar med den inbäddade `ed25519-mini` - **ingen openssl på
  enheten**. Det signerade meddelandet är sha256-hexen av manifestet utan dess `sig`-fält
  (nycklar sorterade, kompakt, UTF-8), så signering och verifiering härleder samma byte på två
  körtider utan ett JSON-bibliotek på enheten.
- **Keyring = RAW 32-byte pubnycklar**, endast-flash. Enhetens keyring levererar `<key_id>.pub`
  som den råa 32-byte-nyckeln (aldrig PEM), `vdlu-pack` **exkluderar** keyringen och
  `verify/`-binärerna från flödet, så ett manifest kan aldrig skriva om tillitsankaret på
  enheten över nätet.
- **Engine-sidig exkludering av tillitsankaret (VDLU#2).** Oberoende av producent-sidans
  exkludering ovan **ignorerar** engine på enheten varje `vdlu/`-sökväg (`update.sh`,
  `vdlu-verify`, `verify/*`, `keyring/*`, config) i en hämtad plan - den hämtar, tillämpar
  eller raderar dem aldrig, även om ett flöde bär dem. Ett publicerat flöde levererar hela
  modulträdet, `vdlu/` inkluderat, så engine släpper tyst de sökvägarna i stället för att
  avvisa manifestet: modulen uppdateras ändå, och tillitsankaret ändras bara genom en
  fullständig signerad om-flash. En enda läckt signeringsnyckel kan inte längre byta ut
  verifieraren eller signeringsnyckeln över nätet och bevara root.
- **Module-update-`key_id`-allowlist (fail-closed, före pubnyckelval).** En keyring får legitimt
  bära fler än en nyckel (till exempel en fingerprint-feed-nyckel med lägre tillit vid sidan av
  release-nyckeln). Innan `<key_id>.pub` någonsin väljs avvisar `verify_manifest` varje manifest
  vars `key_id` inte finns i den konfigurerade allowlisten, i **båda** profiles, och speglar den
  upplösta uppsättningen till `vdlu-verify` via `VDLU_KEYID_ALLOW`. Detta stänger en förbigång
  där en läckt nyckel med lägre tillit annars skulle kunna signera en fullständig flashless
  root-uppdatering. Standardsäkert när `key_id` är osatt: en keyring med **en nyckel** nålar
  automatiskt fast den enda nyckeln, en keyring med **flera nycklar** avvisas tills `key_id` är
  fastnålad (kommaseparerade för rotation).
- **Fingerprint-feedens tillitsrot är en separat, fastnålad sökväg** med sin egen nyckel, den är
  aldrig nåbar via module-update-sökvägen ovan.
- **Baseline är en lokal betrodd seed.** `baseline.json` anländer inuti den flashade zippen -
  installationens tillitsgräns - så den är osignerad och nyckellös och går **inte** genom
  `vdlu-verify`, endast ett manifest som **hämtats** från flödet verifieras. Detta håller
  signeringsnyckeln borta från CI.

## Fail-closed-garantier

- **`validate_plan` körs före varje fetch eller apply.** I `do_diff`, fail-closed, avvisar den
  **hela** manifestet om någon `path` är absolut, innehåller ett `..`- eller `.`-segment, slutar
  på `/`, eller håller ett kontrolltecken, om någon `sha256` inte är `^[0-9a-f]{64}$`, eller om
  någon `mode`/`class`/`enc` är ogiltig. Inget fientligt fält når ett shell, och `cmd_check` bär
  ingen `system()`-interpolation.
- **Sökvägsinneslutning.** Varje skrivning och radering begränsas till `MODULE_DIR` via
  `contained()` - apply, delete, och reboot-`stage_file` passerar alla samma vakt. Symlänkar i
  trädet hoppas över av producern (läcker aldrig innehåll utanför det).
- **Två profiles, fail-closed genom inversion.** `trusted` (privat, SSH-scenlagd källa) är den
  **enda** opt-in till best-effort-verify, **varje** annat värde - inklusive ett stavfel, ett
  avslutande mellanslag/CR, eller en annan skiftläge - behandlas som `hardened`, där en giltig
  signatur är **obligatorisk** och ett fel avbryter. Varje blobs `sha256` kontrolleras i båda
  profiles.
- **Signatur + hash före varje verktygs-exec.** Den hämtade statiska `curl` körs som root, så
  `install-tool` verifierar tools-manifestets signatur (ed25519-mini, obligatorisk i **varje**
  profile) och curlens hash **innan** den installeras och körs - sig+hash före exec stänger RCE:n.
- **Återupptagbar, pin-säker transaktion.** Det pågående manifestet nålas fast i `target.json`;
  en krasch, nätverksförlust, eller omstart återupptar från journalen utan att besluta om planen
  på nytt. Downgrade är blockerad (monoton `version`), det signerade `module`-fältet måste vara
  lika med `MODID`, och `delete[]` körs endast vid `finalize_done` (en `PENDING_REBOOT` raderar
  inget). Inget är någonsin "klart" utan en fullständig om-hashning, inget skrivs över utan en
  `rollback/<v>/`-backup först.

## Hardening (försvar på djupet)

- **Storleksgränser.** Manifestet, tools-manifestet, och den curl-lösa `wget`/`head -c`-
  nedladdningsvägen är alla begränsade innan de läses (anti-OOM / anti-flood). En blob
  misslyckas med sin fas efter 3 försök. Taken är **128 MiB per fil** (`MAX_FILE_BYTES`) och
  **2 MiB för manifestet** (`MAX_MANIFEST_BYTES`), upprätthållna i `update.sh` och speglade i
  `vdlu-verify`.
- **Lock vid check-tid.** `check` tar mkdir-locket innan den bygger om sin work-dir, så att en
  samtidig körning inte kan racea den.
- **Staging-inneslutning.** `stage_file` har samma `contained()`-vakt som de levande apply-
  primitiverna, så en scenlagd reboot-hard-sökväg kan inte heller slippa ut ur `MODULE_DIR`.
- **TLS är försvar på djupet, inte tillitsroten.** Den statiska curlen använder mbedTLS med
  Androids tillitslager (`--capath`, `ca_path`-override), integritetsgarantin är ed25519-
  signaturen, certkontrollen är ett andra lager.

## Se även

- [`INTERFACES.md`](INTERFACES.md) - det oföränderliga sömkontraktet (§5 config, §6 signatur, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - den enhetssidiga engine och dess tillståndsmaskin.
- [`PRODUCER.md`](PRODUCER.md) - packing, signering, kanonikalisering, och nyckelrotation.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
