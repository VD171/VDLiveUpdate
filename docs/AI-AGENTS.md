> **Languages:** English · [العربية](ar/AI-AGENTS.md) · [Čeština](cs/AI-AGENTS.md) · [Deutsch](de/AI-AGENTS.md) · [Español](es/AI-AGENTS.md) · [فارسی](fa/AI-AGENTS.md) · [Français](fr/AI-AGENTS.md) · [हिन्दी](hi/AI-AGENTS.md) · [Bahasa Indonesia](id/AI-AGENTS.md) · [Italiano](it/AI-AGENTS.md) · [日本語](ja/AI-AGENTS.md) · [한국어](ko/AI-AGENTS.md) · [Nederlands](nl/AI-AGENTS.md) · [Polski](pl/AI-AGENTS.md) · [Português](pt/AI-AGENTS.md) · [Русский](ru/AI-AGENTS.md) · [Svenska](sv/AI-AGENTS.md) · [ไทย](th/AI-AGENTS.md) · [Türkçe](tr/AI-AGENTS.md) · [Українська](uk/AI-AGENTS.md) · [Tiếng Việt](vi/AI-AGENTS.md) · [中文](zh/AI-AGENTS.md)

---

# Driving VDLU from an AI agent

VDLiveUpdate (VDLU) is the flashless, incremental updater that KSU/Magisk modules
vendor in `vdlu/`. The whole engine is driven from the shell, so an AI assistant
or agent can check, apply, resume and finish an update headlessly, the same cycle
the WebUI runs, with no UI and no human in the loop. Parse the JSON it prints,
never scrape text.

## The contract

One entry point, run as root on the device, with the engine's three environment
variables set:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` is the Tier-2 state dir (outside the module, survives a reflash),
  `MODULE_DIR` is the live module tree, `MODID` is the module id.
- `rc 0` = ok, `rc != 0` = error with the reason on stderr.
- The read verbs (`check`, `status`) print **one JSON object** on stdout. Parse
  that, never scrape text.
- The engine depends only on toybox (`sha256sum`/`gzip`/`base64`) plus an embedded
  `ed25519-mini` plus a static `curl` fetched on the first https update, zero `jq`.

During development the same script lives at `engine/update.sh` in this repo, so
`sh engine/update.sh <verb>` with the three variables set drives a staging copy
the same way.

## Verbs

| Verb | Does | Prints |
|------|------|--------|
| `check` | read-only DIFF against the feed, changes nothing | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, or `{"update":false,"ahead":true,"from":N,"to":M}` when the device is ahead of the feed (downgrade blocked, benign, rc 0) |
| `run` | full LIVE cycle DIFF -> FETCH -> APPLY -> COMMIT, applies LIVE files and stages REBOOT-hard ones, honors `cancel` | progress in `journal.json` |
| `resume` | resumes the pending transaction from its current phase, idempotent, never swaps the `.so` | updated `journal.json` |
| `boot` | pre-zygote mode, `resume` plus the swap of the staged `.so`, closes `PENDING_REBOOT` into `DONE` | updated `journal.json` |
| `status` | read-only snapshot, changes nothing | `journal.json`, or `{"state":"idle"}` when no transaction is active |
| `cancel` | requests a stop, an in-flight `run` halts at the next safe point | creates `$VDLU_DIR/cancel` |

A headless update is `check` to see whether anything is pending, `run` to apply
everything that can go live, then `boot` on the next boot to swap any staged `.so`
(or `resume` to retry a deferred fetch). Every verb is safe to call again, a crash
or a dropped network mid-cycle leaves a resumable journal, never a half-applied
module.

## Status JSON

`status` (and the live file at `$VDLU_DIR/journal.json`) is the progress contract
that the WebUI and an agent both read:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` moves in a fixed order: `PLANNED -> FETCHING -> FETCHED -> APPLYING ->
  APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` is reached only after a re-hash of everything matches. A staged
  REBOOT-hard file yields `PENDING_REBOOT`, never a bogus `DONE`, run `boot` to
  finish it.
- `DEFERRED` means `net_policy` blocked the download, a benign resumable state and
  not an error, the plan persists and the next `check`/`boot` continues.
- `ERROR` carries the reason in `error`, the applied LIVE files are reverted from
  `rollback/`, the module is never left half-applied.
- `cancelled:true` with `error:null` is a clean stop, the journal stays resumable.

## The seam contract

Every component (engine, producer, WebUI) conforms to
[`INTERFACES.md`](INTERFACES.md), the law of convergence. The CLI verbs, the
`manifest.json` schema, the `journal.json` keys and the config keys defined there
are **immutable**, treat that file as the single source of truth and align to it
before changing any of them. For the engine internals (the resumable transaction,
the rigor guarantees, the trust-anchor exclusion) see [`ENGINE.md`](ENGINE.md),
for the feed side (building and signing the content-addressed feed) see
[`PRODUCER.md`](PRODUCER.md).

## Rules for an agent

- Use the verbs and the JSON, never scrape the WebUI and never edit the state
  files by hand.
- Treat `INTERFACES.md` as immutable, a change means aligning the contract first.
- A patch from an AI agent meets the same review bar as any other, build always
  release, loosen nothing, lose nothing.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome, see [CONTRIBUTING.md](../CONTRIBUTING.md)._
