# Bidra

Bidrag är välkomna. VDLU är en flashfri, inkrementell självuppdateringsmotor
inbäddad i KernelSU- / APatch- / Magisk-moduler. Denna sida är det praktiska dev-
arbetsflödet; för hur delarna passar ihop, läs [[Architecture]], [[Engine]] och
[[Producer]] först.

## Inget kompileras

VDLU är skript (POSIX sh, lite Python på releasesidan, ren JS för
WebUI), så det finns inget byggsteg. Du verifierar en ändring genom att köra pipelinen
från början till slut och genom att statiskt kontrollera varje del.

## Fogkontraktet först

Gränssnittskontraktet mellan komponenterna (CLI-signaturerna, filnamnen och
JSON-nycklarna som delas av motorn, producenten och WebUI) är **konvergensens
lag**. Behandla det som oföränderligt. Om din ändring vidrör
producent-till-motor-fogen (manifestschema, journalschema, konfigurationsnycklar,
signatur-/kanoniseringsregeln), **anpassa gränssnittskontraktet först**, ändra sedan
koden på båda sidorna så att den matchar. En ändring på en sida av fogen utan
den andra bryter tyst adoptörer. Se [[Producer]] för kanoniserings-
regeln som signeraren och verifieraren måste vara överens om byte-för-byte.

## Testa från början till slut före en PR

Kör producenten och motorn tillsammans på ett slängträd, på samma sätt som en
adoptörs release gör:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Statisk-kontrollera sedan varje komponent:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Och öppna `webui/demo.html` i en webbläsare: den härmar root-hanterar-bryggan
(`ksu.exec`), så att du kan utöva Updates-panelen, förloppstoasten, avbryt
och omstartsbannern utan någon enhet. Se [[WebUI]].

## Husregler

- **POSIX sh på enheten.** Inga bashismer utöver `local`, och inget `jq`. Det måste
  köras på toybox / busybox.
- **Säkerhet är icke förhandlingsbart.** Varje manifestfält är fientlig indata;
  `validate_plan()` förblir fail-closed, och den privata signeringsnyckeln vidrör aldrig
  CI eller en enhet. Lossa inte en kontroll för att få ett test att passera.
- **Rigorositet vid fel.** Håll transaktionen återupptagbar: inget rapporterar "done"
  utan en matchande omhashning, inget skrivs över utan en säkerhetskopia, och
  tillämpningar förblir atomära.
- **Alltid releasekvalitet.** Håll kommentarer korta; inga onödiga kommentarer.
- **En logisk ändring per PR.** Säg vad som ändrades och varför.

## Att rapportera ärenden

Öppna ett ärende som beskriver vad du gjorde, vad du förväntade dig och vad som hände.
För en bugg, inkludera modul-id:t, källprofilen (`hardened` eller `trusted`),
det `update.sh`-kommando du körde, och den relevanta `journal.json` (den registrerar
fasen, tillståndet och felet). För en funktion, säg vilken komponent den vidrör (engine,
producer eller WebUI) så att fogpåverkan är tydlig från början.
