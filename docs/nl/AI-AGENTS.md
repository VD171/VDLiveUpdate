> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · Nederlands · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# VDLU aansturen vanuit een AI-agent

VDLiveUpdate (VDLU) is de flashloze, incrementele updater die KSU/Magisk-modules in `vdlu/` meeleveren. De hele engine wordt vanuit de shell aangestuurd, zodat een AI-assistent of agent een update headless kan controleren, toepassen, hervatten en afronden, dezelfde cyclus die de WebUI draait, zonder UI en zonder mens in de lus. Parse de JSON die het afdrukt, scrape nooit tekst.

## Het contract

Eén ingangspunt, als root uitgevoerd op het apparaat, met de drie omgevingsvariabelen van de engine ingesteld:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` is de Tier-2-statusmap (buiten de module, overleeft een reflash), `MODULE_DIR` is de levende moduleboom, `MODID` is de module-id.
- `rc 0` = ok, `rc != 0` = fout, met de reden op stderr.
- De leeswerkwoorden (`check`, `status`) drukken **één JSON-object** af op stdout. Parse dat, scrape nooit tekst.
- De engine hangt alleen af van toybox (`sha256sum`/`gzip`/`base64`) plus een ingebedde `ed25519-mini` plus een statische `curl` die bij de eerste https-update wordt opgehaald, nul `jq`.

Tijdens de ontwikkeling staat hetzelfde script in `engine/update.sh` in deze repository, dus `sh engine/update.sh <verb>` met de drie variabelen ingesteld stuurt een testkopie op dezelfde manier aan.

## Werkwoorden

| Werkwoord | Doet | Drukt af |
|------|------|--------|
| `check` | alleen-lezen DIFF tegen de feed, verandert niets | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, of `{"update":false,"ahead":true,"from":N,"to":M}` wanneer het apparaat voorloopt op de feed (downgrade geblokkeerd, onschadelijk, rc 0) |
| `run` | volledige LIVE-cyclus DIFF -> FETCH -> APPLY -> COMMIT, past LIVE-bestanden toe en staget de REBOOT-hard, respecteert `cancel` | voortgang in `journal.json` |
| `resume` | hervat de openstaande transactie vanaf de huidige fase, idempotent, verwisselt nooit de `.so` | bijgewerkte `journal.json` |
| `boot` | pre-zygote-modus, `resume` plus de omwisseling van de gestagede `.so`, sluit `PENDING_REBOOT` af naar `DONE` | bijgewerkte `journal.json` |
| `status` | alleen-lezen snapshot, verandert niets | `journal.json`, of `{"state":"idle"}` wanneer geen transactie actief is |
| `cancel` | vraagt een stop aan, een lopende `run` stopt op het volgende veilige punt | maakt `$VDLU_DIR/cancel` aan |

Een headless update is `check` om te zien of er iets openstaat, `run` om alles toe te passen dat live kan, dan `boot` bij de volgende boot om een gestagede `.so` te verwisselen (of `resume` om een uitgestelde fetch opnieuw te proberen). Elk werkwoord is veilig om opnieuw aan te roepen, een crash of een wegvallend netwerk halverwege de cyclus laat een hervatbaar journal achter, nooit een half toegepaste module.

## Status-JSON

`status` (en het levende bestand in `$VDLU_DIR/journal.json`) is het voortgangscontract dat de WebUI en een agent beide lezen:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` beweegt in een vaste volgorde: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` wordt pas bereikt nadat een re-hash van alles overeenkomt. Een gestaged REBOOT-hard-bestand levert `PENDING_REBOOT` op, nooit een nep-`DONE`, draai `boot` om het af te ronden.
- `DEFERRED` betekent dat `net_policy` de download blokkeerde, een onschadelijke, hervatbare toestand en geen fout, het plan blijft bestaan en de volgende `check`/`boot` gaat verder.
- `ERROR` draagt de reden in `error`, de toegepaste LIVE-bestanden worden teruggedraaid vanuit `rollback/`, de module blijft nooit half toegepast.
- `cancelled:true` met `error:null` is een schone stop, het journal blijft hervatbaar.

## Het naadcontract

Elk component (engine, producer, WebUI) voldoet aan [`INTERFACES.md`](INTERFACES.md), de wet van convergentie. De CLI-werkwoorden, het `manifest.json`-schema, de `journal.json`-sleutels en de daar gedefinieerde config-sleutels zijn **onveranderlijk**, behandel dat bestand als de enige bron van waarheid en richt je erop voordat je er iets van wijzigt. Voor de engine-interne werking (de hervatbare transactie, de rigueur-garanties, de trust-anchor-uitsluiting) zie [`ENGINE.md`](ENGINE.md), voor de feedkant (de inhoudsgeadresseerde feed bouwen en ondertekenen) zie [`PRODUCER.md`](PRODUCER.md).

## Regels voor een agent

- Gebruik de werkwoorden en de JSON, scrape nooit de WebUI en bewerk nooit de statusbestanden met de hand.
- Behandel `INTERFACES.md` als onveranderlijk, een wijziging betekent eerst het contract uitlijnen.
- Een patch van een AI-agent haalt dezelfde reviewlat als elke andere, build altijd release, versoepel niets, verlies niets.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom, zie [CONTRIBUTING.md](CONTRIBUTING.md)._
