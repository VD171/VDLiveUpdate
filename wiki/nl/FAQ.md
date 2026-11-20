# FAQ

Korte antwoorden op de vragen die het vaakst voorkomen. Elk linkt naar de pagina met
het volledige verhaal.

## Wat betekent "flashloos"? Moet ik de eerste keer nog steeds flashen?

Ja, je flasht eenmaal. De module wordt op de normale manier geinstalleerd (flash de zip in
je root-manager). "Flashloos" beschrijft elke update daarna: VDLU haalt
alleen de bestanden op die zijn veranderd en past ze ter plekke toe, zodat je nooit een
volledige zip herflasht alleen om een paar gewijzigde regels te leveren. Zie [[Architecture]].

## Heeft een update een herstart nodig?

Meestal niet. De meeste bestanden (je WebUI, binaries, libraries, configs, `module.prop`)
zijn **live**-class en worden atomair toegepast zonder herstart. Alleen bestanden van de herstartklasse
(een `.so` onder `zygisk/`, een `/system/**`-overlay, een `*.rule` sepolicy-bestand) worden
**gefaseerd** en bij de volgende boot ingewisseld, omdat een draaiend proces de live inode al heeft
gemapt. Wanneer dat gebeurt toont de WebUI een aanhoudende "reboot to
activate"-banner. Zie [[Reboot Handling]].

## Is het veilig als de feed ge-MITM'd of vergiftigd is?

Ja, op een `hardened`-feed. Elk manifestveld wordt als vijandige invoer behandeld.
Het manifest moet een geldige ed25519-handtekening over zijn canonieke vorm dragen, en
`validate_plan()` draait fail-closed **voor elke download**: het verwerpt het hele
manifest bij een absoluut of `..`-pad, een `sha256` die geen 64 hex-tekens is,
of een ongeldige mode, class of encoding. Het manifest is ook gebonden aan je module-
id, zodat een geldig gesigneerde feed voor een andere module niet in plaats daarvan kan worden geserveerd.
De sha256 van elke blob wordt na download geverifieerd ongeacht het profiel. Zie
[[Security and Trust Model]].

## Wat heeft het op het apparaat nodig (afhankelijkheden)?

Heel weinig. Puur POSIX sh (mksh / busybox / toybox) plus toybox' `sha256sum`,
`gzip`, `base64` en `date`; de ingebedde `ed25519-mini`-verifier; en, alleen voor
een `https`-bron, een statische `curl` die eenmaal wordt opgehaald en gecachet in Tier-2.
Een `file://`-bron heeft helemaal geen curl nodig. Er is **geen afhankelijkheid van `jq`**: de
engine parst JSON met een gron-achtige flattener geschreven in `awk`. Zie [[Engine]].

## Is openssl vereist op het apparaat?

Nee. `openssl` wordt alleen gebruikt op de pc-/release-zijde (`vdlu-keygen`, `vdlu-sign`).
Op het apparaat gebruikt handtekeningverificatie het slanke ingebedde `ed25519-mini`-
binary, dat een RAUWE publieke sleutel van 32 bytes leest. Zie [[Producer]] en
[[Security and Trust Model]].

## Hoe roteer ik de signeringssleutel?

Genereer een nieuw sleutelpaar met `vdlu-keygen`, voeg de nieuwe RAUWE publieke sleutel van 32 bytes toe aan
de keyring van het apparaat naast de vorige, en begin met signeren met de nieuwe
`key_id`. Het apparaat kiest `<keyring>/<key_id>.pub` aan de hand van de `key_id` van het manifest,
zodat geen engine-wijziging nodig is. Zowel de huidige als de vorige publieke sleutel meeleveren
betekent dat een geroteerde sleutel oudere installaties nooit brickt. Zie [[Security and Trust Model]].

## hardened vs trusted - welke gebruik ik?

Gebruik `hardened` voor elke publieke feed (geserveerd over `https`, bv. GitHub Pages).
Het maakt de handtekening verplicht en blokkeert downgrades. Gebruik `trusted` alleen voor een
private `file://`- of via SSH gefaseerde bron die je al beheert, waar de handtekening
best-effort is (elke blob-hash wordt nog steeds gecontroleerd). Bij twijfel, gebruik `hardened`:
het is de fail-closed-standaard, en elke niet-`trusted`-waarde wordt als
`hardened` behandeld. Zie [[Security and Trust Model]].

## Wat als een blob is geknoeid of het manifest misvormd is?

De update breekt af en niets wordt toegepast. Een misvormd manifest wordt in zijn geheel
afgewezen door `validate_plan()` voor elke fetch. Een blob waarvan de sha256 niet overeenkomt met het
manifest wordt afgewezen; drie fouten op dezelfde blob breken de fetch-fase af met
niets toegepast. Bij elke harde fout legt het journal `ERROR` vast en blijft de module
intact. Zie [[Engine]].

## Kan een update mijn bestanden verwijderen of het apparaat bricken?

Het risico is door ontwerp ingeperkt. Overschreven en verwijderde bestanden worden eerst geback-upt
naar `rollback/<version>/`, en `apply` breekt af in plaats van te overschrijven zonder een
succesvolle back-up. Verwijderingen draaien alleen wanneer een transactie `DONE` bereikt, nooit
terwijl een herstart nog in afwachting is. Een mislukt apply zet de live bestanden terug die het al
schreef. Paden worden gevalideerd op containment binnen de moduledirectory voor gebruik,
zodat een manifest niet buiten de boom kan schrijven of verwijderen. Zie [[Engine]] en
[[Security and Trust Model]].

## Werkt het op KernelSU EN Magisk EN APatch?

Ja. VDLU is gewoon POSIX sh plus een WebUI, gevendord in de module, zodat het draait op
KernelSU, APatch en Magisk gelijk. Het gebruikt de WebUI-brug van de root-manager
(`ksu.exec`) om de engine aan te sturen en voortgang te pollen. Zie [[Architecture]] en
[[WebUI]].

## Hoe groot is de footprint op het apparaat?

Klein. De engine is scripts; de enige binaries zijn de per-ABI `ed25519-mini`-
verifier (piepklein) en, voor een `https`-bron, een statische `curl` (~1MB) die eenmaal wordt
opgehaald en gecachet. Een module die al zijn eigen `curl` bundelt hergebruikt die en voegt helemaal
geen download toe. De Tier-2-blob-cache houdt geverifieerde inhoud plus
de laatste 3 rollback-versies. Zie [[Engine]] en [[Architecture]].
