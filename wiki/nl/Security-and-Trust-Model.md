# Security and Trust Model

VDLU werkt een module ter plekke bij, over het netwerk, als root. Dat is veel macht gericht op een bestand dat van een feed komt, dus de hele engine is gebouwd op een enkele aanname:

> **Elk veld in het manifest is vijandige invoer.**

Een feed kan bij de bron worden vergiftigd, of in transit worden verwisseld en verminkt door een MITM. Wanneer dat gebeurt arriveert het manifest nog steeds als een manifest: het draagt bestandspaden, `sha256`-strings, een `delete[]`-lijst, modes, classes en een encoding-vlag. VDLU behandelt geen van die als betrouwbaar. Het valideert het hele plan voordat het één byte downloadt, en het laat nooit een manifestwaarde een shell bereiken.

Deze pagina is het volledige vertrouwensverhaal. Zie [[Feed Format]] voor het manifestschema dat het valideert, en [[Engine]] voor waar deze controles zitten in de DIFF -> FETCH -> APPLY -> COMMIT-transactie.

---

## Het kernidee: fail-closed, voordat er iets gebeurt

`validate_plan()` draait binnen de `check`/diff-fase, **voor** elke fetch en **voor** elke apply. Het loopt door elke entry in de geplande bestandsboom en elke entry in `delete[]`, en als een enkele entry misvormd is, **verwerpt het het hele manifest** en de transactie begint nooit. Er is geen gedeeltelijke acceptatie, geen "sla de slechte over en pas de rest toe". Eén slecht veld vergiftigt de batch, met opzet.

Een manifest wordt alleen geaccepteerd als **al** deze voor **elke** entry gelden:

| Veld | Regel | Waarom |
|---|---|---|
| `path` | niet absoluut, geen `..`-component, geen `.`-component, geen leidende `./`, geen ingebedde `/./`, geen afsluitende slash, geen stuurteken (tab / newline) | een pad moet binnen `MODULE_DIR` blijven; een absoluut of `..`-pad is schrijf-overal |
| `sha256` | komt exact overeen met `^[0-9a-f]{64}$` | een niet-hex sha zou anders in een shellpad worden geinterpoleerd; het is het inhoudsadres, dus het moet een pure hex-digest zijn en niets anders |
| `mode` | alleen octaal (`[0-7]`) | een mode-string wordt een `chmod`-argument |
| `size` | alleen cijfers, en `<=` het plafond van de engine | begrenst de download en de decompressie |
| `class` | exact `live`, `soft` of `reboot` | de class beslist of een bestand live wordt toegepast of wordt gefaseerd voor herstart |
| `enc` | exact `raw` of `gz` | de encoding beslist of de blob wordt gegunzipt |
| `delete[]`-entries | dezelfde padregels als hierboven | een `delete[]`-entry stuurt een verwijdering aan; een ongecontroleerde `..` zou `rm` buiten de boom zijn |

Omdat dit eerst draait, kan een vergiftigd manifest nooit buiten de module schrijven, nooit buiten de module verwijderen, en nooit een niet-hex-token in een commandoregel injecteren.

### Manifestwaarden raken nooit een shell

De tweede helft van de regel: zelfs nadat een waarde de validatie passeert, wordt die nooit in `sh` geinterpoleerd, en nooit aan `awk system()` gevoed. Het check-commando werd bewust herschreven om geen enkele `system()`-aanroep te bevatten. Inhoudsadressering doet de rest van het werk: een blob wordt opgehaald aan de hand van zijn `sha256`, geschreven naar een cachepad genoemd naar diezelfde `sha256`, en de gedownloade bytes worden herhasht en vergeleken voordat er iets wordt toegepast. Een waarde die geen schone 64-hex-digest is komt nooit zo ver, omdat `validate_plan()` die al heeft verworpen.

### Een tweede verdedigingslinie op apply-tijd

`validate_plan()` blokkeert `..` **lexicaal**, maar een reeds bestaande symlink binnen de boom zou een schrijfbewerking alsnog kunnen omleiden. Dus op apply-tijd resolvet `contained()` het echte doelpad en bevestigt dat het onder de modulebasis zit, fail-closed wanneer het niet kan resolven. Schrijfbewerkingen zijn atomair (schrijf naar een temp-naam, dan `rename` over het doel) en elk overschrijven wordt eerst geback-upt naar `rollback/`; een mislukte back-up breekt het apply af in plaats van te overschrijven zonder vangnet.

---

## De twee profielen

VDLU draait in een van twee vertrouwensprofielen, ingesteld door `profile=` in de config.

### `hardened` (de publieke standaard)

- **Handtekening is verplicht.** Het manifest moet een geldige ed25519-handtekening dragen van een sleutel in de keyring op het apparaat, of de transactie breekt af.
- **Downgrade is geblokkeerd.** Een manifest waarvan de `version` lager is dan de geinstalleerde versie wordt geweigerd. Een aanvaller kan je niet terugrollen naar een bekend-kwetsbare build.
- Dit is het profiel voor elke module die aan het publiek wordt gedistribueerd over `https://`.

### `trusted` (private, via SSH gefaseerde bron)

- Handtekeningverificatie is **best-effort**: de bron is een private `file://`- of via SSH gefaseerde feed die jij beheert, zodat een ontbrekende of niet-verifieerbare handtekening niet hard afbreekt.
- **Maar de `sha256` van elke blob wordt nog altijd gecontroleerd.** `trusted` versoepelt *wie het manifest signeerde*, nooit *of de bytes met het plan overeenkomen*. Inhoudsintegriteit is in beide profielen niet onderhandelbaar.

---

## Fail-closed door inversie

Dit is het subtiele deel, en het is het deel dat de meeste systemen fout doen.

`trusted` is de **enige** string die kiest voor versoepelde verificatie. De engine test niet "is dit `hardened`?" Het test "is dit **niet** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Dus **alles** anders dan het letterlijke `trusted` resolvet naar hardened-gedrag:

- de regel ontbreekt volledig -> hardened
- een typefout zoals `hardend` -> hardened
- `trusted ` met een afsluitende spatie, of een `\r` van CRLF -> hardened
- `Trusted` met verkeerde hoofdletters -> hardened
- een door MITM verminkte waarde -> hardened

Een eerdere versie liet een *ontbrekende* regel standaard op hardened staan, wat nog steeds een beschadigde *waarde* door het open pad liet vallen. Dat was een fail-open: een verminkte profielstring kon stilletjes een ongesigneerd manifest accepteren, en een ongesigneerd manifest betekent een door een aanvaller geleverde `.so` die onder MITM wordt ingewisseld, en dat is remote code execution op root-niveau. De inversie sluit het. De enige manier om versoepelde verificatie te krijgen is `trusted` exact te spellen, en zelfs dan worden de blob-hashes gecontroleerd. De engine is nooit één typefout verwijderd van het accepteren van ongesigneerde code. (De `tr -d` strijkt verdwaalde witruimte weg zodat een legitieme `trusted` met slordige spatiëring niet onterecht wordt geweigerd, zonder het gat te heropenen.)

**Deze test is dragend. Die moet `!= trusted` blijven en nooit `== hardened` worden.**

---

## Het manifest is gebonden aan de module

Een enkele release-sleutel signeert vele modules. Dus een manifest dat geldig is gesigneerd, voor een *andere* module, zou in principe aan deze kunnen worden geserveerd (een feed-misconfiguratie, een bronverwisseling, of een MITM-omleiding) en zijn handtekening zou kloppen.

VDLU sluit dit met een binding: het gesigneerde `module`-veld binnen het manifest moet gelijk zijn aan de `MODID` van deze installatie, of het manifest wordt afgewezen als een cross-module-feed. Omdat `module` binnen de gesigneerde canonieke vorm zit, kan een aanvaller het niet wijzigen zonder de handtekening te breken. Een geldig gesigneerde feed voor module B kan simpelweg niet op module A worden toegepast.

---

## De slanke verifier op het apparaat

Verificatie op het apparaat gebruikt **ed25519-mini**, een piepkleine verify-only-controleur gebouwd op TweetNaCl (publiek domein). Er is **geen `openssl` op het apparaat**.

- De keyring-entry is de **rauwe publieke sleutel van 32 bytes**, opgeslagen als `keyring/<key_id>.pub`. (De PEM publieke sleutel is alleen een pc-zijdig artefact; een PEM in de keyring van het apparaat kopiëren breekt de verificatie, aangezien de verifier precies 32 rauwe bytes verwacht.)
- `vdlu-verify <manifest.json> <keyring_dir>` reconstrueert de canonieke vorm (de manifesttekst met het `sig`-veld verwijderd, compact, gesorteerde sleutels), hasht die tot het 64-tekens-hex-bericht dat de handtekening dekt, decodeert de base64-handtekening, controleert dat die 64 bytes is, en vraagt `ed25519-mini <pub32> <msg> <sig64>` om een oordeel. rc 0 = geldig, alles anders = afwijzen.
- Het binary is statisch per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), met een `PROVENANCE.json` die de exacte TweetNaCl-bronnen, wrapper-hash en build-vlaggen vastpint, zodat het ding dat als root draait auditeerbaar is.
- De `key_id` uit het manifest wordt zelf gesaneerd (geen `/`, geen `..`, geen quote) voordat die wordt gebruikt om een keyring-bestand te kiezen, zodat die niet uit de keyring-directory kan ontsnappen.

### De keyring is flash-only, verify-not-copy, stabiel

De keyring levert mee in de module op flash-tijd en wordt niet herschreven door de update-engine. Bij opnieuw vendoren is de regel **verifiëren, niet kopiëren**: de keyring verandert alleen bij een bewuste sleutelrotatie, nooit als neveneffect van een update.

### Sleutelrotatie brickt oudere installaties niet

Wanneer een signeringssleutel wordt geroteerd, levert de keyring **zowel de huidige als de vorige rauwe publieke sleutels** mee. De verifier selecteert het sleutelbestand aan de hand van de `key_id` van het manifest, zodat een feed die nog met de oude sleutel is gesigneerd verifieert tegen de oude pubkey, en een feed gesigneerd met de nieuwe sleutel verifieert tegen de nieuwe. Een apparaat dat niet voorbij de rotatie is bijgewerkt blijft werken; niets raakt gestrand.

---

## De key_id-allowlist voor module-updates

Sleutelrotatie betekent al dat de keyring legitiem meer dan één sleutel kan bevatten, en een module kan er om een tweede reden meer dan één bevatten: hij kan een sleutel met lager vertrouwen meeleveren die een *andere* feed signeert. De fingerprint-feed is precies dat geval. Een module kan een smalle sleutel dragen wiens enige taak is een fingerprint-feed te signeren, pal naast de release-sleutel die de module zelf signeert in dezelfde keyring.

Dat roept een vraag op die het rotatieverhaal alleen niet beantwoordt: zodra twee sleutels in de keyring leven, *welke* van hen mag een **module-update** signeren? Een module-update is het krachtigste dat een manifest kan vragen, want het herschrijft bestanden die het apparaat als root draait. De verifier koos vroeger de pubkey die door de `key_id` van het manifest werd genoemd en accepteerde elke sleutel die toevallig in de keyring aanwezig was. Dus de fingerprint-feed-sleutel met lager vertrouwen kon, als die lekte, een module-update-manifest signeren en het apparaat zou het honoreren. Dat is een omzeiling van de vertrouwenswortel: een sleutel bedoeld voor één smalle taak kon een volledige flashless root-update aandrijven.

De fix pint de geaccepteerde module-update-`key_id` vast op een fail-closed **allowlist**, gecontroleerd **voordat** de pubkey ooit wordt geselecteerd. De config-sleutel is `key_id`, en de engine lost die zo op:

- **Een keyring met één sleutel pint die ene sleutel automatisch vast.** Het gangbare geval heeft helemaal geen config nodig: als de keyring precies één sleutel bevat, *is* die sleutel de allowlist, en niets anders kan een module-update signeren.
- **Een keyring met meerdere sleutels moet `key_id` instellen.** Op het moment dat een tweede sleutel verschijnt, weigert de engine te gokken. Hij faalt gesloten met "multiple keys in keyring; config must pin key_id" totdat de config de sleutel noemt (of sleutels, kommagescheiden tijdens een rotatievenster) die module-updates mag signeren.

Omdat de controle vóór de pubkey-selectie loopt, wordt een manifest dat een sleutel noemt die aanwezig maar niet op de allowlist staat, afgewezen zonder dat de verifier die sleutel ooit laadt. De opgeloste set wordt via `VDLU_KEYID_ALLOW` naar `vdlu-verify` gespiegeld, zodat de slanke controleur op het apparaat dezelfde pin afdwingt en de twee niet kunnen verschillen. Dit geldt in **beide** profielen: zowel `hardened` als `trusted` raadplegen de allowlist, want de allowlist beslist *welke sleutel* een geldige module-update-wortel is, niet *of* een handtekening vereist is.

De fingerprint-feed houdt zijn eigen aparte vastgepinde vertrouwenswortel, `FEED_KEY_ID`. Het is een aparte wortel met een aparte taak, nooit bereikbaar via het module-update-pad hierboven, dus het vastpinnen van de module-update-allowlist raakt die niet en een gelekte feed-sleutel kan nog steeds geen module-update signeren. Deze wijziging bracht `ENGINE_VERSION` naar 4.

---

## Wat het tools-manifest afsluit

De slanke fetch-bootstrap downloadt bij eerste gebruik een statische `curl` voor modules die niet hun eigen meeleveren. Omdat dat binary als root draait, zijn zijn eigen manifest-handtekening (ed25519-mini) en zijn hash **verplicht in elk profiel**, inclusief `trusted`, voordat het ooit wordt geinstalleerd of uitgevoerd. De webview is slechts transport; vertrouwen komt uit de handtekening- en hashcontrole op het apparaat, nooit uit het feit dat een download slaagde.

---

## Wat een aanvaller NIET kan

Zelfs met bezit van de feed, of zittend op de draad als een volledige MITM, kan een aanvaller niet:

- **Buiten de module schrijven.** Absolute paden, `..`, `.`, stuurtekens en afsluitende slashes worden allemaal afgewezen voor elke apply, en symlink-omleiding wordt opnieuw gevangen op apply-tijd.
- **Buiten de module verwijderen.** `delete[]`-entries passeren dezelfde padvalidatie.
- **Een commando injecteren.** Geen manifestwaarde wordt in een shell of `awk system()` geinterpoleerd; `sha256` moet pure 64-hex zijn of het hele manifest wordt afgewezen.
- **Ongesigneerde code naar een publieke installatie leveren.** `hardened` maakt de handtekening verplicht, en het profiel is fail-closed door inversie, zodat geen typefout of verminkte waarde dat downgradet.
- **Een module-update signeren met een sleutel met lager vertrouwen.** De module-update-`key_id` is vastgepind op een fail-closed allowlist, gecontroleerd voordat de pubkey wordt geselecteerd, zodat een gelekte fingerprint-feed-sleutel die de keyring deelt geen volledige root-update kan signeren.
- **De gesigneerde feed van een andere module hier serveren.** Het gesigneerde `module`-veld moet gelijk zijn aan deze `MODID`.
- **Je terugrollen.** Downgrade is geblokkeerd in `hardened`.
- **Een blob onopgemerkt corrumperen.** Elke gedownloade blob wordt in beide profielen herhasht tegen de manifest-`sha256`; een mismatch breekt na drie pogingen de fase af met niets toegepast.
- **Een valse root-fetcher inwisselen.** De gebootstrapte `curl` wordt handtekening- en hash-gecontroleerd voordat die wordt geinstalleerd of gedraaid, in elk profiel.
- **Een corrupte update half toepassen.** De transactie bereikt `DONE` pas wanneer een herhash van alles overeenkomt; een mislukt apply rolt terug in plaats van te overschrijven zonder back-up.

---

Zie ook: [[Feed Format]] voor het manifestschema, [[Engine]] voor de transactie waarin deze controles leven, en [[Architecture]] voor het grote plaatje.
