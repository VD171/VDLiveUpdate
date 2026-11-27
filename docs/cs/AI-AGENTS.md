> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · Čeština · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Řízení VDLU z AI agenta

VDLiveUpdate (VDLU) je bezflashový, přírůstkový aktualizátor, který moduly KSU/Magisk vestavují do `vdlu/`. Celý engine se řídí ze shellu, takže AI asistent nebo agent může zkontrolovat, aplikovat, obnovit a dokončit aktualizaci bezhlavě, stejný cyklus, jaký běží ve WebUI, bez UI a bez člověka ve smyčce. Parsuj JSON, který vytiskne, nikdy nescrapuj text.

## Smlouva

Jediný vstupní bod, spuštěný jako root na zařízení, se třemi nastavenými proměnnými prostředí enginu:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` je adresář stavu Tier-2 (mimo modul, přežije reflash), `MODULE_DIR` je živý strom modulu, `MODID` je id modulu.
- `rc 0` = ok, `rc != 0` = chyba, s důvodem na stderr.
- Čtecí slovesa (`check`, `status`) tisknou **jeden JSON objekt** na stdout. Naparsuj ho, nikdy nescrapuj text.
- Engine závisí jen na toybox (`sha256sum`/`gzip`/`base64`) plus vestavěném `ed25519-mini` plus statickém `curl` staženém při první https aktualizaci, nula `jq`.

Během vývoje leží stejný skript v `engine/update.sh` v tomto repozitáři, takže `sh engine/update.sh <verb>` se třemi nastavenými proměnnými řídí testovací kopii stejným způsobem.

## Slovesa

| Sloveso | Dělá | Tiskne |
|------|------|--------|
| `check` | DIFF jen pro čtení proti kanálu, nic nemění | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, nebo `{"update":false,"ahead":true,"from":N,"to":M}` když je zařízení napřed před kanálem (downgrade blokován, neškodné, rc 0) |
| `run` | plný cyklus LIVE DIFF -> FETCH -> APPLY -> COMMIT, aplikuje soubory LIVE a inscenuje REBOOT-hard, respektuje `cancel` | postup v `journal.json` |
| `resume` | obnovuje čekající transakci z její aktuální fáze, idempotentní, nikdy nevyměňuje `.so` | aktualizovaný `journal.json` |
| `boot` | režim pre-zygote, `resume` plus výměna inscenovaného `.so`, uzavírá `PENDING_REBOOT` do `DONE` | aktualizovaný `journal.json` |
| `status` | snímek jen pro čtení, nic nemění | `journal.json`, nebo `{"state":"idle"}` když není aktivní žádná transakce |
| `cancel` | žádá o zastavení, probíhající `run` se zastaví v příštím bezpečném bodě | vytváří `$VDLU_DIR/cancel` |

Bezhlavá aktualizace je `check`, aby se zjistilo, zda něco čeká, `run`, aby se aplikovalo vše, co může jít naživo, pak `boot` při příštím startu, aby se vyměnil jakýkoli inscenovaný `.so` (nebo `resume`, aby se zopakoval odložený fetch). Každé sloveso je bezpečné volat znovu, pád nebo výpadek sítě uprostřed cyklu zanechá obnovitelný žurnál, nikdy napůl aplikovaný modul.

## JSON stavu

`status` (a živý soubor v `$VDLU_DIR/journal.json`) je smlouva o postupu, kterou WebUI i agent oba čtou:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` se pohybuje v pevném pořadí: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` se dosáhne až poté, co re-hash všeho souhlasí. Inscenovaný soubor REBOOT-hard dává `PENDING_REBOOT`, nikdy falešné `DONE`, spusť `boot`, abys ho dokončil.
- `DEFERRED` znamená, že `net_policy` zablokovala stahování, neškodný a obnovitelný stav a nikoli chyba, plán přetrvává a příští `check`/`boot` pokračuje.
- `ERROR` nese důvod v `error`, aplikované soubory LIVE se vracejí z `rollback/`, modul nikdy nezůstane napůl aplikovaný.
- `cancelled:true` s `error:null` je čisté zastavení, žurnál zůstává obnovitelný.

## Smlouva o švu

Každá komponenta (engine, producent, WebUI) odpovídá [`INTERFACES.md`](INTERFACES.md), zákonu konvergence. Slovesa CLI, schéma `manifest.json`, klíče `journal.json` a tam definované klíče config jsou **neměnné**, zacházej s tím souborem jako s jediným zdrojem pravdy a sladěj se s ním, než cokoli z nich změníš. Pro vnitřnosti enginu (obnovitelná transakce, záruky přísnosti, vyloučení trust-anchor) viz [`ENGINE.md`](ENGINE.md), pro stranu kanálu (sestavení a podepsání kanálu adresovaného obsahem) viz [`PRODUCER.md`](PRODUCER.md).

## Pravidla pro agenta

- Používej slovesa a JSON, nikdy nescrapuj WebUI a nikdy needituj stavové soubory ručně.
- Zacházej s `INTERFACES.md` jako s neměnným, změna znamená nejprve sladit smlouvu.
- Patch od AI agenta projde stejnou laťkou revize jako kterýkoli jiný, build vždy release, nic neuvolňuj, nic neztrácej.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány, viz [CONTRIBUTING.md](CONTRIBUTING.md)._
