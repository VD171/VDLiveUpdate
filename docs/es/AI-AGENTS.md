> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · Español · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Operar VDLU desde un agente de IA

VDLiveUpdate (VDLU) es el actualizador incremental y sin flasheo que los módulos KSU/Magisk incorporan en `vdlu/`. Todo el motor se opera desde el shell, así que un asistente o agente de IA puede comprobar, aplicar, reanudar y finalizar una actualización de forma headless, el mismo ciclo que ejecuta la WebUI, sin UI y sin humano en el circuito. Interpreta el JSON que imprime, nunca raspes texto.

## El contrato

Un único punto de entrada, ejecutado como root en el dispositivo, con las tres variables de entorno del motor definidas:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` es el directorio de estado Tier-2 (fuera del módulo, sobrevive a un reflasheo), `MODULE_DIR` es el árbol vivo del módulo, `MODID` es el id del módulo.
- `rc 0` = ok, `rc != 0` = error, con el motivo en stderr.
- Los verbos de lectura (`check`, `status`) imprimen **un objeto JSON** en stdout. Interprétalo, nunca raspes texto.
- El motor depende solo de toybox (`sha256sum`/`gzip`/`base64`) más un `ed25519-mini` incorporado más un `curl` estático descargado en la primera actualización https, cero `jq`.

Durante el desarrollo el mismo script vive en `engine/update.sh` en este repositorio, así que `sh engine/update.sh <verb>` con las tres variables definidas opera una copia de pruebas de la misma forma.

## Verbos

| Verbo | Hace | Imprime |
|------|------|--------|
| `check` | DIFF de solo lectura contra el feed, no cambia nada | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, o `{"update":false,"ahead":true,"from":N,"to":M}` cuando el dispositivo va por delante del feed (downgrade bloqueado, benigno, rc 0) |
| `run` | ciclo LIVE completo DIFF -> FETCH -> APPLY -> COMMIT, aplica los archivos LIVE y escena los REBOOT-hard, respeta `cancel` | progreso en `journal.json` |
| `resume` | reanuda la transacción pendiente desde su fase actual, idempotente, nunca cambia el `.so` | `journal.json` actualizado |
| `boot` | modo pre-zygote, `resume` más el cambio del `.so` escenificado, cierra `PENDING_REBOOT` en `DONE` | `journal.json` actualizado |
| `status` | instantánea de solo lectura, no cambia nada | `journal.json`, o `{"state":"idle"}` cuando ninguna transacción está activa |
| `cancel` | solicita una parada, un `run` en curso se detiene en el siguiente punto seguro | crea `$VDLU_DIR/cancel` |

Una actualización headless es `check` para ver si hay algo pendiente, `run` para aplicar todo lo que puede ir en vivo, y luego `boot` en el siguiente arranque para cambiar cualquier `.so` escenificado (o `resume` para reintentar una descarga aplazada). Cada verbo es seguro de llamar de nuevo, un fallo o una caída de red a mitad de ciclo deja un journal reanudable, nunca un módulo a medio aplicar.

## JSON de estado

`status` (y el archivo vivo en `$VDLU_DIR/journal.json`) es el contrato de progreso que la WebUI y un agente leen:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` avanza en orden fijo: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` solo se alcanza después de que un re-hash de todo coincide. Un archivo REBOOT-hard escenificado produce `PENDING_REBOOT`, nunca un `DONE` falso, ejecuta `boot` para terminarlo.
- `DEFERRED` significa que `net_policy` bloqueó la descarga, un estado benigno y reanudable y no un error, el plan persiste y el siguiente `check`/`boot` continúa.
- `ERROR` lleva el motivo en `error`, los archivos LIVE aplicados se revierten desde `rollback/`, el módulo nunca queda a medio aplicar.
- `cancelled:true` con `error:null` es una parada limpia, el journal sigue reanudable.

## El contrato de costura

Cada componente (motor, productor, WebUI) se conforma a [`INTERFACES.md`](INTERFACES.md), la ley de convergencia. Los verbos de la CLI, el esquema del `manifest.json`, las claves del `journal.json` y las claves de config definidas ahí son **inmutables**, trata ese archivo como la única fuente de verdad y alinéate con él antes de cambiar cualquiera de ellos. Para los internos del motor (la transacción reanudable, las garantías de rigor, la exclusión del trust-anchor) consulta [`ENGINE.md`](ENGINE.md), para el lado del feed (construir y firmar el feed direccionado por contenido) consulta [`PRODUCER.md`](PRODUCER.md).

## Reglas para un agente

- Usa los verbos y el JSON, nunca raspes la WebUI ni edites los archivos de estado a mano.
- Trata `INTERFACES.md` como inmutable, un cambio significa alinear el contrato primero.
- Un parche de un agente de IA pasa por la misma barra de revisión que cualquier otro, build siempre release, no aflojes nada, no pierdas nada.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas, consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
