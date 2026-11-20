# VDLiveUpdate (VDLU)

**VDLU är en flashfri, inkrementell självuppdateringsmotor för KernelSU- / APatch- / Magisk-moduler: en installerad modul uppdaterar sina egna filer via ett signerat flöde, hämtar bara det som ändrats och tillämpar det mesta av det utan omstart.**

En vanlig moduluppdatering skickar hela `.zip`-filen igen, så några få ändrade rader kostar en fullständig omnedladdning, och ett statiskt uppdateringsmanifest kan bara peka på en enda `zipUrl` (en variant för varje enhet). VDLU väljer en annan väg: den jämför trädet som faktiskt är installerat mot ett signerat, innehållsadresserat flöde, laddar bara ner skillnaderna och skriver dem på plats. En arm64-fullinstallation förblir arm64-full, en lite-installation förblir lite, och modulen flashas aldrig om.

VDLU är tänkt att **bäddas in** (vendoras) i en modul, placerad i `<module>/vdlu/`. Den är inte en egen modul.

## Mål

- **Flashfri självuppdatering.** Uppdatera en installerad modul på plats, trådlöst, utan root-hanterare, utan omflashning av `.zip`-filen och utan att förlora den installerade varianten.
- **Inkrementell efter innehåll.** Överför bara de blobbar vars innehåll har ändrats. Ett innehållsadresserat flöde (`manifest.json` + `blobs/<sha256>`) innebär att oförändrade eller återställda filer aldrig hämtas igen.
- **Omstartsfri där det är säkert.** Tillämpa vanliga filer direkt, i realtid. Reservera en förberedd omstart bara för de få filer som verkligen behöver det (en `.so`, ett `/system`-överlägg, en `sepolicy.rule`).
- **Slimmad på enheten.** Ren POSIX `sh`, inget `jq`, inget `bash`, inget `openssl` på enheten. Verifieringen vilar på en inbäddad `ed25519-mini`; den enda hämtade binären är en statisk `curl`, som bara används för `https`-flöden.
- **Fail-closed och ärlig.** Varje manifestfält behandlas som fientlig indata och valideras innan något laddas ner. Inget rapporteras någonsin som "klart" om inte en omhashning bevisar det, och inget skrivs över utan en säkerhetskopia först.

## Särdrag

Det som skiljer VDLU från en typisk OTA-klient:

- **Flashfri och inkrementell.** Innehållsadresserad diff / fetch / apply med deduplicering: enheten beräknar skillnaden mot det signerade flödet och hämtar bara saknade blobbar.
- **Omstartsfri där det går.** Vanliga filer tillämpas i realtid; bara `.so`, `/system`-överlägg och `sepolicy.rule`-filer förbereds och byts ut vid en enda omstart. Se [[Reboot Handling]].
- **POSIX `sh` på enheten.** Körs under toybox / busybox / mksh. Inget `jq` (en `gron`-liknande `awk`-utplattare tolkar JSON), inga `bash`-specifika konstruktioner, ingen tung körmiljö.
- **Slimmad verifiering.** En inbäddad `ed25519-mini` verifierar signaturer. Det finns **inget `openssl` på enheten**; den privata nyckeln vidrör aldrig en enhet eller CI.
- **Fail-closed-säkerhet.** `validate_plan()` förkastar **hela** manifestet vid vilket felaktigt fält som helst (en absolut sökväg eller en med `..`, en `sha256` som inte är 64 hex-tecken, ett ogiltigt läge / klass / kodning). Två profiler, `trusted` och `hardened`, där `hardened` är fail-closed genom inversion. Se [[Security and Trust Model]].
- **Återupptagbar och atomär.** En journal gör varje transaktion kraschsäker; skrivningar använder `rename` / `mv`; en säkerhetskopia tas innan någon överskrivning så att en misslyckad tillämpning rullas tillbaka i stället för att korrumpera modulen.

## Börja här

| Om du vill... | Gå till |
|---|---|
| Införa VDLU i din modul, steg för steg | [[Quick Start]] |
| Förstå hela systemet på ett ögonkast | [[Architecture]] |
| Lära dig enhetssidans motor (`update.sh`) | [[Engine]] |
| Bygga och signera ett flöde på din PC | [[Producer]] |
| Lägga in Updates-panelen | [[WebUI]] |
| Läsa förtroendemodellen och hotbilden | [[Security and Trust Model]] |
| Se manifest- och bloblayouten | [[Feed Format]] |
| Veta vad som orsakar omstart och varför | [[Reboot Handling]] |
| Ställa en vanlig fråga | [[FAQ]] |
| Bidra | [[Contributing]] |

## Projektlänkar

- **Källkod:** https://github.com/VD171/VDLiveUpdate
- **Kanal (uppdateringar):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate är ett oberoende, inofficiellt projekt. "Android" är ett varumärke som tillhör Google LLC; "KernelSU", "Magisk" och "APatch" är sina respektive upphovsmäns varumärken. VDLU körs helt och hållet på din egen enhet och din egen releasevärd.
