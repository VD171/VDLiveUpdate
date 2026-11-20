> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · Polski · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Polityka bezpieczeństwa i model zaufania

VDLiveUpdate (VDLU) stosuje **flashless aktualizacje root** do żywego modułu: zapisuje do
`/data/adb/modules/<mod>` i robi swap `.so` Zygisk przy rozruchu. Każde pole pobranego
manifestu (`path`, `sha256`, `delete[]`, `mode`, ...) jest **wrogim wejściem** - zatruty feed
lub MITM je dostarcza. Ta strona to model zaufania i polityka odpowiedzialnego ujawniania.
Pełny kontrakt styku zobacz w [`INTERFACES.md`](INTERFACES.md), a wnętrze engine/producera w
[`ENGINE.md`](ENGINE.md) i [`PRODUCER.md`](PRODUCER.md); strona wiki
**Security-and-Trust-Model** niesie ten sam model dla czytelników spoza repo.

## Wspierane wersje

Poprawki bezpieczeństwa lądują w najnowszym `ENGINE_VERSION`; podpisany manifest deklaruje
minimalny engine, którego potrzebuje, przez `engine_min`, a engine na urządzeniu odmawia
manifestowi, który prosi o więcej, niż implementuje. Oczekuje się, że starsze wendorowane
engine zostaną **ponownie wendorowane**, aby pobrać poprawkę, a nie załatane w miejscu.

| ENGINE_VERSION | status |
|---|---|
| 4 (bieżący) | wspierany - allowlista `key_id`, odrzucanie path z dot-segmentem/końcowym-slashem, limity rozmiaru, lock w czasie check |
| 3 | zastąpiony - domyślny `hardened`, fail-closed `profile` przez inwersję, bind module/MODID, blokada downgrade |
| <= 2 | niewspierany - ponownie wendoruj bieżący engine |

Każda zmiana weryfikacji engine lub logiki apply podbija `ENGINE_VERSION`.

## Zgłaszanie podatności

Zgłaszaj prywatnie. **Nie** otwieraj publicznej issue, PR ani wpisu na forum dla błędu
bezpieczeństwa. Użyj kontaktów projektu (zobacz [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanał: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Dołącz proszę wersję engine, używany `profile` oraz manifest lub feed, który reprodukuje
problem. Poprawki są dostarczane jako nowy `ENGINE_VERSION` z wpisem w `CHANGELOG.md`;
skoordynuj czas ujawnienia w wątku zgłoszenia.

## Model zaufania

- **Odłączone podpisy ed25519.** Producer podpisuje kanoniczny manifest na PC (openssl);
  urządzenie weryfikuje wbudowanym `ed25519-mini` - **bez openssl na urządzeniu**. Podpisana
  wiadomość to hex sha256 manifestu bez jego pola `sig` (klucze posortowane, kompaktowy,
  UTF-8), więc sign i verify wyprowadzają te same bajty na dwóch runtime'ach bez biblioteki
  JSON na urządzeniu.
- **Keyring = pubkeye RAW 32-bajtowe**, wyłącznie-flash. Keyring urządzenia dostarcza
  `<key_id>.pub` jako surowy 32-bajtowy klucz (nigdy PEM); `vdlu-pack` **wyklucza** keyring i
  binaria `verify/` z feedu, więc manifest nigdy nie może nadpisać kotwicy zaufania na
  urządzeniu po kablu.
- **Allowlista `key_id` module-update (fail-closed, przed wyborem pubkey).** Keyring może
  zasadnie nieść więcej niż jeden klucz (na przykład klucz fingerprint-feedu niższego zaufania
  obok klucza release). Zanim `<key_id>.pub` zostanie w ogóle wybrany, `verify_manifest`
  odrzuca każdy manifest, którego `key_id` nie ma na skonfigurowanej allowliście, w **obu**
  profiles, i odzwierciedla rozwiązany zbiór do `vdlu-verify` przez `VDLU_KEYID_ALLOW`. To
  zamyka obejście, w którym wyciekły klucz niższego zaufania mógłby inaczej podpisać pełną
  flashless aktualizację root. Domyślnie bezpieczne, gdy `key_id` nieustawione: keyring z
  **jednym kluczem** auto-przypina się do tego jednego klucza; keyring **wielokluczowy** jest
  odrzucany, dopóki `key_id` nie zostanie przypięte (rozdzielone przecinkami dla rotacji).
- **Korzeń zaufania fingerprint-feedu to osobny, przypięty path** z własnym kluczem; nigdy nie
  jest osiągalny przez powyższy path module-update.
- **Baseline to lokalne zaufane ziarno.** `baseline.json` przybywa wewnątrz flashowanego zipa -
  granicy zaufania instalacji - więc jest niepodpisany i bez klucza i **nie** przechodzi przez
  `vdlu-verify`; weryfikowany jest tylko manifest **pobrany** z feedu. To trzyma klucz
  podpisujący poza CI.

## Gwarancje fail-closed

- **`validate_plan` uruchamia się przed każdym fetchem lub apply.** W `do_diff`, fail-closed,
  odrzuca **cały** manifest, jeśli jakikolwiek `path` jest absolutny, zawiera segment `..` lub
  `.`, kończy się na `/`, lub zawiera znak kontrolny; jeśli jakikolwiek `sha256` nie jest
  `^[0-9a-f]{64}$`; lub jeśli jakikolwiek `mode`/`class`/`enc` jest nieprawidłowy. Żadne wrogie
  pole nie dociera do shella, a `cmd_check` nie niesie interpolacji `system()`.
- **Zawieranie path.** Każdy zapis i usunięcie jest ograniczone do `MODULE_DIR` przez
  `contained()` - apply, delete oraz `stage_file` rozruchu przechodzą przez tę samą straż.
  Symlinki w drzewie są pomijane przez producera (nigdy nie wyciekają treści spoza niego).
- **Dwa profiles, fail-closed przez inwersję.** `trusted` (prywatny, źródło staged przez SSH)
  to **jedyny** opt-in do verify best-effort; **każda** inna wartość - w tym literówka, końcowa
  spacja/CR, lub inna wielkość liter - jest traktowana jako `hardened`, gdzie poprawny podpis
  jest **obowiązkowy**, a awaria przerywa. `sha256` każdego bloba jest sprawdzany w obu
  profiles.
- **Podpis + hash przed każdym exec narzędzia.** Pobrany statyczny `curl` działa jako root,
  więc `install-tool` weryfikuje podpis tools-manifestu (ed25519-mini, obowiązkowy w **każdym**
  profile) oraz hash curla **zanim** zostanie zainstalowany i wykonany - sig+hash przed exec
  zamyka RCE.
- **Wznawialna, pin-safe transakcja.** Manifest w locie jest przypięty w `target.json`; crash,
  utrata sieci, lub reboot wznawia z journala bez ponownego decydowania planu. Downgrade jest
  zablokowany (monotoniczny `version`), podpisane pole `module` musi równać się `MODID`, a
  `delete[]` uruchamia się tylko przy `finalize_done` (`PENDING_REBOOT` niczego nie usuwa). Nic
  nigdy nie jest "zrobione" bez pełnego re-hasha; nic nie jest nadpisywane bez wcześniejszej
  kopii zapasowej `rollback/<v>/`.

## Hardening (obrona w głąb)

- **Limity rozmiaru.** Manifest, tools-manifest oraz ścieżka pobierania `wget`/`head -c` bez
  curla są ograniczone przed odczytem (anty-OOM / anty-flood). Blob zawodzi swoją fazę po 3
  próbach.
- **Lock w czasie check.** `check` bierze mkdir-lock przed przebudową swojego work dir, więc
  współbieżne uruchomienie nie może się z nim ścigać.
- **Zawieranie stagingu.** `stage_file` ma tę samą straż `contained()` co prymitywy apply
  live, więc staged ścieżka reboot-hard również nie może uciec z `MODULE_DIR`.
- **TLS to obrona w głąb, nie korzeń zaufania.** Statyczny curl używa mbedTLS z magazynem
  zaufania Androida (`--capath`, override `ca_path`); gwarancją integralności jest podpis
  ed25519, sprawdzenie certyfikatu to druga warstwa.

## Zobacz też

- [`INTERFACES.md`](INTERFACES.md) - niezmienny kontrakt styku (§5 config, §6 podpis, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - engine po stronie urządzenia i jego maszyna stanów.
- [`PRODUCER.md`](PRODUCER.md) - packing, podpisywanie, kanonikalizacja i rotacja klucza.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane; zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
