> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · Polski · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Flashless, inkrementalny klient aktualizacji dla modułów KSU/Magisk. Implementuje cykl
`DIFF -> FETCH -> APPLY -> COMMIT` jako wznawialną transakcję. Zgodny z `INTERFACES.md` (prawo
zbieżności).

Czysty POSIX sh (mksh/busybox/toybox). **SLIM:** zależy tylko od toybox (`sha256sum`/`gzip`/`base64`/`date`) +
wbudowanego `ed25519-mini` (verify ed25519, **bez openssl na urządzeniu**) + statycznego `curl` **pobieranego** przy
pierwszej aktualizacji https (WebUI robi `fetch()`, utrwala go w Tier-2, a `install-tool` weryfikuje jego
podpis+hash PRZED użyciem). `file://` nie potrzebuje curl. Zerowa zależność od `jq`.

## Wywołanie

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = błąd (powód na stderr). `vdlu-verify` jest dostarczany przez inny komponent
(podpis w `INTERFACES.md §6`), engine tylko go wywołuje.

| cmd | robi |
|---|---|
| `check` | DIFF tylko-do-odczytu; wypisuje `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nie zmienia |
| `run` | pełny cykl LIVE + inscenizuje REBOOT-hard; honoruje `cancel`; postęp w `journal.json` |
| `resume` | wznawia oczekującą transakcję (`target.json`) od bieżącej fazy; idempotentnie; **nie** robi swap `.so` |
| `boot` | tryb pre-zygote: resume **+** robi swap plików `staged/*.vdlu-new` → zamyka `PENDING_REBOOT`→`DONE`. Bez oczekującej transakcji uruchamia świeży cykl i stosuje wszystko (włącznie z `.so`) w jednym rozruchu |
| `status` | wypisuje `journal.json` (lub `{"state":"idle"}`) |
| `cancel` | tworzy `$VDLU_DIR/cancel`; trwający `run` zatrzymuje się w następnym bezpiecznym punkcie |

## Maszyna stanów (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` dopiero gdy ponowny hash WSZYSTKIEGO się zgadza. Jeśli jakikolwiek REBOOT-hard został zainscenizowany ⇒
`PENDING_REBOOT` (nigdy fałszywe `DONE`). `ERROR` przy każdej awarii, bez uszkodzenia modułu (zastosowane pliki
LIVE są cofane z `rollback/<v>/`, nic "w połowie zastosowane, kłamiące o tym"). Łagodne wyjście z fazy
`fetch`: **`DEFERRED`** - pobieranie zostało odroczone przez `net_policy` (sieć niedozwolona), plan/target
trwają i wznawia się przy następnym check/boot (WebUI pokazuje niebieski info-toast "oczekiwanie na sieć X", nie błąd).

## Gwarancje rygoru

- **FETCH:** bramkowany przez `net_policy` (any/wifi/mobile, tylko http/https, `file://` nigdy) - niedozwolona sieć ⇒
  `DEFERRED` (wznawialne), bez wydawania danych. Pobiera tylko brakujące do `<sha>.part` (curl z
  `--connect-timeout` + `--speed-time`, nigdy się nie zawiesza), rozpakowuje `gz` (toybox `gunzip`), sprawdza `sha256sum` ==
  manifest, atomowy `mv` do `blobs/<sha>`. Blob z cache+ok jest pomijany. Może zasiać bloba z niezmienionego
  pliku lokalnego (dedup/offline). **3 awarie na tym samym blobie = faza przerywa się bez stosowania czegokolwiek.** Staje
  się `FETCHED` tylko gdy WSZYSTKIE bloby planu są obecne+zweryfikowane. Przy konfiguracji
  toolchainu loguje rozwiązane zaufanie TLS (ścieżka CA + czytelność, rozmiar bundla i liczba
  certyfikatów), więc bootowy curl `rc 77` sam się tłumaczy w `boot.log` - odróżnia pusty
  magazyn od nieczytelnego (przypadek kontekstu SELinux przy boot).
- **APPLY** (tylko z `FETCHED`): `live`/`soft` → kopia zapasowa do `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  atomowy `rename`. `reboot` → materializuje do `staged/<path>.vdlu-new` (NIE dotyka żywego inode).
  `delete[]` → kopia zapasowa → usunięcie. Idempotentnie (plik już na hashu docelowym jest pomijany).
- **COMMIT:** ponowny hash każdego `live`/`soft`, dopiero wtedy zapisuje `current.json`. Z zainscenizowanymi plikami ⇒
  `PENDING_REBOOT`. `boot` robi `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + re-weryfikuje +
  `DONE`.
- **cancel:** sprawdzany między plikami (bezpieczny punkt), usuwa `.vdlu-tmp`/`.part` w locie, usuwa `cancel`,
  pozostawia journal wznawialny (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializuje (flock niewykonalny na toybox, odzysk przestarzałego po PID).
  CIERPLIWY boot-retry nie trzyma locka podczas oczekiwania (`acquire_lock_try`+release między próbami) ani
  wakelocka - bezpieczny dla baterii. Crash/sieć/reboot w środku → `resume`/`boot` kontynuuje.
- **profile=hardened** ⇒ `vdlu-verify` obowiązkowy na manifeście PRZED użyciem, awaria = przerwanie, downgrade zablokowany
  (wersja monotoniczna). **trusted** ⇒ verify jest best-effort, ale hash każdego bloba jest ZAWSZE sprawdzany.
- **Allowlist klucza module-update (oba profiles):** `verify_manifest` odrzuca, fail-closed, każdy manifest, którego `key_id` nie ma w skonfigurowanej allowliście `key_id` (zob. INTERFACES §5/§6), ZANIM zostanie wybrany pubkey, więc klucz niższego zaufania, który jedynie leży w keyringu (np. klucz fingerprint-feedu), nigdy nie może podpisać flashless aktualizacji root. Domyślnie bezpieczne, gdy nieustawione: keyring z jednym kluczem = tylko ten jeden klucz, keyring wielokluczowy = odrzucony, dopóki `key_id` nie zostanie przypięte.
- **Wykluczenie kotwicy zaufania (VDLU#2):** engine IGNORUJE każdą ścieżkę `vdlu/` w pobranym planie (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) - nigdy nie pobierana, stosowana ani usuwana - nawet jeśli podpisany feed je niesie. Feed nigdy nie może podmienić weryfikatora na urządzeniu ani klucza podpisującego, kotwica zaufania zmienia się tylko przez pełny podpisany re-flash, więc pojedynczy wyciekły klucz podpisujący nie może utrwalić roota po kablu.
- **Odroczenie przy zajętości (opcjonalne `apply_busy_file`):** z ustawionym `apply_busy_file` (bezwzględna ścieżka, którą moduł-host dotyka podczas własnych operacji, np. trwającego backupu), APPLY jest odraczane, dopóki ta ścieżka istnieje - aktualizacja nigdy nie podmienia plików modułu w trakcie operacji. Bloby są już pobrane, więc następny trigger stosuje bez ponownego pobierania.
- **Pułapy rozmiaru:** 128 MiB na plik (`MAX_FILE_BYTES`) i 2 MiB na manifest (`MAX_MANIFEST_BYTES`), egzekwowane przed odczytem zarówno w `update.sh`, jak i `vdlu-verify` (anty bomba-dekompresyjna / anty-OOM).
- Degraduje z gracją: brakujący binary / sieć padła / dysk pełny → jasny błąd na stderr + `state:ERROR` w
  journal, bez uszkodzenia modułu.

## Parsowanie JSON bez jq

Flattener w stylu gron w `awk` (czysty POSIX: `substr`/`index`/`gsub`/`split`/`printf` + lokalne przekazywane jako
parametry) tokenizuje manifest znak po znaku i emituje jeden wiersz `path<TAB>value` na skalarny liść
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Odporny na kompaktowy LUB
pretty-printed JSON. `sh` konsumuje go przez `grep`/`cut`, plan per plik jest składany ponownie w 2. `awk` do TSV
(`class st mode enc sha size path`), który staje się `$VDLU_DIR/plan.tsv`.

## Pliki stanu (w `$VDLU_DIR`, Tier-2)

| plik | rola |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…; zob. INTERFACES §5) |
| `current.json` | manifest AKTYWNEJ wersji (baza diff); brak = nigdy nie aktualizowano |
| `target.json` | przypięty manifest transakcji w locie (obecność = aktywna transakcja); staje się `current.json` przy `DONE` |
| `plan.tsv` / `plan.del` | plan + postęp per plik (st) / ścieżki do usunięcia |
| `journal.json` | postęp dla WebUI (regenerowany przy każdym przejściu) |
| `blobs/<sha256>` | cache zweryfikowanej treści oryginalnej |
| `rollback/<version>/<path>` | kopia zapasowa nadpisanych plików (undo; trzyma ostatnie 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard oczekujący na swap przy rozruchu |
| `lock.d/` | mkdir-lock (flock niewykonalny na toybox; odzysk przestarzałego po PID) |
| `tools/<abi>/curl` | pobrany statyczny curl (oszczędny bootstrap); trwa między aktualizacjami |
| `cancel` | żądanie anulowania |

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane, zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
