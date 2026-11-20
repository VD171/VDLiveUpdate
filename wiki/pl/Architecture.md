# Architecture

VDLU ma dwie strony połączone jedną rzeczą pośrodku. Na PC [[Producer]] zamienia drzewo modułu w podpisany, adresowany treścią kanał (feed). Na urządzeniu [[Engine]] czyta ten kanał, ustala, co się zmieniło, i to stosuje. Szwem między nimi jest **podpisany manifest wraz z magazynem blobów** ([[Feed Format]]). Nic innego nie przekracza tej granicy.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Obie strony nigdy nie współdzielą środowiska uruchomieniowego. Producer używa `python3` i `openssl`; Engine to czysty POSIX `sh` z toybox i wbudowanym `ed25519-mini`. Zgadzają się tylko dlatego, że obie wyprowadzają **te same kanoniczne bajty** z manifestu (zobacz [[Security and Trust Model]]). WebUI to cienki panel w czystym JS, który steruje silnikiem przez mostek menedżera roota i czyta jego dziennik postępu; nie ma żadnej własnej logiki aktualizacji. Zobacz [[WebUI]].

## Dwie strony

| Strona | Działa na | Zbudowana z | Zadanie |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Przejść drzewo modułu do `manifest.json` + `blobs/`, podpisać je, usunąć sieroty |
| [[Engine]] | urządzenie | POSIX `sh` + toybox + `ed25519-mini` | Porównać zainstalowane drzewo z kanałem, pobrać delty, zastosować, zatwierdzić |
| [[WebUI]] | urządzenie (webview) | czysty JS/CSS | Wyzwalać aktualizacje, pokazywać postęp, edytować konfigurację, pokazywać baner restartu |

## Potok aktualizacji

Każda aktualizacja to jedna transakcja, wykonywana w ustalonej kolejności:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` to ta faza, tylko do odczytu). Silnik pobiera tylko manifest, uruchamia `validate_plan()` na każdym polu **przed** dotknięciem czegokolwiek, a następnie porównuje kanał z `current.json`, aby zbudować plan per-plik. Nie zmienia niczego na dysku. Urządzenie wyprzedzające kanał to łagodny wynik "ahead", a nie błąd.
- **FETCH.** Pobiera tylko bloby, których brakuje w planie, do pliku `<sha>.part`, dekompresuje `gz`, sprawdza `sha256sum` względem manifestu i atomowo wykonuje `mv` każdego zweryfikowanego bloba do pamięci podręcznej. Blob już zbuforowany (lub zaszczepiony z niezmienionego lokalnego pliku) jest pomijany, więc cofnięcie lub współdzielony plik nic nie kosztuje. Trzy niepowodzenia na jednym blobie przerywają fazę bez stosowania czegokolwiek. Pobieranie zablokowane przez politykę sieciową kończy się jako `DEFERRED` (wznawialne), a nie jako błąd.
- **APPLY.** Zwykłe pliki (`live` / `soft`) są zapisywane teraz: kopia zapasowa do `rollback/<v>/`, zapis `.vdlu-tmp`, `chmod`, weryfikacja, a następnie atomowe `rename` nad celem. Pliki klasy reboot są materializowane do `staged/<path>.vdlu-new`, a żywy inode pozostaje nietknięty. Wpis `delete[]` jest najpierw kopiowany, a potem usuwany. Każdy krok jest idempotentny: plik już o docelowym skrócie jest pomijany.
- **COMMIT.** Ponowne obliczenie skrótu każdego żywego pliku; tylko jeśli wszystko się zgadza, silnik awansuje `target.json` do `current.json`. Jeśli cokolwiek zostało zetapowane, transakcja kończy się w `PENDING_REBOOT`; w przeciwnym razie `DONE`.

## Adresowany treścią manifest i bloby

Kanał jest adresowany treścią: manifest wymienia **kompletne** docelowe drzewo, każdy plik niesiony przez swój `sha256`, a magazyn blobów przechowuje jedną kopię każdej odrębnej treści pod `blobs/<sha256>` (lub `blobs/<sha256>.gz`).

- **Deduplikacja.** Identyczna treść gdziekolwiek w drzewie lub między wydaniami to jeden blob. Publikowanie jest przyrostowe: blob, którego `sha256` już istnieje na hoście, nigdy nie jest ponownie wypychany, a urządzenie nigdy nie pobiera ponownie treści, którą już ma.
- **sha256 jest z oryginału.** Skrót zawsze nazywa nieskompresowaną treść; `enc` (`raw` lub `gz`) zapisuje jedynie, jak ten konkretny blob jest przechowywany. Urządzenie dekompresuje `gz` za pomocą `gunzip` z toybox, więc nie jest dołączany żaden dodatkowy kompresor.
- **Stabilność wariantu.** Ponieważ urządzenie porównuje względem tego, co jest faktycznie zainstalowane, kanał może nieść całą rodzinę modułu; każda instalacja pobiera tylko te bloby, które dopełniają jej własny wariant.

Pełny układ pole po polu znajduje się w [[Feed Format]].

## Wznawialny dziennik

Każda transakcja jest odporna na awarie, ponieważ jej postęp znajduje się w dzienniku (`journal.json`), a przypięty cel transakcji w toku znajduje się w `target.json`. Maszyna stanów działa w ustalonej kolejności:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Stan | Znaczenie |
|---|---|
| `PLANNED` | Plan zbudowany, nic jeszcze nie pobrane |
| `FETCHING` / `FETCHED` | Pobieranie blobów / wszystkie bloby obecne i zweryfikowane |
| `APPLYING` / `APPLIED_LIVE` | Zapisywanie plików / wszystkie żywe pliki zapisane |
| `PENDING_REBOOT` | Plik klasy reboot jest zetapowany, czeka na podmianę przy rozruchu |
| `DONE` | Ponowne obliczenie skrótu wszystkiego się zgodziło; `current.json` awansowany |
| `ERROR` | Twarde niepowodzenie; moduł pozostawiony nieuszkodzony, żywe pliki przywrócone z `rollback/` |
| `DEFERRED` | Pobieranie wstrzymane przez politykę sieciową; plan trwa, wznawia się później |

`DONE` jest osiągane **tylko** po tym, jak ponowne obliczenie skrótu wszystkiego się zgadza, więc dziennik nigdy nie twierdzi, że połowicznie zastosowana aktualizacja jest kompletna. Awaria, zerwana sieć lub ponowne uruchomienie w połowie pozostawiają wznawialny dziennik; `update.sh resume` (lub `boot`) podejmuje pracę od bieżącej fazy. Zobacz [[Engine]], aby poznać zestaw poleceń i pliki stanu na urządzeniu.

## Atomowość i wycofywanie

Nic nigdy nie jest nadpisywane w miejscu i nic nie jest tracone:

- **Atomowe zapisy.** Każdy plik ląduje przez plik tymczasowy (`.vdlu-tmp`) i atomowe `rename` / `mv`, więc czytelnik nigdy nie widzi połowicznie zapisanego pliku.
- **Kopia zapasowa przed nadpisaniem.** Poprzednia treść trafia do `rollback/<version>/<path>`, zanim nowy plik zostanie przemianowany nad nią (zachowywanych jest kilka ostatnich wersji). Jeśli zastosowanie się nie powiedzie, żywe pliki są przywracane z kopii zapasowej, zamiast być pozostawione uszkodzone. Nieudana kopia zapasowa **przerywa** zastosowanie, zamiast nadpisać bez siatki bezpieczeństwa.
- **Serializacja.** Blokada oparta na `mkdir` (`lock.d/`, ponieważ `flock` jest niewykonalny na toybox, z odzyskiwaniem przeterminowanych blokad po PID) serializuje równoległe uruchomienia.

## Zasada braku ponownego uruchamiania

Większość plików można podmienić, gdy moduł jest aktywny, więc VDLU stosuje je natychmiast. Tylko trzy klasy wymagają ponownego uruchomienia, ponieważ żywy proces już je zmapował: `.so` (ładowany przez Zygisk), nakładka `/system` i `sepolicy.rule`. Te są **etapowane, nigdy nie zapisywane nad żywym inode** i podmieniane w jednym kroku przed-zygote przy następnym rozruchu. Pełna taksonomia i przebieg rozruchu znajdują się w [[Reboot Handling]].

## Postawa zaufania fail-closed

Kanał jest jedyną rzeczą, która przechodzi z PC na urządzenie, więc silnik traktuje każdy jego bajt jako wrogi. `validate_plan()` działa w fazie DIFF, przed każdym pobraniem, i odrzuca cały manifest przy każdym zniekształconym polu. Weryfikacja podpisu używa wbudowanego `ed25519-mini` (bez `openssl` na urządzeniu), klucz prywatny nigdy nie dotyka urządzenia ani CI, a profil `hardened` jest fail-closed przez inwersję, więc uszkodzona wartość profilu nigdy nie może po cichu zaakceptować niepodpisanego kanału. Pełny model, dwa profile i zagrożenia, na które każdy z nich odpowiada, znajdują się w [[Security and Trust Model]].
