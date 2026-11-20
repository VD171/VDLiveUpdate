# Producer

**Producent** to strona VDLU po stronie PC / wydania: niewielki zestaw narzędzi, które zamieniają gotowe drzewo modułu w podpisany, adresowany treścią kanał, z którego urządzenie może się aktualizować. Nic tutaj nie działa na telefonie. Te narzędzia działają na Twojej maszynie wydawniczej (lub, dla części, które są do tego bezpieczne, w CI).

Jest ich cztery:

| Narzędzie | Działa na | Język | Zadanie |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Przejść drzewo modułu do `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Wygenerować parę kluczy podpisujących ed25519 |
| `vdlu-sign` | PC | sh + openssl | Wstrzyknąć `key_id` + podpis do manifestu, w miejscu |
| `vdlu-gc` | PC | python3 | Usunąć osierocone bloby z opublikowanego kanału (fail-safe) |

Przepływ wydania to trzy kroki, wykonywane raz na wydanie: **pack, następnie sign, następnie publish**. `vdlu-keygen` to jednorazowa konfiguracja, a `vdlu-gc` to porządki, które uruchamiasz, gdy kanał rośnie. Wszystko, co producent emituje, jest zgodne z [[Feed Format]], który jest tym, co silnik na urządzeniu konsumuje.

---

## vdlu-pack

`vdlu-pack` bierze **dokładne drzewo, które dostarcza Twój `.zip`** (drzewo końcowe, po tym jak Twój build zastosował własną listę dozwolonych i przycięcie ABI) i produkuje dla niego kanał.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Zapisuje dwie rzeczy do `<out_dir>`:

- `manifest.json` - kompletny opis docelowego drzewa (każdy plik z jego `sha256`, `size`, `mode`, kodowaniem i klasą reboot), wciąż **niepodpisany** (pola `key_id` i `sig` są pustymi placeholderami).
- `blobs/<sha256>` (lub `blobs/<sha256>.gz`) - jeden blob na odrębną treść pliku.

### Adresowanie treścią i deduplikacja

Każdy blob jest nazwany przez **sha256 swojej oryginalnej (nieskompresowanej) treści**. Ponieważ nazwa jest skrótem, identyczna treść ląduje na tym samym blobie. `vdlu-pack` zapisuje blob tylko wtedy, gdy nie jest już obecny, więc:

- Plik, który się nie zmienił, zachowuje tę samą nazwę bloba i nigdy nie jest ponownie zapisywany ani wypychany.
- Dwa różne pliki o identycznej treści dzielą jeden blob.
- Cofnięty plik ponownie używa bloba, który był tam już wcześniej.

Publikowanie jest zatem **przyrostowe z konstrukcji**: między wydaniami `blobs/` tylko rośnie, i dodawana jest tylko naprawdę nowa treść. Urządzenie pobiera według tych samych skrótów, więc pobiera tylko te bloby, których jeszcze nie ma.

### Kompresja (pole `enc`)

Dla każdego pliku `vdlu-pack` decyduje, jak przechować blob:

- `gz`, gdy plik ma co najmniej 4096 bajtów **oraz** gzip (deterministyczne `-9 -n`) oszczędza co najmniej 10 procent.
- `raw` w przeciwnym razie (małe pliki, które gzip na łączu i tak już pokrywa, lub już nieskompresowalne dane).
- Jeśli `gzip` brakuje na hoście budowania, wszystko jest przechowywane jako `raw`. Pakowanie nigdy nie zawodzi z tego powodu.

`sha256` w manifeście jest **zawsze** z oryginalnej treści; `enc` jedynie nazywa, jak blob akurat jest przechowywany. Urządzenie dekompresuje bloby `gz` za pomocą `gunzip` z toybox, a następnie sprawdza skrót względem oryginału.

### Klasa reboot i bezpieczeństwo

`vdlu-pack` taguje także każdy plik klasą reboot `class` (`live`, `soft`, `reboot`) wyprowadzoną z jego ścieżki, aby silnik wiedział, co można zastosować bez ponownego uruchomienia, a co trzeba zetapować. Reguły i to, co urządzenie robi z każdą klasą, są omówione w [[Reboot Handling]].

Kilka rzeczy, których `vdlu-pack` celowo **nie** robi:

- Nie podąża za dowiązaniami symbolicznymi (pomija je z ostrzeżeniem, więc treść spoza drzewa, jak dowiązanie do pliku systemowego, nigdy nie może przeciec do bloba).
- Pomija pliki nieregularne (katalogi, fifo, urządzenia).
- Honoruje `SOURCE_DATE_EPOCH` dla znacznika czasu `built`, więc manifesty są reprodukowalne.
- Wyklucza z kanału całkowicie ustalony zestaw ścieżek (korzeń zaufania, rusztowanie instalatora i kilka innych). Pełna lista i powód wykluczenia każdej z nich znajdują się w [[Feed Format]].

### Lista `delete[]`

Przekaż `--prev <previous manifest.json>`, a `vdlu-pack` obliczy `delete[]`: ścieżki, które istniały w poprzednim wydaniu, ale zniknęły w tym, aby urządzenie je usunęło, zamiast pozostawiać sieroty. Wykluczone ścieżki nigdy nie są emitowane jako usunięcia, nawet gdy pojawiają się w poprzednim manifeście (zobacz [[Feed Format]], aby poznać dokładną semantykę).

---

## vdlu-keygen

Krok jednorazowy. `vdlu-keygen` tworzy parę kluczy podpisujących ed25519 dla Twojego kanału.

```sh
vdlu-keygen <id> <out_dir>
```

Zapisuje trzy pliki:

| Plik | Co to jest | Dokąd trafia |
|---|---|---|
| `<id>.pem` | **Prywatny** klucz podpisujący (tryb `0600`) | Pozostaje na Twojej maszynie wydawniczej. Nigdy. |
| `<id>.pub` | Klucz publiczny jako PEM | Tylko narzędzia po stronie PC |
| `<id>.pub.raw` | Klucz publiczny jako **surowe 32 bajty** | Dostarczany jako wpis keyringa modułu na urządzeniu |

Surowy 32-bajtowy klucz publiczny jest tym, co odczytuje weryfikator na urządzeniu (nie niesie `openssl`, więc nie może odczytać PEM). Osadzasz `<id>.pub.raw` w module jako `vdlu/keyring/<id>.pub`. PEM jest tylko do użytku po stronie PC. Ten podział i to, jak działa rotacja kluczy, są wyjaśnione w [[Security and Trust Model]].

> **Keyring z wieloma kluczami musi przypiąć `key_id`.** Jeśli keyring modułu dostarcza więcej niż jeden klucz (na przykład klucz wydania plus klucz kanału fingerprint o niższym zaufaniu), silnik nie będzie zgadywać, który może podpisać aktualizację modułu. Ustaw konfigurację `key_id` na klucz, lub rozdzielone przecinkami klucze podczas okna rotacji, który może podpisywać aktualizacje; keyring z jednym kluczem przypina automatycznie i nie potrzebuje konfiguracji. To jest lista dozwolonych aktualizacji modułu, omówiona w [[Security and Trust Model]].

> Prywatny `.pem` to jedyny sekret w całym systemie. Trzymaj go z dala od każdego urządzenia i poza każdym pushem do repozytorium. Zobacz uwagę o CI poniżej.

---

## vdlu-sign

`vdlu-sign` bierze niepodpisany manifest, który wyprodukował `vdlu-pack`, i podpisuje go **w miejscu**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Ustawia pole `key_id`, oblicza kanoniczną formę manifestu i zapisuje podpis ed25519 (base64) do pola `sig`. Podpis obejmuje precyzyjną transformację bajtową manifestu, tak by PC i urządzenie wyprowadzały dokładnie te same podpisane bajty bez żadnej biblioteki JSON na urządzeniu. Ta transformacja (**kanonikalizacja**) jest pojedynczym najważniejszym niezmiennikiem w formacie i jest w pełni udokumentowana w [[Feed Format]].

Klucz prywatny jest odczytywany tylko tutaj, na Twojej maszynie, i nigdy jej nie opuszcza.

### Klucz podpisujący pozostaje poza CI

To celowy punkt projektowy. CI może uruchomić `vdlu-pack` i wyprodukować doskonale ważną **bazową linię bez klucza** (niepodpisany manifest zalążkowy; zobacz [[Feed Format]]), więc świeża instalacja rodzi się aktualna, a CI nigdy nie dotyka klucza prywatnego. Faktyczne podpisywanie opublikowanego kanału wykonujesz Ty, lokalnie, za pomocą `vdlu-sign`. W ten sposób klucz podpisujący jest w 100 procentach poza CI, a podpisany jest tylko kanał, który publikujesz ręcznie.

---

## vdlu-gc

Ponieważ bloby są adresowane treścią i niezmienne, `blobs/` tylko rośnie: `vdlu-pack` dodaje, nigdy nie usuwa. Przez wiele wydań kanał (i strona Pages hostująca go) akumuluje bloby, do których żaden bieżący manifest już się nie odwołuje. `vdlu-gc` usuwa te sieroty.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Buduje **zbiór zachowany** manifestów: bieżący `manifest.json`, plus ostatnie `N` zarchiwizowanych manifestów według wersji (domyślnie `N=3`, dając margines wycofania), plus wszystkie, które nazwiesz za pomocą `--keep`. Blob, do którego odwołuje się **żaden** zachowany manifest, jest sierotą i jest kandydatem do usunięcia. Zbiór zachowany to suma, więc blob pozostaje tak długo, jak dowolne zachowane wydanie wciąż go potrzebuje; urządzenie siedzące na starszej zachowanej wersji nigdy nie traci swojego pobierania.

`vdlu-gc` jest zbudowany tak, aby być bezpiecznym:

- **Dry-run domyślnie.** Bez `--apply` tylko wypisuje, co *by* usunął. Dodajesz `--apply`, aby faktycznie usunąć.
- **Fail-safe.** Jeśli nie znajdzie żadnego zachowanego manifestu w ogóle, odmawia usuwania, zamiast ryzykować opróżnienie kanału.
- **Zachowywanie przez odwołanie, nie przez datę.** Blob jest zachowywany, ponieważ zachowany manifest na niego wskazuje, nigdy z powodu znacznika czasu.

Po usunięciu wypchnij mniejszy kanał na swojego hosta. Rozłóż zapis w czasie, jeśli Twój host ogranicza tempo zapisów wsadowych.

---

## Składając to razem

Typowe wydanie, od początku do końca:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Aby zobaczyć pełny przepracowany przykład wdrożenia VDLU do modułu, zobacz [[Quick Start]]. Aby poznać kształt na łączu wszystkiego, co producent emituje, zobacz [[Feed Format]]. Aby poznać uzasadnienie obsługi kluczy i tego, co jest trzymane poza kanałem, zobacz [[Security and Trust Model]].
