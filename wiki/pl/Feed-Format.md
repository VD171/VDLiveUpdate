# Feed Format

**Kanał (feed)** to to, co VDLU serwuje przez sieć i z czego aktualizuje się urządzenie. To zwykły statyczny katalog, serwowalny przez cokolwiek (GitHub Pages, cel rsync, ścieżka `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Sam moduł dostarcza także jeden dodatkowy plik, `baseline.json`, wewnątrz `.zip` (nie serwowany z kanału). Producent, który buduje to wszystko, jest opisany w [[Producer]]; ta strona to kontrakt na łączu.

---

## manifest.json

Manifest to kompletny opis jednego wydania: każdy plik w docelowym drzewie, co usunąć, i podpis obejmujący całość.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Pola

| Pole | Znaczenie |
|---|---|
| `schema` | Wersja formatu samego manifestu (obecnie `1`). |
| `module` | Id modułu. Urządzenie odrzuca manifest, jeśli nie pasuje do jego własnego id modułu, więc ważnie podpisany kanał dla innego modułu nie może być podany w jego miejscu. |
| `version` | Całkowita wersja. Silnik aktualizuje tylko do przodu; kanał starszy niż urządzenie to łagodny stan "ahead", a nie błąd. |
| `version_name` | Czytelny dla człowieka ciąg wersji (na przykład `v106`). |
| `built` | Znacznik czasu budowania ISO 8601. Honoruje `SOURCE_DATE_EPOCH` dla reprodukowalności. |
| `engine_min` | Minimalna wersja silnika wymagana do zastosowania tego manifestu. |
| `channel` | Kanał wydania (na przykład `stable`). |
| `key_id` | Który klucz w keyringu urządzenia podpisał ten manifest. Wybiera klucz publiczny do weryfikacji i musi znajdować się na liście dozwolonych aktualizacji modułu silnika (zobacz [[Security and Trust Model]]); klucz jedynie obecny w keyringu, ale nie na liście dozwolonych, jest odrzucany, zanim jego pubkey zostanie załadowany. |
| `files[]` | **Kompletne** docelowe drzewo (nie diff). Każdy wpis: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Ścieżki obecne w poprzednim wydaniu, ale już nieobecne teraz, do usunięcia przez urządzenie. |
| `sig` | Podpis ed25519, base64. Zobacz kanonikalizację poniżej. |

`files[]` opisuje **całe** drzewo, a nie deltę. Urządzenie samo oblicza deltę, porównując manifest z tym, co już ma, i pobiera tylko te bloby, których `sha256` mu brakuje. `sha256` jest zawsze z oryginalnej (nieskompresowanej) treści; `enc` jedynie mówi, jak ten blob jest przechowywany w `blobs/`. Znaczenie `class` i to, co urządzenie robi z każdą wartością, jest omówione w [[Reboot Handling]].

---

## Kanonikalizacja (podpisane bajty)

To jest pojedynczy najważniejszy niezmiennik w formacie. Podpisujący na PC i weryfikator na urządzeniu działają na całkowicie różnych środowiskach uruchomieniowych (openssl na PC, toybox + maleńki wbudowany weryfikator na urządzeniu, i **żadnej biblioteki JSON w ogóle** na urządzeniu). Muszą mimo to wyprowadzić dokładnie te same bajty do podpisania i do weryfikacji. Reguła jest zatem celowa **transformacja bajtowa**, a nie ponowna serializacja JSON.

**Krok 1: ustalona forma przechowywania.** `vdlu-pack` zapisuje `manifest.json` kompaktowo, z posortowanymi kluczami, UTF-8, zawsze zawierając `key_id` i `sig` (jako puste ciągi aż do podpisania):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Krok 2: usuń tylko `sig`.** Forma kanoniczna to ten dokładny tekst z **usuniętym tylko polem `"sig"`**. Ponieważ klucze są posortowane, `sig` zawsze pojawia się jako `,"sig":"<value>",` nawiasowane przez `"schema"` przed nim i `"version"` po nim (oba zawsze obecne), więc jego usunięcie pozostawia dobrze uformowany tekst. JSON escapuje każdy `"` wewnątrz wartości ciągu jako `\"`, więc token strukturalny `"sig":"` jest jednoznaczny nawet wobec nazwy pliku, która dosłownie zawiera `"sig":"`.

Usunięcie to garść rozwinięć parametrów POSIX, identyczne w podpisującym i weryfikatorze, bez `sed` i bez `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Krok 3: podpisz skrót tego.** Podpisana/zweryfikowana wiadomość to **sha256 hex** (64 znaki ASCII, bez nowej linii) formy kanonicznej. ed25519 podpisuje ten hex.

Dwie konsekwencje wynikają z tego z konstrukcji:

- `key_id` jest częścią formy kanonicznej (usuwany jest tylko `sig`). `vdlu-sign` ustawia `key_id` **przed** haszowaniem, więc tożsamość klucza jest objęta podpisem.
- Czy placeholder `sig` jest pusty (`"sig":""`, w czasie podpisywania), czy wypełniony (w czasie weryfikacji), jego usunięcie daje identyczne bajty kanoniczne. Podpisywanie i weryfikacja zgadzają się automatycznie.

Dwa narzędzia POSIX sh są autorytatywne. Równoważnik w Pythonie, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` następnie sha256, istnieje tylko po to, aby je zweryfikować krzyżowo.

Rozumowanie zaufania wokół tego wszystkiego (dlaczego weryfikacja jest na urządzeniu, jak `hardened` zawodzi zamknięto) żyje w [[Security and Trust Model]].

---

## baseline.json (zalążek instalacji)

Gdy moduł jest świeżo zainstalowany, powinien już być "aktualny" dla swojej własnej dostarczonej wersji, bez zbędnej samoaktualizacji wersji, którą właśnie zainstalował. Tym właśnie jest `baseline.json`.

`baseline.json` dostarczany jest **wewnątrz zipa modułu** (w `vdlu/baseline.json`), nie na kanale. Przy świeżej instalacji silnik zaszczepia z niego swój rekord "aktywnej wersji", więc urządzenie rodzi się aktualne, bez `from:0` i bez ponownego pobierania tego, co już ma.

Kluczowe właściwości:

- To **bezkluczowa kopia podpisanego manifestu** dla dostarczonej wersji: ten sam wynik `vdlu-pack`, pozostawiony niepodpisany (`key_id` i `sig` pozostają puste).
- **Nie jest weryfikowany.** Silnik traktuje go jako lokalny zaufany zalążek, ponieważ przybył wewnątrz zflashowanego zipa, który jest granicą zaufania instalacji. Tylko manifest *pobrany z kanału* przechodzi weryfikację podpisu.
- Ponieważ nie potrzebuje podpisu, **CI może wygenerować go bezkluczowo**, co właśnie trzyma klucz podpisujący całkowicie poza CI (zobacz [[Producer]]).
- `vdlu-pack` **wyklucza `baseline.json` ze swojego własnego manifestu**, więc manifest nigdy nie odwołuje się do baseline (to byłaby pętla samoodwołania: manifest do baseline do manifestu).
- Jest **niefatalny, jeśli nieobecny**. Bez niego urządzenie po prostu zaczyna od `from:0` przy pierwszej aktualizacji i pobiera to, czego potrzebuje. Nigdy zepsuty, po prostu mniej optymalny.

---

## Bloby

Każda odrębna treść pliku to jeden blob pod `blobs/`, nazwany przez **sha256 oryginalnej treści**:

- `blobs/<sha256>` dla surowego bloba.
- `blobs/<sha256>.gz` dla bloba spakowanego gzip (gzip jest zachowywany tylko, gdy plik ma co najmniej 4096 bajtów i kompresja oszczędza co najmniej 10 procent).

Blob jest przechowywany raz, w jednym formacie. Adresowanie treścią daje deduplikację za darmo: niezmieniona, współdzielona lub cofnięta treść mapuje się na blob, który już istnieje, więc kanał rośnie tylko o naprawdę nową treść, a urządzenie pobiera tylko te skróty, których mu brakuje. Urządzenie sprawdza `sha256` każdego pobranego bloba względem manifestu (po zdekompresowaniu bloba `gz`), zanim go użyje.

---

## Co jest wykluczone z kanału i dlaczego

Kanał niesie **tylko własną treść modułu**. Ustalony zestaw ścieżek jest trzymany poza nim celowo. `vdlu-pack` stosuje jeden predykat wykluczenia zarówno przy przechodzeniu drzewa, jak i przy obliczaniu `delete[]`.

| Wykluczone | Dlaczego |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (korzeń zaufania: surowe klucze publiczne + plik binarny weryfikatora) | **To jest podstawowy powód bezpieczeństwa.** Kotwica zaufania jest **tylko-z-flasha**. Gdyby keyring lub weryfikator były dostarczalne przez kanał, manifest mógłby nadpisać samą rzecz, która go waliduje. Trzymanie ich poza łączem oznacza, że manifest nigdy nie może przepisać kotwicy zaufania na urządzeniu. |
| `vdlu/baseline.json` | To kopia podpisanego manifestu (zalążek instalacji); spakowanie go byłoby pętlą samoodwołania. |
| `.vd/` infrastruktura flasha | Rusztowanie bramy flasha, które dostarczane jest w zipie, nigdy stosowane na żywo. |
| `update.json`, `update-mmrl.json` | Ich rozmiar/sha są wypełniane przez CI *po* zbudowaniu zipów, więc dostarczona kopia różni się od każdej kopii z kanału. Podanie ich powodowałoby fantomowe pobranie pojedynczego pliku przy pierwszej samoaktualizacji każdej instalacji, a i tak są szczątkowe na urządzeniu (menedżer czyta zdalny surowy update JSON). |
| `META-INF/`, `customize.sh` (rusztowanie instalatora) | Konsumowane przez menedżera w czasie **flasha** i nie zachowywane w zainstalowanym module. Nie są treścią VDLU; serwowanie ich marnuje bloby i, gdyby jeden kiedykolwiek zmienił się między wersjami, zostałby zapisany jako plik instalatora do żywego katalogu modułu. |
| Towarzyszące `.sha256` per-plik | Należą tylko do flashowalnego zipa, stają się przestarzałe po przyrostowej aktualizacji i podwajałyby manifest. |
| Pliki dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nigdy nie dostarczane na urządzenie; serwowanie ich marnuje bloby i wzburza podpisany manifest przy każdej edycji dokumentacji. |

Rozumowanie stojące za wykluczeniem korzenia zaufania jest rozwinięte w [[Security and Trust Model]].

---

## Semantyka delete[]

`delete[]` mówi urządzeniu, które ścieżki usunąć, aby plik upuszczony między wydaniami nie trwał na urządzeniu jako sierota. Jest obliczany przez przekazanie `--prev <previous manifest.json>` do `vdlu-pack`: ścieżka, która była w poprzednim wydaniu i nie jest w bieżącym, staje się wpisem usunięcia.

Ważna reguła: **wykluczone ścieżki nigdy nie są emitowane jako usunięcia, nawet z `--prev`.** Każda poprzednia ścieżka jest przepuszczana przez ten sam predykat wykluczenia, który jest używany przy przechodzeniu drzewa. Jeśli `--prev` wskazuje na starszy manifest, który wciąż wymieniał teraz-wykluczone ścieżki (błądzący `baseline.json`, `META-INF/*`, wpis keyringa itd.), te ścieżki **nie** są zamieniane we wpisy usunięcia. Wykluczona ścieżka nigdy nie była treścią kanału, więc nie jest rzeczą VDLU do usuwania, a urządzeniu nigdy nie jest nakazane usunąć pliku, który nie był serwowany przez kanał. To właśnie powstrzymuje listę wykluczeń od kiedykolwiek zawrócenia jako niszcząca instrukcja.
