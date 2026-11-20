# FAQ

Krótkie odpowiedzi na pytania, które pojawiają się najczęściej. Każda linkuje do strony z
pełną historią.

## Co oznacza "flashless"? Czy wciąż flashuję za pierwszym razem?

Tak, flashujesz raz. Moduł jest instalowany w normalny sposób (flash zipa w
Twoim menedżerze roota). "Flashless" opisuje każdą aktualizację po tym: VDLU pobiera
tylko te pliki, które się zmieniły, i stosuje je w miejscu, więc nigdy nie flashujesz ponownie
pełnego zipa tylko po to, by dostarczyć kilka zmienionych linii. Zobacz [[Architecture]].

## Czy aktualizacja wymaga ponownego uruchomienia?

Zwykle nie. Większość plików (Twój WebUI, pliki binarne, biblioteki, konfiguracje, `module.prop`)
to klasa **live** i stosują się atomowo bez ponownego uruchomienia. Tylko pliki klasy reboot
(`.so` pod `zygisk/`, nakładka `/system/**`, plik sepolicy `*.rule`) są
**etapowane** i podmieniane przy następnym rozruchu, ponieważ działający proces już
zmapował żywy inode. Gdy tak się dzieje, WebUI pokazuje trwały baner "reboot to
activate". Zobacz [[Reboot Handling]].

## Czy to bezpieczne, jeśli kanał jest MITM'owany lub zatruty?

Tak, na kanale `hardened`. Każde pole manifestu jest traktowane jako wrogie wejście.
Manifest musi nieść ważny podpis ed25519 nad swoją formą kanoniczną, a
`validate_plan()` działa fail-closed **przed każdym pobraniem**: odrzuca cały
manifest przy ścieżce absolutnej lub `..`, `sha256`, które nie ma 64 znaków szesnastkowych,
lub nieprawidłowym trybie, klasie czy kodowaniu. Manifest jest także związany z id Twojego modułu,
więc ważnie podpisany kanał dla innego modułu nie może być podany w jego miejscu.
`sha256` każdego bloba jest weryfikowany po pobraniu niezależnie od profilu. Zobacz
[[Security and Trust Model]].

## Czego potrzebuje na urządzeniu (zależności)?

Bardzo niewiele. Czysty POSIX sh (mksh / busybox / toybox) plus `sha256sum` z toybox,
`gzip`, `base64` i `date`; wbudowany weryfikator `ed25519-mini`; oraz, tylko dla
źródła `https`, statyczny `curl`, który jest pobierany raz i buforowany w Tier-2.
Źródło `file://` nie potrzebuje curla w ogóle. Nie ma **zależności od `jq`**:
silnik parsuje JSON za pomocą spłaszczacza w stylu gron napisanego w `awk`. Zobacz [[Engine]].

## Czy openssl jest wymagany na urządzeniu?

Nie. `openssl` jest używany tylko po stronie PC/wydania (`vdlu-keygen`, `vdlu-sign`).
Na urządzeniu weryfikacja podpisu używa oszczędnego wbudowanego pliku binarnego `ed25519-mini`,
który odczytuje surowy 32-bajtowy klucz publiczny. Zobacz [[Producer]] i
[[Security and Trust Model]].

## Jak zrotować klucz podpisujący?

Wygeneruj nową parę kluczy za pomocą `vdlu-keygen`, dodaj nowy surowy 32-bajtowy klucz publiczny do
keyringa urządzenia obok poprzedniego i zacznij podpisywać nowym
`key_id`. Urządzenie wybiera `<keyring>/<key_id>.pub` po `key_id` manifestu,
więc nie jest potrzebna żadna zmiana silnika. Dostarczanie zarówno bieżącego, jak i poprzedniego klucza publicznego
oznacza, że zrotowany klucz nigdy nie unieruchamia starszych instalacji. Ponieważ rotacja pozostawia w keyringu więcej niż jeden klucz, musisz także przypiąć, który klucz może podpisać aktualizację modułu: ustaw konfigurację `key_id` (rozdzielone przecinkami podczas okna rotacji). Keyring z jednym kluczem przypina automatycznie i nie potrzebuje konfiguracji. Zobacz [[Security and Trust Model]].

## hardened vs trusted - którego używam?

Użyj `hardened` dla każdego publicznego kanału (serwowanego przez `https`, np. GitHub Pages).
Czyni podpis obowiązkowym i blokuje cofnięcia wersji. Użyj `trusted` tylko dla
prywatnego źródła `file://` lub etapowanego przez SSH, które już kontrolujesz, gdzie podpis
jest best-effort (skrót każdego bloba i tak jest sprawdzany). W razie wątpliwości użyj `hardened`:
to fail-closed domyślny, a każda nie-`trusted` wartość jest traktowana jako
`hardened`. Zobacz [[Security and Trust Model]].

## Co, jeśli blob jest zmanipulowany lub manifest jest zniekształcony?

Aktualizacja przerywa i nic nie jest stosowane. Zniekształcony manifest jest odrzucany w całości
przez `validate_plan()` przed każdym pobraniem. Blob, którego `sha256` nie pasuje do
manifestu, jest odrzucany; trzy niepowodzenia na tym samym blobie przerywają fazę fetch z
niczym niezastosowanym. Przy każdym twardym niepowodzeniu dziennik zapisuje `ERROR`, a moduł
jest pozostawiony nienaruszony. Zobacz [[Engine]].

## Czy aktualizacja może usunąć moje pliki lub unieruchomić urządzenie?

Ryzyko jest ograniczone z założenia. Nadpisane i usunięte pliki są najpierw kopiowane
do `rollback/<version>/`, a `apply` przerywa, zamiast nadpisać bez
udanej kopii zapasowej. Usunięcia uruchamiają się dopiero, gdy transakcja osiąga `DONE`, nigdy
gdy restart jest wciąż w toku. Nieudane zastosowanie przywraca żywe pliki, które już
zapisało. Ścieżki są walidowane pod kątem zawierania wewnątrz katalogu modułu przed użyciem,
więc manifest nie może zapisać ani usunąć poza drzewem. Zobacz [[Engine]] i
[[Security and Trust Model]].

## Czy działa na KernelSU ORAZ Magisk ORAZ APatch?

Tak. VDLU to zwykły POSIX sh plus WebUI, wbudowany w moduł, więc działa na
KernelSU, APatch i Magisk jednakowo. Używa mostka WebUI menedżera roota
(`ksu.exec`) do sterowania silnikiem i pollowania postępu. Zobacz [[Architecture]] i
[[WebUI]].

## Jak duży jest ślad na urządzeniu?

Mały. Silnik to skrypty; jedyne pliki binarne to weryfikator per-ABI `ed25519-mini`
(maleńki) oraz, dla źródła `https`, statyczny `curl` (~1MB), który jest
pobierany raz i buforowany. Moduł, który już dołącza własny `curl`, używa go ponownie
i nie dodaje żadnego pobierania w ogóle. Pamięć podręczna blobów Tier-2 trzyma zweryfikowaną treść plus
ostatnie 3 wersje wycofania. Zobacz [[Engine]] i [[Architecture]].
