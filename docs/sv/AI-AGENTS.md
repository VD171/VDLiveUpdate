> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · Svenska · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Styra VDLU från en AI-agent

VDLiveUpdate (VDLU) är den flashfria, inkrementella uppdateraren som KSU/Magisk-moduler bäddar in i `vdlu/`. Hela motorn styrs från skalet, så en AI-assistent eller agent kan kontrollera, tillämpa, återuppta och slutföra en uppdatering huvudlöst, samma cykel som WebUI kör, utan UI och utan människa i slingan. Tolka JSON som den skriver ut, skrapa aldrig text.

## Kontraktet

En enda ingångspunkt, körd som root på enheten, med motorns tre miljövariabler satta:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` är Tier-2-tillståndskatalogen (utanför modulen, överlever en omflashning), `MODULE_DIR` är modulens levande träd, `MODID` är modulens id.
- `rc 0` = ok, `rc != 0` = fel, med orsaken på stderr.
- Läsverben (`check`, `status`) skriver ut **ett JSON-objekt** på stdout. Tolka det, skrapa aldrig text.
- Motorn beror bara på toybox (`sha256sum`/`gzip`/`base64`) plus en inbäddad `ed25519-mini` plus en statisk `curl` som hämtas vid den första https-uppdateringen, noll `jq`.

Under utvecklingen ligger samma skript i `engine/update.sh` i detta repository, så `sh engine/update.sh <verb>` med de tre variablerna satta styr en testkopia på samma sätt.

## Verb

| Verb | Gör | Skriver ut |
|------|------|--------|
| `check` | skrivskyddad DIFF mot flödet, ändrar ingenting | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, eller `{"update":false,"ahead":true,"from":N,"to":M}` när enheten är före flödet (nedgradering blockerad, godartat, rc 0) |
| `run` | full LIVE-cykel DIFF -> FETCH -> APPLY -> COMMIT, tillämpar LIVE-filer och iscensätter REBOOT-hard, respekterar `cancel` | förlopp i `journal.json` |
| `resume` | återupptar den väntande transaktionen från dess aktuella fas, idempotent, byter aldrig `.so` | uppdaterad `journal.json` |
| `boot` | pre-zygote-läge, `resume` plus bytet av den iscensatta `.so`, stänger `PENDING_REBOOT` till `DONE` | uppdaterad `journal.json` |
| `status` | skrivskyddad ögonblicksbild, ändrar ingenting | `journal.json`, eller `{"state":"idle"}` när ingen transaktion är aktiv |
| `cancel` | begär ett stopp, ett pågående `run` stannar vid nästa säkra punkt | skapar `$VDLU_DIR/cancel` |

En huvudlös uppdatering är `check` för att se om något väntar, `run` för att tillämpa allt som kan gå live, sedan `boot` vid nästa start för att byta varje iscensatt `.so` (eller `resume` för att försöka om en uppskjuten hämtning). Varje verb är säkert att anropa igen, en krasch eller ett tappat nätverk mitt i cykeln lämnar en återupptagbar journal, aldrig en halvt tillämpad modul.

## Status-JSON

`status` (och den levande filen i `$VDLU_DIR/journal.json`) är förloppskontraktet som WebUI och en agent båda läser:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` rör sig i fast ordning: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` nås först efter att en ny hashning av allt stämmer. En iscensatt REBOOT-hard-fil ger `PENDING_REBOOT`, aldrig ett falskt `DONE`, kör `boot` för att slutföra den.
- `DEFERRED` betyder att `net_policy` blockerade nedladdningen, ett godartat och återupptagbart tillstånd och inte ett fel, planen består och nästa `check`/`boot` fortsätter.
- `ERROR` bär orsaken i `error`, de tillämpade LIVE-filerna återställs från `rollback/`, modulen lämnas aldrig halvt tillämpad.
- `cancelled:true` med `error:null` är ett rent stopp, journalen förblir återupptagbar.

## Fogkontraktet

Varje komponent (motor, producent, WebUI) följer [`INTERFACES.md`](INTERFACES.md), konvergensens lag. CLI-verben, `manifest.json`-schemat, `journal.json`-nycklarna och config-nycklarna som definieras där är **oföränderliga**, behandla den filen som den enda sanningskällan och rätta dig efter den innan du ändrar någon av dem. För motorns inre delar (den återupptagbara transaktionen, rigor-garantierna, trust-anchor-uteslutningen) se [`ENGINE.md`](ENGINE.md), för flödessidan (att bygga och signera det innehållsadresserade flödet) se [`PRODUCER.md`](PRODUCER.md).

## Regler för en agent

- Använd verben och JSON, skrapa aldrig WebUI och redigera aldrig tillståndsfilerna för hand.
- Behandla `INTERFACES.md` som oföränderlig, en ändring betyder att först rätta in kontraktet.
- En patch från en AI-agent klarar samma granskningsribba som vilken annan som helst, build alltid release, lätta inte på något, förlora inget.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
