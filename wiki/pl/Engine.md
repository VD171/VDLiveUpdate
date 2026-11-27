# Engine

Silnik to strona VDLU po stronie urządzenia: część, która działa na telefonie, decyduje, co się zmieniło, pobiera to i stosuje. Jest to pojedynczy skrypt powłoki POSIX, `engine/update.sh`, plus maleńki weryfikator podpisu, `engine/vdlu-verify`. Oba są wbudowane (vendored) w moduł hosta w `<module>/vdlu/` i uruchamiane przez roota.

Cały silnik jest zbudowany wokół jednej idei: aktualizacja to **wznawialna transakcja**. Jeśli telefon zostanie ponownie uruchomiony, zabity lub straci sieć w połowie, następne uruchomienie podejmuje pracę dokładnie tam, gdzie się zatrzymało, a moduł nigdy nie jest pozostawiony połowicznie zastosowany, udając, że jest gotowy.

Jeśli najpierw chcesz całościowy obraz, zobacz [[Architecture]]. Aby dowiedzieć się, jak aktualizacje unikają ponownego uruchomienia, kiedy tylko mogą, zobacz [[Reboot Handling]].

## Napisany dla urządzenia, nie dla Twojego laptopa

`update.sh` to czysty POSIX `sh`. Działa pod mksh, busybox lub toybox, bez funkcji wyłącznych dla bash, i przechodzi `sh -n`. To ważne, bo środowisko na zrootowanym urządzeniu z Androidem jest małe i restrykcyjne.

W szczególności nie ma `jq`. VDLU parsuje `manifest.json` za pomocą małego spłaszczacza w stylu gron napisanego w `awk`: przechodzi JSON znak po znaku i emituje jedną linię `path<TAB>value` na liść (na przykład `files/0/sha256<TAB>ab..` lub `version<TAB>6`). Powłoka następnie czyta te linie za pomocą `grep` i `cut`. Działa to zarówno na kompaktowym, jak i ładnie sformatowanym JSON, i nigdy nie wywołuje narzędzia JSON, którego tam nie ma.

Silnik zależy tylko od tego, co toybox już dostarcza (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), od wbudowanego weryfikatora `ed25519-mini` oraz, dla kanałów `https://`, od małego statycznego `curl`, który jest pobierany i weryfikowany jeden raz. Kanał `file://` nie potrzebuje `curl` w ogóle.

## Sześć poleceń

Silnik wywołujesz, podając ścieżki modułu w środowisku i jedno polecenie:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Kod wyjścia `0` oznacza sukces; każdy inny kod oznacza błąd, a przyczyna jest wypisywana na stderr.

| Polecenie | Co robi |
|---|---|
| `check` | Diff tylko do odczytu. Pobiera manifest, porównuje go z tym, co jest zainstalowane, i wypisuje jednoliniowe podsumowanie JSON: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Nie zmienia niczego na dysku. Jeśli urządzenie jest nowsze niż kanał (zablokowane cofnięcie wersji), raportuje `{"update":false,"ahead":true,...}` z kodem wyjścia `0`, a nie błędem. |
| `run` | Pełny cykl na żywo: DIFF, FETCH, APPLY, COMMIT. Stosuje każdy żywy plik natychmiast i etapuje te nieliczne pliki klasy reboot. Honoruje `cancel`. Zapisuje postęp do `journal.json`. |
| `resume` | Kontynuuje transakcję, która została przerwana, zaczynając od tej fazy, w której była. Idempotentne. **Nie** podmienia zetapowanego `.so` (to jest zarezerwowane dla `boot`). |
| `boot` | Ścieżka przed-zygote. Wykonuje `resume`, a następnie podmienia wszelkie zetapowane pliki `*.vdlu-new` na miejsce, zamykając `PENDING_REBOOT` do `DONE`. Jeśli nie ma żadnej oczekującej transakcji, uruchamia świeży cykl i stosuje wszystko, łącznie z `.so`, w tym jednym rozruchu. |
| `status` | Wypisuje `journal.json` lub `{"state":"idle"}`, gdy nic nie jest w toku. |
| `cancel` | Tworzy znacznik `cancel`. Trwający `run` zatrzymuje się czysto w następnym bezpiecznym punkcie. |

Polecenie `check` jest celowo tanie, aby interfejs użytkownika mógł poinformować Cię o istnieniu aktualizacji w każdej sieci. Faktyczne pobieranie jest bramkowane osobno (zobacz fazę fetch poniżej).

## Transakcja, krok po kroku

Każdy `run` przechodzi przez ustaloną maszynę stanów, zapisywaną w `journal.json`, aby WebUI (i Ty) mógł ją obserwować:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Silnik pobiera `manifest.json`, waliduje każde pole (zobacz poniżej i [[Security and Trust Model]]) i porównuje podpisane docelowe drzewo z `current.json`, manifestem już zainstalowanej wersji. Wynikiem jest plan per-plik zapisany do `plan.tsv`: jeden wiersz na plik, niosący jego klasę, docelowy skrót, tryb i stan postępu. Pliki już o docelowym skrócie są oznaczone do pominięcia.

**FETCH.** Dla każdego wciąż potrzebnego pliku silnik pobiera jego adresowany treścią blob z `<source>/blobs/<sha>` (lub `<sha>.gz`, gdy skompresowany), do pliku `.part`. Jeśli blob jest spakowany gzip, jest dekompresowany, a następnie jego SHA-256 jest sprawdzany względem manifestu. Tylko przy zgodności jest atomowo przenoszony (`mv`) do `blobs/<sha>`. Blob już zbuforowany z poprawnym skrótem jest pomijany w całości, a niezmieniony lokalny plik może zaszczepić pamięć podręczną bez żadnego pobierania. Trzy niepowodzenia na tym samym blobie przerywają fazę bez zastosowania czegokolwiek. Faza osiąga `FETCHED` dopiero, gdy każdy blob w planie jest obecny i zweryfikowany. Aby poznać [[Feed Format]], z którego pochodzą te bloby, zobacz tamtą stronę. Przy konfiguracji toolchainu silnik loguje rozwiązane zaufanie TLS - ścieżkę CA i to, czy jest czytelna, plus rozmiar bundla i liczbę certyfikatów - więc bootowy curl `rc 77` sam się tłumaczy w `boot.log` (odróżnia pusty magazyn zaufania od nieczytelnego, przypadek kontekstu SELinux przy boot).

Pobieranie jest bramkowane przez politykę sieciową: kanał może być ograniczony tylko do Wi-Fi, tylko do sieci komórkowej lub do dowolnej sieci. Gdy bieżąca sieć nie jest dozwolona, pobieranie nie zawodzi; wchodzi w łagodny stan `DEFERRED`, utrzymuje plan i cel przypięte, i wznawia się przy następnym check lub rozruchu, gdy pojawi się właściwa sieć. W międzyczasie nie są zużywane żadne dane.

**APPLY.** Wchodzona zawsze tylko z `FETCHED`. Dla każdego pliku silnik działa według klasy:

- pliki `live` i `soft`: kopia zapasowa bieżącego pliku do `rollback/<version>/<path>`, zapis nowej treści do siostrzanego `.vdlu-tmp`, `chmod`, weryfikacja skrótu, a następnie atomowe `rename` nad celem. Plik już o docelowym skrócie jest pomijany.
- pliki `reboot` (`.so`, nakładka `/system`, `sepolicy.rule`): materializacja do `staged/<path>.vdlu-new`. Żywy inode nigdy nie jest tutaj dotykany. Zobacz [[Reboot Handling]].
- usunięcia: kopia zapasowa, a potem usunięcie. Usunięcia są stosowane dopiero na samym końcu, przy czystym `DONE`, nigdy gdy ponowne uruchomienie jest wciąż w toku.

**COMMIT.** Silnik ponownie oblicza skrót każdego dotkniętego pliku live i soft. Tylko gdy wszystkie się zgadzają, zapisuje `current.json`, czyniąc nową wersję bazą diff. Jeśli jakikolwiek plik klasy reboot został zetapowany, stan staje się `PENDING_REBOOT` zamiast `DONE`; podmiana i końcowa reweryfikacja odbywają się później pod poleceniem `boot`.

## Bezpieczny z konstrukcji (fail-safe)

Gwarancje, które czynią to bezpiecznym do uruchamiania bez nadzoru:

- **Nic nie jest oznaczone jako `DONE` bez zgodnego ponownego obliczenia skrótu.** `DONE` jest osiągane dopiero po tym, jak każdy zastosowany plik został odczytany z powrotem, a jego SHA-256 porównany z manifestem. Zetapowany plik reboot wymusza `PENDING_REBOOT`, nigdy fałszywego `DONE`.
- **Nic nie jest tracone.** Każdy plik jest kopiowany do `rollback/<version>/`, zanim zostanie nadpisany, a zachowywane są trzy ostatnie wersje. Jeśli zastosowanie się nie powiedzie, żywe pliki są przywracane z kopii zapasowej; moduł nigdy nie jest pozostawiony połowicznie zastosowany, kłamiąc o tym. `apply_live` przerywa wręcz, jeśli krok kopii zapasowej się nie powiedzie, zamiast nadpisać bez drogi powrotu.
- **Wszystko jest atomowe.** Nowa treść ląduje przez `rename`/`mv` nad celem, więc czytelnik zawsze widzi albo stary plik, albo nowy, nigdy obciętego zapisu.
- **Wznawialny po awarii lub zabiciu.** Awaria, utracona sieć lub ponowne uruchomienie w połowie pozostawiają ważny dziennik; `resume` (lub `boot`) kontynuuje od zapisanej fazy. Projekt zakłada, że zostanie przerwany.
- **Łagodna degradacja.** Brakujący plik binarny, niedostępna sieć lub pełny dysk produkują wyraźny błąd na stderr i `state:ERROR` w dzienniku, bez uszkadzania modułu.
- **Kotwica zaufania jest wykluczona (`ENGINE_VERSION` 5).** Silnik ignoruje każdą ścieżkę `vdlu/` w pobranym planie - własny `update.sh`, `vdlu-verify`, binaria `verify/`, keyring i config - więc feed nigdy nie może podmienić weryfikatora ani klucza podpisującego po kablu; kotwica zmienia się tylko przez pełny podpisany re-flash. Zobacz [[Security and Trust Model]].
- **Aktualizacja odracza się, gdy moduł jest zajęty.** Z opcjonalnym `apply_busy_file` ustawionym na bezwzględną ścieżkę, którą moduł-host dotyka podczas własnych operacji (na przykład trwającego backupu), APPLY czeka, dopóki ta ścieżka istnieje, więc pliki nigdy nie są podmieniane w trakcie operacji; bloby są już pobrane, więc następny trigger stosuje bez ponownego pobierania.
- **Pułapy rozmiaru.** Plik jest ograniczony do **128 MiB**, a manifest do **2 MiB**, egzekwowane przed odczytem któregokolwiek z nich zarówno w `update.sh`, jak i `vdlu-verify` (anty bomba-dekompresyjna / anty-OOM).
- **Moduł wyprzedzający feed nigdy nie jest cofany (`ENGINE_VERSION` 7).** Zainstalowany na żywo `versionCode`, odczytany z własnego `module.prop` modułu, wyznacza dolną granicę wersji "from", więc urządzenie zaktualizowane ręcznie poza nieaktualny feed jest odczytywane jako *wyprzedzające*: strażnik downgrade zwraca wynik łagodny, bez planu i bez cofania. `boot` samoczynnie naprawia też istniejącą instalację - utrwalony plan, którego target jest poniżej zainstalowanej wersji, lub nieaktualny journal z `target <= 0` (`ENGINE_VERSION` 6), jest czyszczony przed każdym resume.

## Blokada

Tylko jedna transakcja może naraz dotykać stanu. `flock` nie jest niezawodny na toybox, więc VDLU serializuje za pomocą blokady katalogowej: `mkdir "$VDLU_DIR/lock.d"` powiedzie się dla dokładnie jednego wywołującego i zawiedzie dla reszty, co jest atomowe na każdym rozsądnym systemie plików. Przeterminowana blokada pozostawiona przez martwy proces jest odzyskiwana przez sprawdzenie zapisanego PID.

Cierpliwe ponawianie przy rozruchu (używane, gdy urządzenie jest offline przy rozruchu) **nie** trzyma tej blokady podczas oczekiwania. Pozyskuje ją i zwalnia między próbami, więc ręczny `run` nigdy nie jest blokowany przez rozruch czekający na sieć, i nigdy nie trzyma wakelock. Bezpieczny dla baterii z założenia. Więcej o tym w [[Reboot Handling]].

## Sprawdzanie podpisu: `vdlu-verify`

`vdlu-verify` to weryfikator podpisu na urządzeniu, celowo utrzymany w oszczędności:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Kod wyjścia `0` oznacza, że podpis manifestu jest ważny względem klucza publicznego z keyringa, którego id pasuje do `key_id` manifestu; każdy inny kod to odrzucenie.

Oszczędnym czyni go to, że używa **żadnego `openssl` na urządzeniu**. Odczytuje klucz publiczny keyringa jako plik **surowych 32 bajtów**, kanonikalizuje manifest (tekst manifestu z usuniętym polem `sig`), haszuje go za pomocą `sha256sum` z toybox, dekoduje podpis z base64 i przekazuje surowy klucz, wiadomość i 64-bajtowy podpis do wbudowanego pliku binarnego `ed25519-mini`. Weryfikator odmawia także wszystkiego zniekształconego, zanim w ogóle zweryfikuje: brakujący lub pusty `key_id` albo `sig`, `key_id` zawierający separatory ścieżki, klucz publiczny, który nie ma dokładnie 32 bajtów, lub podpis, który nie ma dokładnie 64 bajtów.

Zanim w ogóle wybierze klucz, silnik wymusza **listę dozwolonych `key_id`**: `key_id` manifestu musi być jednym z tych, którym konfiguracja pozwala podpisać *aktualizację modułu*, a klucz, który jest jedynie obecny w keyringu, ale nie na liście dozwolonych, jest odrzucany, zanim jego pubkey zostanie w ogóle załadowany. Keyring z jednym kluczem automatycznie przypina ten jeden klucz bez konfiguracji; keyring z wieloma kluczami musi przypiąć `key_id`, inaczej silnik zawodzi w trybie zamkniętym. Dozwolony zestaw jest przekazywany w dół do `vdlu-verify` jako `VDLU_KEYID_ALLOW` i obowiązuje w obu profilach. To powstrzymuje klucz o niższym zaufaniu, taki jak klucz kanału fingerprint współdzielący keyring, przed podpisaniem pełnej aktualizacji roota; oddzielny kanał fingerprint zachowuje własny przypięty klucz, `FEED_KEY_ID`. Pełna historia znajduje się w [[Security and Trust Model]].

Kanonikalizacja jest bajt w bajt identyczna z podpisującym producenta, co właśnie sprawia, że podpis weryfikuje się między narzędziami. Pasujący klucz prywatny nigdy nie dotyka urządzenia ani CI; wbudowany jest tylko surowy klucz publiczny. Pełna historia zaufania, dwa profile i dlaczego `hardened` jest fail-closed przez inwersję, znajdują się w [[Security and Trust Model]].

Silnik wywołuje `vdlu-verify` podczas fazy diff. W profilu `hardened` nieudana weryfikacja przerywa całą aktualizację; w profilu `trusted` weryfikacja jest best-effort, ale skrót każdego bloba i tak jest zawsze sprawdzany, więc uszkodzona treść jest wychwytywana niezależnie od profilu.

## Stan na dysku

Cały stan silnika znajduje się w `$VDLU_DIR` (poza katalogiem modułu), więc samo drzewo modułu zawsze trzyma tylko ukończone pliki:

| Ścieżka | Rola |
|---|---|
| `config` | ustawienia key=value (source, profile, channel, polityka sieciowa, ponawianie przy rozruchu) |
| `current.json` | manifest aktywnej wersji; to jest baza diff. Brak oznacza, że nigdy nie aktualizowano |
| `target.json` | przypięty manifest transakcji w toku. Jego obecność oznacza aktywną transakcję; staje się `current.json` przy `DONE` |
| `plan.tsv` / `plan.del` | plan per-plik i postęp oraz lista ścieżek do usunięcia |
| `journal.json` | postęp dla WebUI, przepisywany przy każdej zmianie stanu |
| `blobs/<sha256>` | pamięć podręczna zweryfikowanej, zdekompresowanej oryginalnej treści |
| `rollback/<version>/<path>` | kopie zapasowe nadpisanych plików; zachowywane są trzy ostatnie wersje |
| `staged/<path>.vdlu-new` | plik klasy reboot czekający na podmianę przy rozruchu |
| `lock.d/` | blokada mkdir |
| `tools/<abi>/curl` | pobrany, zweryfikowany statyczny curl; utrzymuje się między aktualizacjami |
| `cancel` | żądanie anulowania |

## Zobacz także

- [[Reboot Handling]]: jak system klas utrzymuje większość aktualizacji bez ponownego uruchamiania i jak zetapowany `.so` jest podmieniany przed-zygote.
- [[Security and Trust Model]]: dwa profile, walidacja fail-closed i łańcuch ed25519 z surowym kluczem.
- [[Feed Format]]: manifest i adresowane treścią bloby, które silnik konsumuje.
- [[Architecture]]: jak silnik, producent i WebUI do siebie pasują.
