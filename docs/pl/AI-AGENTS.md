> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · Polski · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Sterowanie VDLU z agenta AI

VDLiveUpdate (VDLU) to przyrostowy, bezflashowy aktualizator, który moduły KSU/Magisk wbudowują w `vdlu/`. Cały silnik sterowany jest z powłoki, więc asystent lub agent AI może sprawdzić, zastosować, wznowić i dokończyć aktualizację bezgłowo, ten sam cykl, który uruchamia WebUI, bez UI i bez człowieka w pętli. Parsuj JSON, który wypisuje, nigdy nie zeskrobuj tekstu.

## Kontrakt

Jeden punkt wejścia, uruchamiany jako root na urządzeniu, z trzema ustawionymi zmiennymi środowiskowymi silnika:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` to katalog stanu Tier-2 (poza modułem, przetrwa reflash), `MODULE_DIR` to żywe drzewo modułu, `MODID` to id modułu.
- `rc 0` = ok, `rc != 0` = błąd, z powodem na stderr.
- Czasowniki odczytu (`check`, `status`) wypisują **jeden obiekt JSON** na stdout. Sparsuj go, nigdy nie zeskrobuj tekstu.
- Silnik zależy tylko od toybox (`sha256sum`/`gzip`/`base64`) plus wbudowany `ed25519-mini` plus statyczny `curl` pobrany przy pierwszej aktualizacji https, zero `jq`.

Podczas developmentu ten sam skrypt leży w `engine/update.sh` w tym repozytorium, więc `sh engine/update.sh <verb>` z ustawionymi trzema zmiennymi steruje kopią testową w ten sam sposób.

## Czasowniki

| Czasownik | Robi | Wypisuje |
|------|------|--------|
| `check` | DIFF tylko do odczytu wobec kanału, nic nie zmienia | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, lub `{"update":false,"ahead":true,"from":N,"to":M}` gdy urządzenie wyprzedza kanał (downgrade zablokowany, łagodny, rc 0) |
| `run` | pełny cykl LIVE DIFF -> FETCH -> APPLY -> COMMIT, stosuje pliki LIVE i inscenizuje REBOOT-hard, honoruje `cancel` | postęp w `journal.json` |
| `resume` | wznawia oczekującą transakcję od jej bieżącej fazy, idempotentny, nigdy nie podmienia `.so` | zaktualizowany `journal.json` |
| `boot` | tryb pre-zygote, `resume` plus podmiana zainscenizowanego `.so`, zamyka `PENDING_REBOOT` w `DONE` | zaktualizowany `journal.json` |
| `status` | migawka tylko do odczytu, nic nie zmienia | `journal.json`, lub `{"state":"idle"}` gdy żadna transakcja nie jest aktywna |
| `cancel` | prosi o zatrzymanie, trwający `run` zatrzymuje się w następnym bezpiecznym punkcie | tworzy `$VDLU_DIR/cancel` |

Bezgłowa aktualizacja to `check`, by zobaczyć, czy coś oczekuje, `run`, by zastosować wszystko, co może pójść na żywo, potem `boot` przy następnym rozruchu, by podmienić każdy zainscenizowany `.so` (lub `resume`, by ponowić odroczone pobranie). Każdy czasownik można bezpiecznie wywołać ponownie, awaria lub zerwanie sieci w połowie cyklu zostawia wznawialny dziennik, nigdy modułu zastosowanego w połowie.

## JSON statusu

`status` (oraz żywy plik w `$VDLU_DIR/journal.json`) to kontrakt postępu, który WebUI i agent oboje czytają:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` porusza się w ustalonej kolejności: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` osiąga się dopiero po tym, jak re-hash wszystkiego się zgadza. Zainscenizowany plik REBOOT-hard daje `PENDING_REBOOT`, nigdy fałszywego `DONE`, uruchom `boot`, by go dokończyć.
- `DEFERRED` oznacza, że `net_policy` zablokowało pobranie, stan łagodny i wznawialny, a nie błąd, plan trwa, a następny `check`/`boot` kontynuuje.
- `ERROR` niesie powód w `error`, zastosowane pliki LIVE są cofane z `rollback/`, moduł nigdy nie zostaje zastosowany w połowie.
- `cancelled:true` z `error:null` to czyste zatrzymanie, dziennik pozostaje wznawialny.

## Kontrakt szwu

Każdy komponent (silnik, producent, WebUI) jest zgodny z [`INTERFACES.md`](INTERFACES.md), prawem konwergencji. Czasowniki CLI, schemat `manifest.json`, klucze `journal.json` i zdefiniowane tam klucze config są **niezmienne**, traktuj ten plik jako jedyne źródło prawdy i dostosuj się do niego, zanim zmienisz którykolwiek z nich. Po wewnętrzności silnika (wznawialna transakcja, gwarancje rygoru, wykluczenie trust-anchor) zobacz [`ENGINE.md`](ENGINE.md), po stronę kanału (budowanie i podpisywanie kanału adresowanego treścią) zobacz [`PRODUCER.md`](PRODUCER.md).

## Zasady dla agenta

- Używaj czasowników i JSON-a, nigdy nie zeskrobuj WebUI i nigdy nie edytuj plików stanu ręcznie.
- Traktuj `INTERFACES.md` jako niezmienny, zmiana oznacza najpierw wyrównanie kontraktu.
- Łatka od agenta AI przechodzi tę samą poprzeczkę recenzji co każda inna, build zawsze release, niczego nie rozluźniaj, niczego nie trać.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane, zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
