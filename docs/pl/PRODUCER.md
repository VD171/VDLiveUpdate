> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · Polski · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Warstwa producer + podpisu VDLU

Buduje adresowalną treścią dostawę (manifest + bloby) dla modułu i podpisuje ją.
Zgodna z [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| narzędzie | działa na | język | zadanie |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | obchodzi finalne drzewo modułu -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | para kluczy ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B dla oszczędnego keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | wstrzykuje `key_id` + `sig` do manifestu, in place |
| `engine/vdlu-verify` | **urządzenie** | sh + ed25519-mini | weryfikuje `sig` przez wbudowany ed25519-mini; keyring = pubkey RAW 32B (BEZ openssl na urządzeniu) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` jest adresowalny treścią i deduplikujący: blob, którego `<sha256>` już istnieje, nie jest
przepisywany, więc publikacja jest inkrementalna, a niezmieniona / cofnięta treść nigdy nie jest ponownie wypychana.

### Decyzja `enc` (vdlu-pack)

`sha256` jest **zawsze** z treści oryginalnej (nieskompresowanej); `enc` tylko nazywa, jak blob jest przechowywany.

- `gz` gdy `size >= 4096` **oraz** gzip (`-9 -n`, deterministyczny) oszczędza co najmniej 10% (`comp <= raw*0.90`).
- `raw` w przeciwnym razie (mały tekst, który HTTP gzip już pokrywa, lub już-nieściśliwe dane).
- gzip brakuje na hoście builda -> wszystko `raw` (nigdy nie zawodzi).

Blob jest przechowywany raz, w jednym formacie: `blobs/<sha256>` (raw) lub `blobs/<sha256>.gz` (gz). Urządzenie
rozpakowuje przez toybox `gunzip` (zawsze obecny), więc żaden zstd nie jest dołączany.

### Decyzja `class` (vdlu-pack) - taksonomia reboot

Wywiedziona z path (INTERFACES §3, doc §4). Tylko domyślne; reguła path nigdy nie obniża `reboot`->`live`.

| class | dopasowane przez | stosowane |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | zainscenizowane `.vdlu-new`, swap przy rozruchu |
| `soft` | korzeniowe `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | zapisane live, uruchamia się przy następnym rozruchu |
| `live` | wszystko inne (webroot, bin, lib, confs, module.prop, ...) | zapisane live, atomowo |

Symlinki **nie są śledzone** (nigdy nie wycieka treść spoza drzewa, np. link do
`/etc/shadow`) i są pomijane z ostrzeżeniem, ponieważ schemat manifestu nie ma typu symlink.
Pliki nieregularne (katalogi, fifo, urządzenia) są pomijane. `built` honoruje `SOURCE_DATE_EPOCH` dla
odtwarzalnych manifestów.

### Baseline (ziarno instalacji) - niepodpisany, bez klucza

`baseline.json` (dostarczany pod `vdlu/baseline.json` w zipie modułu) zasiewa `current.json` przy świeżej instalacji,
aby urządzenie rodziło się "aktualne" (bez from:0, bez ponownego fetcha). Engine traktuje go jak **lokalne zaufane ziarno**
(przybył we flashowanym zipie, który jest granicą zaufania instalacji) i **NIE weryfikuje jego podpisu** -
tylko manifest POBRANY z feedu przechodzi przez `vdlu-verify`. Więc baseline nie potrzebuje **klucza**: to
po prostu wynik `vdlu-pack` nad dostarczanym drzewem (niepodpisany; `sig`/`key_id` pozostają puste). CI może zatem
generować go **bez klucza**, trzymając klucz podpisujący w 100% poza CI - tylko opublikowany FEED jest podpisywany (operator,
lokalnie). `vdlu-pack` wyklucza `baseline.json` ze swojego własnego manifestu (anty samoodwołanie). Niekrytyczne jeśli
nieobecny: urządzenie po prostu startuje od from:0 przy pierwszej aktualizacji, nigdy zepsute.

## Kanonikalizacja (punkt zbieżności)

`vdlu-sign` i `engine/vdlu-verify` muszą wyprowadzić **te same bajty** z manifestu, na dwóch
różnych runtime'ach (openssl na PC vs toybox na urządzeniu). Reguła jest celowo transformacją
bajtów, a nie re-serializacją JSON, więc nie potrzebuje biblioteki JSON na urządzeniu:

1. `vdlu-pack` zapisuje `manifest.json` **kompaktowy, klucze posortowane, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), zawsze włączając
   pola `key_id` i `sig` (placeholdery pustego stringa aż do podpisania). To kanoniczna
   forma przechowywania.
2. **Forma kanoniczna = ten tekst z usuniętym polem `"sig"`.** Ponieważ klucze są posortowane, `sig`
   zawsze pojawia się jako `,"sig":"<value>",` otoczony przez `"schema"` (przed) i `"version"` (po),
   oba zawsze obecne. Usunięcie go pozostawia poprawnie uformowane `...,"schema":N,"version":...`.
   JSON escapuje każdy `"` wewnątrz wartości stringowych na `\"`, więc strukturalny token `"sig":"` jest
   jednoznaczny nawet wobec nazwy pliku, która dosłownie zawiera `"sig":"` (przetestowane).
3. Podpisywany/weryfikowany komunikat to **hex sha256** (64 znaki ASCII, bez newline) formy
   kanonicznej. ed25519 nad tym hexem (`openssl pkeyutl -sign/-verify -rawin`).

Usunięcie w POSIX sh (identyczna funkcja w obu narzędziach, bez `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` jest częścią formy kanonicznej (usuwany jest tylko `sig`); `vdlu-sign` ustawia `key_id` **przed**
hashowaniem. Placeholder wartości będący pusty (`"sig":""`, czas podpisu) lub wypełniony (czas weryfikacji) daje
identyczne bajty kanoniczne, więc sign i verify zgadzają się z konstrukcji.

Python odtwarza to jako `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)`, następnie sha256 - używane
tylko do kontroli krzyżowej; autorytatywni producenci to dwa narzędzia sh.

## Podpis (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  do podpisu/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER to 12-bajtowy prefiks + 32-bajtowy klucz, więc `tail -c 32` JEST kluczem). Emituje OBA.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` nad kanonicznym sha256 hex; podpis przechowywany base64.
- `vdlu-verify` (**urządzenie, oszczędny**): `ed25519-mini <pubkey32> <msg> <sig64>` - czyta keyring jako pubkey **RAW 32B**,
  BEZ openssl na urządzeniu. `key_id` jest sanityzowany wg path (bez `/`, `.`, `..`, `"`). 🚨 Keyring dostarcza
  **`.pub.raw` (32B)**, nigdy `.pub` PEM (113B): PEM jest tylko po stronie PC, a `ed25519-mini` nie potrafi go odczytać.

Model zaufania (INTERFACES §6, doc §11/§13): `profile=hardened` (publiczny) czyni verify obowiązkowym - zawiedziony
lub brakujący podpis przerywa aktualizację. `profile=trusted` (prywatny, źródło staged przez SSH) traktuje
verify jako best-effort, ale sha256 każdego bloba jest sprawdzany tak czy inaczej.

## Keyring + rotacja

Keyring to katalog plików `<key_id>.pub`, każdy będący pubkey ed25519 **RAW 32B** (z
`.pub.raw` z `keygen`), NIE PEM - `ed25519-mini` czyta surowe 32 bajty. Dostarcz bieżący **oraz** poprzedni
surowy pubkey (doc §13), aby zrotowany klucz nie uszkodził starszych instalacji. `vdlu-sign` z nowym `key_id` i urządzenie
wybierające `<keyring>/<key_id>.pub` (surowy) to cały mechanizm rotacji - bez zmiany engine. Keyring jest
**stabilny** między releasami (zmienia go tylko rotacja klucza): re-wendoring musi **weryfikować-nie-kopiować** i nigdy
nie nadpisywać go PEM-em `.pub` po stronie PC.

**Keyringi wielokluczowe MUSZĄ przypiąć klucz modułu.** Engine ogranicza, który `key_id` może podpisać MODULE-UPDATE, do allowlisty `key_id` z configu (INTERFACES §5/§6), sprawdzanej fail-closed przed wyborem pubkey. Keyring z jednym kluczem jest domyślnie bezpieczny (ten jeden klucz jest akceptowany). Ale moduł, którego keyring NIESIE także klucz niższego zaufania - np. klucz fingerprint-feedu obok klucza release - jest odrzucany, dopóki jego `config` nie zadeklaruje klucza modułu, np. `key_id=vd-2026` (rozdzielone przecinkami dla rotacji, np. `key_id=vd-2026,vd-2027`). To powstrzymuje wyciekły klucz niższego zaufania od podpisania flashless aktualizacji root.

`vdlu-pack` **wyklucza keyring i binaria `verify/` z feedu** (korzeń zaufania jest wyłącznie-flash, nigdy nie serwowany po kablu), obok `baseline.json`, rusztowania instalatora (`META-INF/`, `customize.sh`), bramki flash `.vd/`, wypełnianych przez CI `update.json`/`update-mmrl.json` oraz towarzyszy `.sha256` per plik. Tylko własna treść modułu jest aktualizowalna przez feed, więc manifest nigdy nie może nadpisać kotwicy zaufania na urządzeniu.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane; zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
