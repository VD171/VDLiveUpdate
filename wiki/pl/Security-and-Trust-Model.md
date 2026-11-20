# Security and Trust Model

VDLU aktualizuje moduł w miejscu, przez sieć, jako root. To dużo mocy wycelowanej w plik, który pochodzi z kanału, więc cały silnik jest zbudowany na jednym założeniu:

> **Każde pole w manifeście to wrogie wejście.**

Kanał może być zatruty u źródła lub podmieniony i zniekształcony w tranzycie przez MITM. Gdy tak się dzieje, manifest wciąż przybywa, wyglądając jak manifest: niesie ścieżki plików, ciągi `sha256`, listę `delete[]`, tryby, klasy i flagę kodowania. VDLU nie traktuje żadnego z nich jako godnego zaufania. Waliduje cały plan, zanim pobierze pojedynczy bajt, i nigdy nie pozwala, aby wartość manifestu dotarła do powłoki.

Ta strona to pełna historia zaufania. Zobacz [[Feed Format]], aby poznać schemat manifestu, który waliduje, oraz [[Engine]], aby zobaczyć, gdzie te kontrole siedzą w transakcji DIFF -> FETCH -> APPLY -> COMMIT.

---

## Idea przewodnia: fail-closed, zanim cokolwiek się stanie

`validate_plan()` działa wewnątrz fazy `check`/diff, **przed** każdym pobraniem i **przed** każdym zastosowaniem. Przechodzi każdy wpis w planowanym drzewie plików i każdy wpis w `delete[]`, a jeśli jakikolwiek pojedynczy wpis jest zniekształcony, **odrzuca cały manifest** i transakcja nigdy się nie zaczyna. Nie ma częściowej akceptacji, nie ma "pomiń zły i zastosuj resztę". Jedno złe pole zatruwa całą partię, celowo.

Manifest jest akceptowany tylko wtedy, gdy **wszystkie** z tych warunków zachodzą dla **każdego** wpisu:

| Pole | Reguła | Dlaczego |
|---|---|---|
| `path` | nieabsolutna, bez komponentu `..`, bez komponentu `.`, bez wiodącego `./`, bez osadzonego `/./`, bez końcowego ukośnika, bez znaku sterującego (tab / nowa linia) | ścieżka musi pozostać wewnątrz `MODULE_DIR`; ścieżka absolutna lub `..` to zapis-gdziekolwiek |
| `sha256` | pasuje dokładnie do `^[0-9a-f]{64}$` | nieszesnastkowy sha w przeciwnym razie zostałby interpolowany do ścieżki powłoki; to jest adres treści, więc musi być czystym skrótem szesnastkowym i niczym więcej |
| `mode` | tylko ósemkowy (`[0-7]`) | ciąg trybu staje się argumentem `chmod` |
| `size` | tylko cyfry i `<=` pułapowi rozmiaru silnika | ogranicza pobieranie i dekompresję |
| `class` | dokładnie `live`, `soft` lub `reboot` | klasa decyduje, czy plik stosuje się na żywo, czy jest etapowany do restartu |
| `enc` | dokładnie `raw` lub `gz` | kodowanie decyduje, czy blob jest rozpakowywany gunzipem |
| wpisy `delete[]` | te same reguły ścieżki co powyżej | wpis `delete[]` napędza usunięcie; niesprawdzone `..` byłoby `rm` poza drzewem |

Ponieważ to działa najpierw, zatruty manifest nigdy nie może zapisać poza modułem, nigdy nie może usunąć poza modułem i nigdy nie może wstrzyknąć nieszesnastkowego tokenu do wiersza poleceń.

### Wartości manifestu nigdy nie dotykają powłoki

Druga połowa reguły: nawet po tym, jak wartość przejdzie walidację, nigdy nie jest interpolowana do `sh` i nigdy nie jest podawana do `awk system()`. Polecenie check zostało celowo przepisane tak, aby nie zawierało żadnego wywołania `system()`. Adresowanie treścią robi resztę pracy: blob jest pobierany przez swój `sha256`, zapisywany do ścieżki pamięci podręcznej nazwanej tym samym `sha256`, a pobrane bajty są ponownie haszowane i porównywane, zanim cokolwiek zostanie zastosowane. Wartość, która nie jest czystym 64-znakowym skrótem szesnastkowym, nigdy nie dociera tak daleko, ponieważ `validate_plan()` już ją odrzucił.

### Druga linia obrony w czasie zastosowania

`validate_plan()` blokuje `..` **leksykalnie**, ale wcześniej istniejące dowiązanie symboliczne już wewnątrz drzewa mogło nadal przekierować zapis. Więc w czasie zastosowania `contained()` rozwiązuje rzeczywistą ścieżkę docelową i potwierdza, że siedzi ona pod bazą modułu, zawodząc zamknięta (fail-closed), gdy nie może jej rozwiązać. Zapisy są atomowe (zapis do nazwy tymczasowej, następnie `rename` nad celem), a każde nadpisanie jest najpierw kopiowane do `rollback/`; nieudana kopia zapasowa przerywa zastosowanie, zamiast nadpisać bez siatki bezpieczeństwa.

---

## Dwa profile

VDLU działa w jednym z dwóch profili zaufania, ustawianym przez `profile=` w konfiguracji.

### `hardened` (publiczny domyślny)

- **Podpis jest obowiązkowy.** Manifest musi nieść ważny podpis ed25519 z klucza w keyringu na urządzeniu, albo transakcja przerywa.
- **Cofnięcie wersji jest zablokowane.** Manifest, którego `version` jest niższa niż zainstalowana wersja, jest odrzucany. Atakujący nie może cofnąć Cię do znanej podatnej kompilacji.
- To profil dla każdego modułu dystrybuowanego publicznie przez `https://`.

### `trusted` (prywatne, źródło etapowane przez SSH)

- Weryfikacja podpisu jest **best-effort**: źródło to prywatny `file://` lub etapowany przez SSH kanał, który kontrolujesz, więc brakujący lub nieweryfikowalny podpis nie przerywa twardo.
- **Ale `sha256` każdego bloba i tak jest zawsze sprawdzany.** `trusted` rozluźnia *kto podpisał manifest*, nigdy *czy bajty pasują do planu*. Integralność treści jest nienegocjowalna w obu profilach.

---

## Fail-closed przez inwersję

To jest subtelna część i to jest część, którą większość systemów robi źle.

`trusted` to **jedyny** ciąg, który włącza rozluźnioną weryfikację. Silnik nie testuje "czy to `hardened`?" Testuje "czy to **nie jest** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Więc **cokolwiek** innego niż dosłowne `trusted` rozwiązuje się do zachowania hardened:

- linia brakuje całkowicie -> hardened
- literówka jak `hardend` -> hardened
- `trusted ` z końcową spacją lub `\r` z CRLF -> hardened
- `Trusted` ze złą wielkością liter -> hardened
- wartość zniekształcona przez MITM -> hardened

Wcześniejsza wersja domyślnie ustawiała *brakującą* linię na hardened, co wciąż pozostawiało uszkodzoną *wartość* wpadającą do otwartej ścieżki. To był fail-open: zniekształcony ciąg profilu mógł po cichu zaakceptować niepodpisany manifest, a niepodpisany manifest oznacza dostarczony przez atakującego `.so` podmieniony pod MITM, co jest zdalnym wykonaniem kodu na poziomie roota. Inwersja to zamyka. Jedynym sposobem na uzyskanie rozluźnionej weryfikacji jest przeliterowanie `trusted` dokładnie, a nawet wtedy skróty blobów są sprawdzane. Silnik nigdy nie jest o jedną literówkę od zaakceptowania niepodpisanego kodu. (`tr -d` usuwa błądzące białe znaki, aby legalne `trusted` z niechlujnym odstępem nie było błędnie odrzucone, bez ponownego otwierania dziury.)

**Ten test jest nośny. Musi pozostać `!= trusted` i nigdy nie stać się `== hardened`.**

---

## Manifest jest związany z modułem

Pojedynczy klucz wydania podpisuje wiele modułów. Więc manifest, który jest ważnie podpisany, dla *innego* modułu, mógłby w zasadzie zostać podany temu (zła konfiguracja kanału, podmiana źródła lub przekierowanie MITM) i jego podpis by się sprawdził.

VDLU zamyka to wiązaniem: podpisane pole `module` wewnątrz manifestu musi równać się `MODID` tej instalacji, albo manifest jest odrzucany jako kanał międzymodułowy. Ponieważ `module` jest wewnątrz podpisanej formy kanonicznej, atakujący nie może go zmienić bez złamania podpisu. Ważnie podpisany kanał dla modułu B po prostu nie może być zastosowany do modułu A.

---

## Oszczędny weryfikator na urządzeniu

Weryfikacja na urządzeniu używa **ed25519-mini**, maleńkiego weryfikatora tylko-do-weryfikacji zbudowanego na TweetNaCl (domena publiczna). **Na urządzeniu nie ma `openssl`.**

- Wpis keyringa to **surowy 32-bajtowy klucz publiczny**, przechowywany jako `keyring/<key_id>.pub`. (Klucz publiczny PEM jest artefaktem tylko po stronie PC; skopiowanie PEM do keyringa na urządzeniu łamie weryfikację, ponieważ weryfikator oczekuje dokładnie 32 surowych bajtów.)
- `vdlu-verify <manifest.json> <keyring_dir>` rekonstruuje formę kanoniczną (tekst manifestu z usuniętym polem `sig`, kompaktowy, posortowane klucze), haszuje ją do 64-znakowej szesnastkowej wiadomości, którą obejmuje podpis, dekoduje podpis base64, sprawdza, że ma 64 bajty, i pyta `ed25519-mini <pub32> <msg> <sig64>` o werdykt. rc 0 = ważny, cokolwiek innego = odrzucenie.
- Plik binarny jest statyczny per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), z `PROVENANCE.json` przypinającym dokładne źródła TweetNaCl, skrót wrappera i flagi budowania, więc rzecz działająca jako root jest audytowalna.
- `key_id` z manifestu jest sam sanityzowany (bez `/`, bez `..`, bez cudzysłowu), zanim zostanie użyty do wyboru pliku keyringa, więc nie może uciec z katalogu keyringa.

### Keyring jest tylko-z-flasha, weryfikuj-nie-kopiuj, stabilny

Keyring dostarczany jest wewnątrz modułu w czasie flashowania i nie jest przepisywany przez silnik aktualizacji. Przy ponownym wbudowaniu reguła brzmi **weryfikuj, nie kopiuj**: keyring zmienia się tylko przy celowej rotacji klucza, nigdy jako efekt uboczny aktualizacji.

### Rotacja klucza nie unieruchamia starszych instalacji

Gdy klucz podpisujący jest rotowany, keyring dostarcza **zarówno bieżący, jak i poprzedni surowy klucz publiczny**. Weryfikator wybiera plik klucza po `key_id` manifestu, więc kanał wciąż podpisany starym kluczem weryfikuje się względem starego pubkey, a kanał podpisany nowym kluczem weryfikuje się względem nowego. Urządzenie, które nie zaktualizowało się poza rotację, działa dalej; nic nie jest porzucone.

---

## Co zamyka manifest narzędzi

Oszczędny bootstrap pobierania pobiera statyczny `curl` przy pierwszym użyciu dla modułów, które nie dostarczają własnego. Ponieważ ten plik binarny działa jako root, jego własny podpis manifestu (ed25519-mini) i jego skrót są **obowiązkowe w każdym profilu**, łącznie z `trusted`, zanim kiedykolwiek zostanie zainstalowany lub wykonany. Webview jest tylko transportem; zaufanie pochodzi z podpisu i kontroli skrótu na urządzeniu, nigdy z faktu, że pobieranie się powiodło.

---

## Czego atakujący NIE MOŻE zrobić

Nawet posiadając kanał lub siedząc na łączu jako pełny MITM, atakujący nie może:

- **Zapisać poza modułem.** Ścieżki absolutne, `..`, `.`, znaki sterujące i końcowe ukośniki są odrzucane przed każdym zastosowaniem, a przekierowanie dowiązaniem symbolicznym jest wychwytywane ponownie w czasie zastosowania.
- **Usunąć poza modułem.** Wpisy `delete[]` przechodzą tę samą walidację ścieżki.
- **Wstrzyknąć polecenie.** Żadna wartość manifestu nie jest interpolowana do powłoki ani `awk system()`; `sha256` musi być czystym 64-znakowym szesnastkowym, albo cały manifest jest odrzucany.
- **Dostarczyć niepodpisany kod do publicznej instalacji.** `hardened` czyni podpis obowiązkowym, a profil jest fail-closed przez inwersję, więc żadna literówka ani zniekształcona wartość tego nie obniży.
- **Podać tutaj podpisany kanał innego modułu.** Podpisane pole `module` musi równać się temu `MODID`.
- **Cofnąć Cię.** Cofnięcie wersji jest zablokowane w `hardened`.
- **Uszkodzić blob niewykryty.** Każdy pobrany blob jest ponownie haszowany względem `sha256` manifestu w obu profilach; niezgodność po trzech próbach przerywa fazę bez zastosowania czegokolwiek.
- **Podmienić fałszywy pobieracz roota.** Zbootstrapowany `curl` jest sprawdzany pod kątem podpisu i skrótu, zanim zostanie zainstalowany lub uruchomiony, w każdym profilu.
- **Połowicznie zastosować uszkodzoną aktualizację.** Transakcja osiąga `DONE` tylko wtedy, gdy ponowne obliczenie skrótu wszystkiego się zgadza; nieudane zastosowanie cofa się, zamiast nadpisać bez kopii zapasowej.

---

Zobacz także: [[Feed Format]] dla schematu manifestu, [[Engine]] dla transakcji, w której te kontrole żyją, oraz [[Architecture]] dla całościowego obrazu.
