> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · Polski · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Kontrakt interfejsu (szew między komponentami)

**Prawo zbieżności:** każdy komponent jest zgodny z tym plikiem. Części od 4 agentów muszą **do siebie
pasować** - sygnatury CLI, nazwy plików i klucze JSON poniżej są **niezmienne** (zmiana oznacza najpierw
uzgodnienie tutaj).

Zasady odziedziczone z repozytoriów: **czysty POSIX sh** na urządzeniu (bez bashizmów; działa z
toybox/busybox + `sha256sum`/`gzip`/`base64` z toybox + pobranym `curl` + wbudowanym `ed25519-mini` -
oszczędnie, bez pakietu binariów), **zero zbędnych komentarzy**, **zawsze release**, **rygor przy awarii**
(wznawialna transakcja, nic fałszywie "ukończone", nic nie stracone), **nic nie poluzowane**.

---

## 1. Układ stanu (Tier-2, poza katalogiem modułu)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` w journal = engine zatrzymał się na anulowaniu (stan nieterminalny, wznawialny; `error`
pozostaje null).

Engine wendorowany w module: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine otrzymuje przez env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI engine (komponent ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = błąd (stderr zawiera powód):

| cmd | robi |
|---|---|
| `check` | DIFF: pobiera manifest, porównuje; wypisuje jednowierszowy JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nie zmienia. Urządzenie PRZED feedem (downgrade zablokowany, utwardzone) = stan ŁAGODNY: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nigdy "check failed"). rc do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | pełny cykl: DIFF→FETCH→APPLY→COMMIT; honoruje `cancel`; zapisuje postęp do `journal.json`; stosuje LIVE, inscenizuje REBOOT-hard |
| `resume` | wznawia transakcję `journal.json` od bieżącej fazy (idempotentnie) |
| `boot` | tryb pre-zygote: `resume` + wykonuje SWAP plików `staged/*.vdlu-new` (stosuje `.so`), zamyka `PENDING_REBOOT`→`DONE` |
| `status` | wypisuje `journal.json` (lub `{"state":"idle"}`) |
| `cancel` | tworzy `$VDLU_DIR/cancel` (trwający `run` zatrzymuje się w następnym bezpiecznym punkcie) |

Źródło blobów/manifestu: `source` z config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` zaczyna się od `https://` (statyczny curl pobierany, TLS) lub `file://` (lokalny staging).

## 3. manifest.json (wytwarzany przez PRODUCER, konsumowany przez ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = KOMPLETNE drzewo docelowe. `class`: `live` (webroot/bin/lib/confs/skrypty-na-żądanie/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Domyślnie wg path; nigdy nie obniża `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministyczny; gunzip z toybox na urządzeniu) tylko gdy dobrze się kompresuje ORAZ
  rozmiar jest znaczący; `sha256` jest ZAWSZE z treści oryginalnej.
- `sig`: podpis manifestu kanonicznego BEZ pola `sig` (§4 verify).

## 4. journal.json (ENGINE zapisuje, WEBUI czyta - kontrakt postępu)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Maszyna stanów (stała kolejność): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` dopiero gdy ponowny hash WSZYSTKIEGO się zgadza. Zainscenizowany REBOOT-hard ⇒ `PENDING_REBOOT` (nie
`DONE`). Wyjścia z fazy `fetch`: `ERROR` (twarda awaria) lub `DEFERRED` (net_policy zablokował pobieranie -
łagodne/wznawialne, nie błąd).

## 5. config (key=value, jeden na wiersz; edytowalny w WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (offline) - CIERPLIWY, bezpieczny dla baterii:** tylko przy `boot` (nigdy przy check/auto-open).
Jeśli fetch manifestu zawiedzie z powodu SIECI (`fetch_offline` klasyfikuje wg kodu wyjścia fetchera), czeka i
ponawia aż do sukcesu LUB wyczerpania `boot_retry_minutes` czasu CZUWANIA. Projekt, który **nic nie trzyma i nie
rozładowuje**:
- **Zero wakelock:** między próbami to `sleep`, który zamarza w deep-sleep → urządzenie śpi normalnie
  (~zero baterii); retry pauzuje i wznawia się, gdy urządzenie już nie śpi.
- **Zero trzymanego locka:** `acquire_lock_try`+release MIĘDZY próbami (nie trzyma locka podczas oczekiwania) →
  `run`/ręczny check nigdy nie blokują; jeśli ręczny run zainscenizuje TARGET w międzyczasie, boot się odracza.
- **Nie budzi radia na darmo:** sonda `net_allowed` (przez `net_type`/`ip route get`, kernelowe wyszukiwanie
  trasy respektujące policy-routing Androida; bez pakietu) bramkuje każdą próbę - wydaje fetch dopiero gdy sieć się pojawi.
- NIGDY nie ponawia awarii deterministycznej (manifest/sig/downgrade). `--connect-timeout 15` na fetch (nie
  zawiesza się na captive portal). `service.sh` przenosi go w tło (boot nigdy się nie zawiesza).
- ⛔ **TWARDE: włączenie `boot_retry_minutes>0` wymaga CIERPLIWEGO engine** (tego z
  `net_allowed`+`acquire_lock_try`, kanoniczny `da7115f4`+). POPRZEDNI boot-retry (trzyma lock przez całe okno +
  ponawia ślepy curl offline) **ROZŁADOWUJE baterię/budzi radio** - włączenie retry w starym engine to samobój.
  Przy włączaniu wendoruj bieżący engine.

**`net_policy` (any|wifi|mobile):** bramkuje **POBIERANIE** wg typu sieci. `net_type()` klasyfikuje egress
`ip route get` (interfejs komórkowy `rmnet/ccmni/v4-*/clat` = mobile; wszystko inne = wifi; wyszukiwanie w jądrze,
bez pakietu). `net_allowed()` porównuje z `net_policy` i bramkuje `do_fetch` (bloby) + sondę cierpliwego
boot-retry. **Sprawdzenie manifestu pozostaje darmowe** (malutkie → UI zgłasza aktualizację w każdej sieci);
tylko pobieranie czeka na dozwoloną sieć. Pobieranie w niedozwolonej sieci = stan **`DEFERRED`** w journal (NIE
ERROR; łagodny niebieski INFO-toast "oczekiwanie na sieć X"; plan/target trwają, wznawia się przy następnym
check/boot w właściwej sieci). `net_policy` **zastępuje** `allow_metered` (który nigdy nie był konsumowany).
Engine `97baf887`+ (`file://` nigdy nie jest bramkowany).

## 6. Podpis (PRODUCER podpisuje na PC przez openssl; ENGINE weryfikuje na urządzeniu przez ed25519-mini)

- Kanonikalizacja: manifest BEZ `sig`, klucze posortowane, kompaktowy JSON (bez zbędnych spacji), UTF-8.
  To, co podpisywane/weryfikowane = hex `sha256` tej formy kanonicznej (daje determinizm między narzędziami).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → wstrzykuje `key_id` + `sig` (base64 podpisu ed25519 kanonicznego sha256) do manifestu, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 jeśli `sig` zgadza się z pubkey `<key_id>.pub` w
  keyring (SLIM: pubkey **RAW 32 bajty**). Wewnętrznie, bez openssl: `sha256sum`/`base64 -d` z toybox + wbudowany
  binary `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=ważny/1=nieważny/2=użycie).
  rc!=0 = odrzuć. **`profile=hardened` ⇒ verify obowiązkowy; awaria = przerwanie.**
  `profile=trusted` ⇒ verify jest best-effort (źródło już zaufane przez SSH), ale hash każdego bloba jest ZAWSZE sprawdzany.
- `producer/vdlu-keygen <id> <out>` → generuje `<id>.pem` (priv) + `<id>.pub` (PEM, dla toolingu na PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` oszczędnego keyring na urządzeniu). openssl `genpkey -algorithm ed25519`.

## 7. Blob - weryfikacja (ENGINE)

Pobiera `<source>/blobs/<sha>` (lub `.gz` jeśli `enc=gz`), zapisuje `.part`, jeśli `gz` rozpakowuje (`gunzip`),
sprawdza `sha256sum` == `sha256` manifestu; zgodność → atomowy `mv` do `$VDLU_DIR/blobs/<sha>`. 3 awarie na
tym samym blobie = przerywa fazę (nic nie zastosowane). Blob już w `$VDLU_DIR/blobs/<sha>` z poprawnym hashem =
pomija pobieranie.

## 8. APPLY wg klasy (ENGINE)

- `live`/`soft`: kopia zapasowa `rollback/<v>/<path>` → zapisuje `$MODULE_DIR/<path>.vdlu-tmp` z bloba → `chmod mode` →
  atomowy `rename` na cel. Już na hashu docelowym = pomiń. (W wariancie Zygisk zapis idzie do zamontowanego
  katalogu = scalanie per plik, nigdy `rm -rf` katalogu.)
- `reboot`: materializuje do `$VDLU_DIR/staged/<path>.vdlu-new` (NIE dotyka żywego). Swap przy `boot`.
- `delete[]`: kopia zapasowa → usunięcie.

## 9. WEBUI ↔ ENGINE (komponent WEBUI)

- Wyzwala: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Postęp: lekki poll `ksu.exec("cat $VDLU_DIR/journal.json")` co ~1s; renderuje `{phase,state,total,done,current,bytes}`.
- Żywotność: journal nieobecny przez 8 ticków ⇒ "brak odpowiedzi". Journal ZAMROŻONY (te same wartości) przez 20 ticków ⇒ sprawdza `lock.d`: żywy = kontynuuje (wolny fetch 1 bloba), martwy = błąd + Resume. Bez tego run, który zginął w środku fetcha, zamroziłby toast na "aktualizowanie".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: czyta/zapisuje `$VDLU_DIR/config` (key=value) w zakładce "Updates".
- Toast: pasek + `phase done/total · current`; przy zakończeniu z `reboot_pending` ⇒ trwały baner "zrestartuj, aby aktywować .so".
- Auto-open (`auto_on_webui_open=1`): najpierw robi CICHY `check()` (bez toasta postępu); wyzwala `run`+trwały toast tylko jeśli `update && fetch>0`. Aktualne/przed/nic-nowego = wynik inline w panelu, zero resztkowego toasta. Nienachalne jak ręczny przycisk (toast pojawia się tylko przy realnym pobieraniu). Bootstrap curl jest jednorazowy.

## 10. Integracja z demo (komponent INTEGRATION) - SNIPPETY, nie edytuj żywych plików

Produkuje, w `integration/demo/`, snippety + `INTEGRATION.md` mówiący, gdzie każdy idzie (bez stosowania):
- hook `auto_on_reboot` w `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) i `auto_on_webui_open`.
- domyślne `config` + wbudowany keyring + wendoring (`modules/<mod>/vdlu/`).
- wariant CZĘŚCIOWY (scalanie do zamontowanego katalogu).

## 11. Pobrany toolchain + baseline (SLIM, Podejście B)

**Układ w module (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **BRAK** `bin/` (openssl/curl/zstd). `customize.sh` może przyciąć
`verify/` do ABI urządzenia (`vdlu-verify` znajduje mini w `<dir>/ed25519-mini` LUB `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (wbudowany binary, tylko-verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=ważny,
1=nieważny, 2=użycie/IO. msg = dokładne podpisane bajty (NIE re-hashuje). TweetNaCl PD, statyczny per ABI, PROVENANCE.

**tools-feed** (tylko profil public/https): serwowany pod `<tools_source>` (domyślnie wywiedziony: zamienia
ostatni segment `source` na `vdlu-tools`, np. `https://<user>.github.io/<repo>/vdlu-tools`). Zawiera:
- `tools-manifest.json` - PODPISANY manifest `vdlu-pack` nad drzewem `<abi>/curl`, przypinający `sha256`
  każdego curl (ten sam klucz `release-2026`).
- `<abi>/curl` - SUROWY **statyczny** curl (samodzielny, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS NIE
  niesie bundla CA: `fetch_url` przekazuje `--capath` (autowykrywanie trust store Androida: `/system/etc/security/cacerts`
  → APEX conscrypt; `ca_path` nadpisuje). Bez capath = błąd 60. Integralność to ed25519; sprawdzanie certyfikatu to obrona w głąb.

**install-tool** (ENGINE): `update.sh install-tool <abi>` czyta `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI pobiera go przez `fetch()` i zapisuje tam), **weryfikuje podpis tools-manifest (ed25519-mini,
OBOWIĄZKOWY w każdym profilu)** + hash curl == manifest, i dopiero wtedy instaluje go do `$VDLU_DIR/tools/<abi>/curl` (0755).
curl działa jako root → sig+hash przed exec zamyka RCE. Trwa w Tier-2: nigdy nie pobierany ponownie (poza uninstall).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): działa przed check/run/resume. `file://` = no-op; curl JUŻ
dostępny (Tier-2, LUB `module/bin/<abi>/curl` z **samo-dołączonego** modułu, LUB system) = no-op
(VDLU wykorzystuje istniejący curl); tylko `https` **bez żadnego curl** pobiera curl + tools-manifest przez webview, zapisuje
je do `.work` (base64 w kawałkach przez `ksu.exec`), wywołuje `install-tool`. Zaufanie = sprawdzenie na urządzeniu, nie pobieranie.

> 🪤 **Slim (fetch-bootstrap) ≠ obowiązkowy.** Moduł, którego `bin/` istnieje dla JEGO WŁASNYCH funkcji (np.
> niesie restic/rclone/age/tar/curl...) **nie** chudnie do ~2MB ani nie pobiera curl - VDLU przyjmuje oszczędny
> engine (gz, mini, baseline, poprawki) i **wykorzystuje** wbudowany toolchain. Tylko moduły bez własnego
> toolchainu zyskują ~2MB.

**baseline.json** (poprawka from:0): release kopiuje PODPISANY `manifest.json` dostarczanej wersji do
`vdlu/baseline.json`; przy świeżej instalacji engine zasiewa `current.json` z niego (`init_paths`, tylko jeśli brak) → urządzenie
rodzi się "aktualne", bez auto-aktualizacji siebie i bez ponownego fetcha.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane; zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
