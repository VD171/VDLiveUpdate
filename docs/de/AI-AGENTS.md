> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · Deutsch · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# VDLU mit einem KI-Agenten steuern

VDLiveUpdate (VDLU) ist der flashlose, inkrementelle Updater, den KSU/Magisk-Module in `vdlu/` einbetten. Die gesamte Engine wird aus der Shell gesteuert, sodass ein KI-Assistent oder Agent ein Update headless prüfen, anwenden, fortsetzen und abschließen kann, derselbe Zyklus, den die WebUI fährt, ohne UI und ohne Mensch im Ablauf. Werte das ausgegebene JSON aus, scrape niemals Text.

## Der Vertrag

Ein einziger Einstiegspunkt, als root auf dem Gerät ausgeführt, mit den drei gesetzten Umgebungsvariablen der Engine:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` ist das Tier-2-Statusverzeichnis (außerhalb des Moduls, übersteht einen Reflash), `MODULE_DIR` ist der lebende Modulbaum, `MODID` ist die Modul-ID.
- `rc 0` = ok, `rc != 0` = Fehler, mit dem Grund auf stderr.
- Die Leseverben (`check`, `status`) geben **ein JSON-Objekt** auf stdout aus. Werte das aus, scrape niemals Text.
- Die Engine hängt nur von toybox (`sha256sum`/`gzip`/`base64`) plus einem eingebetteten `ed25519-mini` plus einem beim ersten https-Update geladenen statischen `curl` ab, null `jq`.

Während der Entwicklung liegt dasselbe Skript als `engine/update.sh` in diesem Repository, sodass `sh engine/update.sh <verb>` mit den drei gesetzten Variablen eine Testkopie genauso steuert.

## Verben

| Verb | Tut | Gibt aus |
|------|------|--------|
| `check` | schreibgeschütztes DIFF gegen den Feed, ändert nichts | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, oder `{"update":false,"ahead":true,"from":N,"to":M}`, wenn das Gerät dem Feed voraus ist (Downgrade blockiert, harmlos, rc 0) |
| `run` | voller LIVE-Zyklus DIFF -> FETCH -> APPLY -> COMMIT, wendet LIVE-Dateien an und staged die REBOOT-hard, beachtet `cancel` | Fortschritt in `journal.json` |
| `resume` | setzt die ausstehende Transaktion ab ihrer aktuellen Phase fort, idempotent, tauscht nie die `.so` | aktualisierte `journal.json` |
| `boot` | pre-zygote-Modus, `resume` plus der Tausch der gestagten `.so`, schließt `PENDING_REBOOT` zu `DONE` | aktualisierte `journal.json` |
| `status` | schreibgeschützter Snapshot, ändert nichts | `journal.json`, oder `{"state":"idle"}`, wenn keine Transaktion aktiv ist |
| `cancel` | fordert einen Stopp an, ein laufendes `run` hält am nächsten sicheren Punkt | erstellt `$VDLU_DIR/cancel` |

Ein headless Update ist `check`, um zu sehen, ob etwas ansteht, `run`, um alles anzuwenden, was live gehen kann, dann `boot` beim nächsten Boot, um eine gestagte `.so` zu tauschen (oder `resume`, um einen aufgeschobenen Fetch zu wiederholen). Jedes Verb ist gefahrlos erneut aufrufbar, ein Absturz oder ein Netzausfall mitten im Zyklus hinterlässt ein fortsetzbares Journal, nie ein halb angewendetes Modul.

## Status-JSON

`status` (und die lebende Datei unter `$VDLU_DIR/journal.json`) ist der Fortschrittsvertrag, den die WebUI und ein Agent beide lesen:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` bewegt sich in fester Reihenfolge: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` wird erst erreicht, nachdem ein Re-Hash von allem stimmt. Eine gestagte REBOOT-hard-Datei ergibt `PENDING_REBOOT`, nie ein falsches `DONE`, führe `boot` aus, um es abzuschließen.
- `DEFERRED` bedeutet, dass `net_policy` den Download blockiert hat, ein harmloser, fortsetzbarer Zustand und kein Fehler, der Plan bleibt bestehen und der nächste `check`/`boot` fährt fort.
- `ERROR` trägt den Grund in `error`, die angewendeten LIVE-Dateien werden aus `rollback/` zurückgesetzt, das Modul bleibt nie halb angewendet.
- `cancelled:true` mit `error:null` ist ein sauberer Stopp, das Journal bleibt fortsetzbar.

## Der Nahtvertrag

Jede Komponente (Engine, Producer, WebUI) richtet sich nach [`INTERFACES.md`](INTERFACES.md), dem Gesetz der Konvergenz. Die CLI-Verben, das `manifest.json`-Schema, die `journal.json`-Schlüssel und die dort definierten Config-Schlüssel sind **unveränderlich**, behandle diese Datei als einzige Quelle der Wahrheit und richte dich nach ihr aus, bevor du etwas davon änderst. Für die Engine-Interna (die fortsetzbare Transaktion, die Rigoros-Garantien, die Trust-Anchor-Ausschlusslogik) siehe [`ENGINE.md`](ENGINE.md), für die Feed-Seite (den inhaltsadressierten Feed bauen und signieren) siehe [`PRODUCER.md`](PRODUCER.md).

## Regeln für einen Agenten

- Nutze die Verben und das JSON, scrape nie die WebUI und bearbeite nie die Statusdateien von Hand.
- Behandle `INTERFACES.md` als unveränderlich, eine Änderung heißt, zuerst den Vertrag anzugleichen.
- Ein Patch von einem KI-Agenten erfüllt dieselbe Review-Latte wie jeder andere, build immer release, lockere nichts, verliere nichts.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen, siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
