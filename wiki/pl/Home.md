# VDLiveUpdate (VDLU)

**VDLU to bezflashowy, przyrostowy silnik samoaktualizacji dla modułów KernelSU / APatch / Magisk: zainstalowany moduł aktualizuje swoje własne pliki przez podpisany kanał (feed), pobierając tylko to, co się zmieniło, i stosując większość zmian bez ponownego uruchomienia.**

Zwykła aktualizacja modułu dostarcza cały plik `.zip` ponownie, więc kilka zmienionych linii kosztuje pełne ponowne pobranie, a statyczny manifest aktualizacji może wskazywać tylko na pojedynczy `zipUrl` (jeden wariant dla każdego urządzenia). VDLU obiera inną drogę: porównuje (diff) drzewo, które jest faktycznie zainstalowane, z podpisanym, adresowanym treścią kanałem, pobiera tylko różnice (delty) i zapisuje je w miejscu. Pełna instalacja arm64 pozostaje pełną arm64, instalacja lite pozostaje lite, a moduł nigdy nie jest ponownie flashowany.

VDLU jest przeznaczony do **wbudowania (vendored)** w moduł, umieszczony w `<module>/vdlu/`. Nie jest to osobny moduł.

## Cele

- **Bezflashowa samoaktualizacja.** Aktualizuj zainstalowany moduł w miejscu, bezprzewodowo, bez menedżera roota, bez ponownego flashowania pliku `.zip` i bez utraty zainstalowanego wariantu.
- **Przyrostowość według treści.** Przesyłaj tylko te bloby, których treść się zmieniła. Adresowany treścią kanał (`manifest.json` + `blobs/<sha256>`) oznacza, że niezmienione lub cofnięte pliki nigdy nie są pobierane ponownie.
- **Bez ponownego uruchamiania tam, gdzie to bezpieczne.** Zwykłe pliki stosuj na żywo, natychmiast. Zarezerwuj etapowany (staged) reboot tylko dla tych nielicznych plików, które naprawdę go wymagają (`.so`, nakładka `/system`, `sepolicy.rule`).
- **Oszczędność na urządzeniu.** Czysty POSIX `sh`, bez `jq`, bez `bash`, bez `openssl` na urządzeniu. Weryfikacja opiera się na wbudowanym `ed25519-mini`; jedynym pobieranym plikiem binarnym jest statyczny `curl`, używany tylko dla kanałów `https`.
- **Zamknięcie w razie błędu (fail-closed) i uczciwość.** Każde pole manifestu jest traktowane jako wrogie wejście i walidowane, zanim cokolwiek zostanie pobrane. Nic nigdy nie jest raportowane jako "gotowe", dopóki ponowne obliczenie skrótu tego nie udowodni, i nic nie jest nadpisywane bez wcześniejszej kopii zapasowej.

## Osobliwości

Co odróżnia VDLU od typowego klienta OTA:

- **Bezflashowość i przyrostowość.** Adresowany treścią diff / fetch / apply z deduplikacją: urządzenie oblicza deltę względem podpisanego kanału i pobiera tylko brakujące bloby.
- **Bez ponownego uruchamiania tam, gdzie to możliwe.** Zwykłe pliki stosują się na żywo; tylko pliki `.so`, nakładki `/system` i pliki `sepolicy.rule` są etapowane i podmieniane przy jednym ponownym uruchomieniu. Zobacz [[Reboot Handling]].
- **POSIX `sh` na urządzeniu.** Działa pod toybox / busybox / mksh. Bez `jq` (spłaszczacz `awk` w stylu `gron` parsuje JSON), bez konstrukcji `bash`, bez ciężkiego środowiska uruchomieniowego.
- **Oszczędna weryfikacja.** Wbudowany `ed25519-mini` weryfikuje podpisy. **Na urządzeniu nie ma `openssl`**; klucz prywatny nigdy nie dotyka urządzenia ani CI.
- **Bezpieczeństwo fail-closed.** `validate_plan()` odrzuca **cały** manifest przy każdym błędnym polu (ścieżka absolutna lub `..`, `sha256`, które nie ma 64 znaków szesnastkowych, nieprawidłowy tryb / klasa / kodowanie). Dwa profile, `trusted` i `hardened`, przy czym `hardened` jest fail-closed przez inwersję. Zobacz [[Security and Trust Model]].
- **Wznawialność i atomowość.** Dziennik (journal) czyni każdą transakcję odporną na awarie; zapisy używają `rename` / `mv`; kopia zapasowa jest tworzona przed każdym nadpisaniem, więc nieudane zastosowanie cofa się, zamiast uszkodzić moduł.

## Zacznij tutaj

| Jeśli chcesz... | Przejdź do |
|---|---|
| Wdrożyć VDLU do swojego modułu, krok po kroku | [[Quick Start]] |
| Zrozumieć cały system w skrócie | [[Architecture]] |
| Poznać silnik po stronie urządzenia (`update.sh`) | [[Engine]] |
| Zbudować i podpisać kanał na swoim PC | [[Producer]] |
| Wstawić panel Updates | [[WebUI]] |
| Przeczytać model zaufania i postawę wobec zagrożeń | [[Security and Trust Model]] |
| Zobaczyć układ manifestu i blobów | [[Feed Format]] |
| Wiedzieć, co wymaga restartu i dlaczego | [[Reboot Handling]] |
| Zadać częste pytanie | [[FAQ]] |
| Wnieść wkład | [[Contributing]] |

## Linki projektu

- **Źródło:** https://github.com/VD171/VDLiveUpdate
- **Kanał (aktualizacje):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate to niezależny, nieoficjalny projekt. "Android" jest znakiem towarowym Google LLC; "KernelSU", "Magisk" i "APatch" są znakami ich odpowiednich autorów. VDLU działa w całości na Twoim urządzeniu i Twoim własnym hoście wydawniczym.
