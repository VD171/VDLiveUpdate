# VDLiveUpdate (VDLU)

**VDLU is een flashloze, incrementele zelf-update-engine voor KernelSU- / APatch- / Magisk-modules: een geinstalleerde module werkt zijn eigen bestanden bij via een gesigneerde feed, haalt alleen op wat is veranderd en past het grootste deel ervan toe zonder herstart.**

Een gewone module-update levert de hele `.zip` opnieuw uit, zodat een paar gewijzigde regels een volledige herdownload kosten, en een statisch update-manifest kan maar naar een enkele `zipUrl` wijzen (een variant voor elk apparaat). VDLU slaat een andere weg in: het vergelijkt de daadwerkelijk geinstalleerde boom met een gesigneerde, inhoudsgeadresseerde feed, downloadt alleen de delta's en schrijft ze ter plekke weg. Een arm64-volledige installatie blijft arm64-volledig, een lite-installatie blijft lite, en de module wordt nooit opnieuw geflasht.

VDLU is bedoeld om in een module **vendored** (ingebed) te worden, geplaatst onder `<module>/vdlu/`. Het is geen module op zichzelf.

## Doelstellingen

- **Flashloze zelf-update.** Werk een geinstalleerde module ter plekke bij, over the air, zonder root-manager, zonder het `.zip` opnieuw te flashen en zonder verlies van de geinstalleerde variant.
- **Incrementeel naar inhoud.** Draag alleen de blobs over waarvan de inhoud is veranderd. Een inhoudsgeadresseerde feed (`manifest.json` + `blobs/<sha256>`) betekent dat ongewijzigde of teruggedraaide bestanden nooit opnieuw worden opgehaald.
- **Herstartvrij waar het veilig is.** Pas gewone bestanden direct live toe. Houd een gefaseerde herstart alleen achter de hand voor de enkele bestanden die er echt een nodig hebben (een `.so`, een `/system`-overlay, een `sepolicy.rule`).
- **Slank op het apparaat.** Puur POSIX `sh`, geen `jq`, geen `bash`, geen `openssl` op het apparaat. De verificatie draait op een ingebedde `ed25519-mini`; het enige opgehaalde binary is een statische `curl`, alleen gebruikt voor `https`-feeds.
- **Fail-closed en eerlijk.** Elk manifestveld wordt als vijandige invoer behandeld en gevalideerd voordat er iets wordt gedownload. Niets wordt ooit als "klaar" gemeld tenzij een herhashing dat bewijst, en niets wordt overschreven zonder eerst een back-up.

## Bijzonderheden

Wat VDLU onderscheidt van een typische OTA-client:

- **Flashloos en incrementeel.** Inhoudsgeadresseerd diff / fetch / apply met dedup: het apparaat berekent het delta tegen de gesigneerde feed en haalt alleen ontbrekende blobs op.
- **Herstartvrij waar mogelijk.** Gewone bestanden worden live toegepast; alleen `.so`, `/system`-overlays en `sepolicy.rule`-bestanden worden gefaseerd en bij een enkele herstart omgewisseld. Zie [[Reboot Handling]].
- **POSIX `sh` op het apparaat.** Draait onder toybox / busybox / mksh. Geen `jq` (een `gron`-achtige `awk`-flattener parst JSON), geen `bash`-trucs, geen zware runtime.
- **Slanke verificatie.** Een ingebedde `ed25519-mini` verifieert handtekeningen. Er is **geen `openssl` op het apparaat**; de private sleutel raakt nooit een apparaat of CI aan.
- **Fail-closed-beveiliging.** `validate_plan()` verwerpt het **hele** manifest bij elk ongeldig veld (absoluut of `..`-pad, een `sha256` die geen 64 hex-tekens is, een ongeldige mode / class / encoding). Twee profielen, `trusted` en `hardened`, waarbij `hardened` door inversie fail-closed is. Zie [[Security and Trust Model]].
- **Hervatbaar en atomair.** Een journal maakt elke transactie crashbestendig; schrijfbewerkingen gebruiken `rename` / `mv`; vóór elk overschrijven wordt een back-up gemaakt, zodat een mislukt apply terugrolt in plaats van de module te beschadigen.

## Begin hier

| Als je wilt... | Ga naar |
|---|---|
| VDLU stap voor stap in je module overnemen | [[Quick Start]] |
| Het hele systeem in één oogopslag begrijpen | [[Architecture]] |
| De apparaatzijdige engine (`update.sh`) leren kennen | [[Engine]] |
| Een feed op je pc bouwen en signeren | [[Producer]] |
| Het Updates-paneel inpluggen | [[WebUI]] |
| Het vertrouwensmodel en de dreigingshouding lezen | [[Security and Trust Model]] |
| De manifest- en blob-indeling bekijken | [[Feed Format]] |
| Weten wat een herstart vereist en waarom | [[Reboot Handling]] |
| Een veelgestelde vraag stellen | [[FAQ]] |
| Bijdragen | [[Contributing]] |

## Projectlinks

- **Broncode:** https://github.com/VD171/VDLiveUpdate
- **Kanaal (updates):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate is een onafhankelijk, onofficieel project. "Android" is een handelsmerk van Google LLC; "KernelSU", "Magisk" en "APatch" zijn de merken van hun respectieve auteurs. VDLU draait volledig op je apparaat en je eigen release-host.
