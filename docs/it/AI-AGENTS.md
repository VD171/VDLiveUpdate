> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · Italiano · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Guidare VDLU da un agente IA

VDLiveUpdate (VDLU) è l'aggiornatore incrementale e senza flash che i moduli KSU/Magisk incorporano in `vdlu/`. L'intero motore si guida dalla shell, quindi un assistente o agente IA può verificare, applicare, riprendere e completare un aggiornamento in modalità headless, lo stesso ciclo che esegue la WebUI, senza UI e senza umano nel giro. Analizza il JSON che stampa, non fare mai scraping del testo.

## Il contratto

Un unico punto di ingresso, eseguito come root sul dispositivo, con le tre variabili d'ambiente del motore impostate:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` è la directory di stato Tier-2 (fuori dal modulo, sopravvive a un reflash), `MODULE_DIR` è l'albero vivo del modulo, `MODID` è l'id del modulo.
- `rc 0` = ok, `rc != 0` = errore, con il motivo su stderr.
- I verbi di lettura (`check`, `status`) stampano **un oggetto JSON** su stdout. Analizzalo, non fare mai scraping del testo.
- Il motore dipende solo da toybox (`sha256sum`/`gzip`/`base64`) più un `ed25519-mini` incorporato più un `curl` statico scaricato al primo aggiornamento https, zero `jq`.

Durante lo sviluppo lo stesso script risiede in `engine/update.sh` in questo repository, quindi `sh engine/update.sh <verb>` con le tre variabili impostate guida una copia di prova allo stesso modo.

## Verbi

| Verbo | Fa | Stampa |
|------|------|--------|
| `check` | DIFF in sola lettura contro il feed, non cambia nulla | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, oppure `{"update":false,"ahead":true,"from":N,"to":M}` quando il dispositivo è avanti rispetto al feed (downgrade bloccato, benigno, rc 0) |
| `run` | ciclo LIVE completo DIFF -> FETCH -> APPLY -> COMMIT, applica i file LIVE e mette in scena i REBOOT-hard, rispetta `cancel` | progresso in `journal.json` |
| `resume` | riprende la transazione in sospeso dalla sua fase corrente, idempotente, non scambia mai il `.so` | `journal.json` aggiornato |
| `boot` | modalità pre-zygote, `resume` più lo scambio del `.so` messo in scena, chiude `PENDING_REBOOT` in `DONE` | `journal.json` aggiornato |
| `status` | snapshot in sola lettura, non cambia nulla | `journal.json`, oppure `{"state":"idle"}` quando nessuna transazione è attiva |
| `cancel` | richiede uno stop, un `run` in corso si ferma al prossimo punto sicuro | crea `$VDLU_DIR/cancel` |

Un aggiornamento headless è `check` per vedere se c'è qualcosa in sospeso, `run` per applicare tutto ciò che può andare in vivo, poi `boot` al prossimo avvio per scambiare ogni `.so` messo in scena (o `resume` per ritentare un fetch rimandato). Ogni verbo è sicuro da richiamare, un crash o una caduta di rete a metà ciclo lascia un journal ripristinabile, mai un modulo applicato a metà.

## JSON di stato

`status` (e il file vivo in `$VDLU_DIR/journal.json`) è il contratto di progresso che la WebUI e un agente leggono entrambi:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` si muove in ordine fisso: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` si raggiunge solo dopo che un re-hash di tutto combacia. Un file REBOOT-hard messo in scena produce `PENDING_REBOOT`, mai un `DONE` fasullo, esegui `boot` per completarlo.
- `DEFERRED` significa che `net_policy` ha bloccato il download, uno stato benigno e ripristinabile e non un errore, il piano persiste e il prossimo `check`/`boot` continua.
- `ERROR` porta il motivo in `error`, i file LIVE applicati vengono ripristinati da `rollback/`, il modulo non resta mai applicato a metà.
- `cancelled:true` con `error:null` è uno stop pulito, il journal resta ripristinabile.

## Il contratto di cucitura

Ogni componente (motore, produttore, WebUI) si conforma a [`INTERFACES.md`](INTERFACES.md), la legge di convergenza. I verbi della CLI, lo schema del `manifest.json`, le chiavi del `journal.json` e le chiavi di config definite lì sono **immutabili**, tratta quel file come l'unica fonte di verità e allineati ad esso prima di cambiarne uno. Per gli interni del motore (la transazione ripristinabile, le garanzie di rigore, l'esclusione del trust-anchor) vedi [`ENGINE.md`](ENGINE.md), per il lato feed (costruire e firmare il feed indirizzato per contenuto) vedi [`PRODUCER.md`](PRODUCER.md).

## Regole per un agente

- Usa i verbi e il JSON, non fare mai scraping della WebUI e non modificare mai i file di stato a mano.
- Tratta `INTERFACES.md` come immutabile, un cambiamento significa allineare prima il contratto.
- Una patch di un agente IA supera la stessa asticella di revisione di qualsiasi altra, build sempre release, non allentare nulla, non perdere nulla.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti, vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
