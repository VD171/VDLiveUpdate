<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** to przyrostowy, bezflashowy silnik samoaktualizacji dla modułów **KernelSU / APatch / Magisk**. Zainstalowany moduł aktualizuje się sam, pobierając **tylko pliki, które się zmieniły** (bloby adresowane treścią + podpisany manifest), stosuje te działające na żywo **bez restartu**, a te nieliczne, które restartu wymagają (`.so`, nakładka `/system`, `sepolicy.rule`), przygotowuje i oznacza. Bez menedżera roota, bez ponownego pobierania całego `.zip`, bez restartu poza tymi przygotowanymi plikami.

Został zaprojektowany, aby być **wbudowywanym (vendored)** w moduł (wrzucany do `<module>/vdlu/`), a nie uruchamianym jako samodzielny moduł.

## Dlaczego

Zwykła aktualizacja modułu dostarcza cały `.zip` jeszcze raz. Dla dużego modułu oznacza to spore ponowne pobranie dla kilku zmienionych linijek, a statyczny manifest aktualizacji potrafi wskazać tylko jeden `zipUrl`, więc nie jest w stanie obsłużyć wariantu (ABI, full vs lite), który urządzenie faktycznie posiada. VDLU porównuje **zainstalowane** drzewo z podpisanym feedem i pobiera tylko różnice, więc instalacja arm64-full pozostaje arm64-full, instalacja lite pozostaje lite, a większość aktualizacji stosuje się na żywo.

## Jak to działa

- **Producent (PC / wydanie):** `vdlu-pack` zamienia drzewo modułu w feed adresowany treścią (`manifest.json` + `blobs/<sha256>`, gzip, deduplikacja, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` usuwa osierocone bloby na podstawie referencji do ostatnich N manifestów (fail-safe, domyślnie dry-run).
- **Silnik (urządzenie):** POSIX sh, bez `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) wykonuje DIFF -> FETCH -> APPLY -> COMMIT jako **wznawialną transakcję** (dziennik), z wycofywaniem i blokadą `mkdir`. Podpis jest weryfikowany przez wbudowany `ed25519-mini` (bez `openssl` na urządzeniu).
- **WebUI:** gotowy do wpięcia panel Updates (toast postępu, anulowanie, baner restartu), czysty JS.

## Profile

- `trusted`: użytek prywatny, źródło `file://` lub SSH, weryfikacja best-effort (hash zawsze).
- `hardened`: użytek publiczny, **podpis obowiązkowy**, downgrade zablokowany. Manifest jest **powiązany z id modułu**, a każde pole jest walidowane fail-closed, zanim cokolwiek zostanie pobrane.

## Wdróż go w swoim module

Wbuduj `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` do `<module>/vdlu/`, osadź swój **surowy 32-bajtowy klucz publiczny** jako `vdlu/keyring/<id>.pub`, dodaj `config` (profil + źródło), podepnij wyzwalacze (`post-fs-data.sh` przed zygote dla autoaktualizacji przy starcie; wyzwalacz otwarcia WebUI) i dodaj `vdlu-pack` + `vdlu-sign` do swojego wydania. Zobacz [`docs/QUICKSTART.md`](docs/QUICKSTART.md) dla gotowego szablonu.

## Bezpieczeństwo

- **Każde pole manifestu to wrogie wejście.** `validate_plan()` odrzuca cały manifest fail-closed przy ścieżce absolutnej lub z `..`, przy `sha256`, który nie ma 64 znaków hex, albo przy nieprawidłowym mode / class / encoding, **zanim** nastąpi jakikolwiek fetch czy apply.
- **Prywatny klucz podpisujący nigdy nie dotyka CI ani urządzenia**; osadzany jest wyłącznie surowy klucz publiczny, a weryfikacja używa `ed25519-mini`, nie `openssl`.
- `hardened` jest fail-closed przez inwersję: cokolwiek innego niż dosłowne `trusted` jest traktowane jako `hardened`, więc uszkodzona wartość profilu nigdy nie może po cichu zaakceptować niepodpisanego manifestu.
- Pliki klasy restartu (`.so`, nakładka `/system`, `sepolicy.rule`) są **przygotowywane, nigdy nie zapisywane na żywym inode**; cała reszta stosuje się na żywo. Nieudany apply przerywa działanie, zamiast nadpisać bez kopii zapasowej.

## Budowanie / testowanie

To skrypty, nie ma czego kompilować. Od końca do końca (producent + silnik razem):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # potem run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js` oraz otwarcie `webui/demo.html` w przeglądarce (symuluje mostek do urządzenia).

## Dokumentacja

- [`INTERFACES.md`](docs/INTERFACES.md): kontrakt szwu między komponentami (prawo konwergencji; traktuj je jako niezmienne).
- [`ENGINE.md`](docs/ENGINE.md): silnik po stronie urządzenia (`update.sh`): wznawialna transakcja DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): strona PC/wydania: budowanie i podpisywanie adresowanego treścią feedu (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): gotowy widget panelu Updates (toast postępu, anulowanie, baner restartu).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): przewodnik wdrożenia krok po kroku i fragmenty podpięć.

## Zobacz również

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: podszywanie się pod globalny fingerprint urządzenia / Play Integrity, dla całego urządzenia z zakresem dla poszczególnych aplikacji i WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: pełna kopia zapasowa i przywracanie aplikacji oraz danych jako root, sterowane w całości z WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: samodzielny zrootowany demon SSH (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: Twoje usługi Google (RCS, Wallet, atestacje Play Integrity) odczytywane na Twoim urządzeniu bez internetu.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: bezproblemowy rootowy instalator sideload dla pojedynczych, wsadowych i podzielonych APK, z przełącznikiem weryfikatora Play Protect i podszywaniem źródła instalacji.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: debugger metod urządzenia: odczytuje każdy element wszystkimi metodami, które mogą go odczytać, i porównuje je obok siebie.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: nasze repozytorium modułów dla MMRL/WebUI-X (zainstaluj je wszystkie z menedżera roota).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: zbiór danych fingerprintów `build.prop` z Pixeli (fork @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: użyj Telegrama jako magazynu obiektów z małego CLI w Go.

## Kontakt

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licencja

Własny kod VDLiveUpdate jest objęty licencją **Apache-2.0**; zobacz [LICENSE](LICENSE). Projekt wbudowuje mały
weryfikator `ed25519-mini` oraz statyczny `curl` na potrzeby bootstrapu pobierania, każdy na własnej licencji; zobacz
[NOTICE.md](NOTICE.md) oraz pliki `PROVENANCE.json` obok dołączonych plików binarnych.

## Znaki towarowe

VDLiveUpdate to niezależny, nieoficjalny projekt, niepowiązany z żadną stroną trzecią ani przez nią niepopierany.
"Android" jest znakiem towarowym Google LLC; "KernelSU", "Magisk" i "APatch" są znakami ich
odpowiednich autorów. VDLU działa w całości na Twoim urządzeniu i na Twoim własnym hoście wydań.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
