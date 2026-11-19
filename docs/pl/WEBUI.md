> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · Polski · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (flashless aktualizacja)

Interfejs VDLU (VD Live Update) dla WebUI menedżera roota KernelSU/APatch. Vanilla JS, bez frameworka, bez
builda, bez CDN. Drop-in: hostowy `index.html` ładuje 2 pliki i wywołuje API.

Zbieżność: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Pliki

| Plik | Co |
|---|---|
| `vdlu.js` | komponent - eksponuje `window.VDLU` |
| `vdlu.css` | toast postępu, baner reboot, zakładka "Updates" (ciemny motyw, dziedziczy zmienne hosta) |
| `demo.html` | samodzielna strona z zamockowanym `ksu.exec` - otwiera się w przeglądarce, bez urządzenia |

## Integracja z hostowym `index.html`

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, poza katalogiem modułu)
    modid:     MODID,
    module:    'Demo',                     // nazwa pokazywana w toaście (default: modid)
    exec:   ex,          // (opcjonalnie) hostowy wrapper ksu.exec; zob. niżej
    toast:  toast,       // (opcjonalnie) hostowy toast przejściowy
    confirm: askConfirm  // (opcjonalnie) hostowy modal potwierdzenia
  });

  VDLU.onWebUIOpen();                          // przy ładowaniu: ocenia journal + baner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // gdy zakładka "Updates" jest otwierana
</script>
```

### Co host musi zdefiniować

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), gdzie engine jest wendorowany
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), stan Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id modułu.

Widget składa komendę engine już niosącą env kontraktu (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` idą w
**tło** (`(… &)`), a postęp jest czytany lekkim pollem (~1s) `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (opcjonalne)

Jeśli pominięte, widget używa swoich własnych:
- **`exec(cmd)`** musi zwrócić `Promise`, który **rozwiązuje się** z stdout (rc 0) i **odrzuca** z stderr
  (rc≠0) - dokładnie sygnatura `ex()` z `webroot/index.html` Demo. Wewnętrzny fallback wywołuje
  `ksu.exec(cmd, '{}', cb)` z tym samym kontraktem.
- **`toast(msg)`** = krótkie przejściowe powiadomienie (fallback wstrzykuje własny mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = modal (dziś używany tylko przez hosta; widget nie wymaga
  potwierdzenia w żadnym przepływie).

Przekazanie własnych hosta sprawia, że widget rozmawia przez TĘ SAMĄ zserializowaną kolejkę i wizualia co reszta
WebUI.

## Publiczne API (`window.VDLU`)

| Funkcja | Robi |
|---|---|
| `init(opts)` | konfiguruje (zob. wyżej). Zwraca `window.VDLU`. |
| `onWebUIOpen()` | wywołaj przy ładowaniu: pokazuje baner jeśli `reboot_pending`; oferuje **Resume** jeśli jest nieterminalna transakcja; z `auto_on_webui_open=1` uruchamia **CICHĄ auto-aktualizację** (najpierw cichy `check()`; wyzwala `run`+trwały toast tylko jeśli `update && fetch>0` - aktualne/przed = wynik inline w panelu, zero toasta). |
| `mountUpdatesPanel(el)` | renderuje zakładkę "Updates" wewnątrz `el` (string id lub element): **Check for update**, **Update now**, przełączniki `auto_on_webui_open`/`auto_on_reboot`, pola boot-retry, select **Network** (`net_policy`: Wi-Fi+komórkowa / tylko-Wi-Fi / tylko-komórkowa) i pola `source`/`channel`/`profile`. |
| `check()` | uruchamia `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | wyzwala `run` w tle + toast postępu z **Cancel**. |
| `cancel()` | tworzy `$VDLU_DIR/cancel` (engine zatrzymuje się w bezpiecznym punkcie). |
| `resume()` | `update.sh resume` + toast (wznawia bieżącą fazę). |
| `refreshBanner()` | ponownie ocenia trwały baner pending-reboot. |

Toast (narożny overlay, nieblokujący) i baner (góra, trwały) są wstrzykiwane przez widget do
`document.body` - host nie potrzebuje HTML dla nich. Zakładka "Updates" to jedyny punkt, który host alokuje (pusty
`<div>`).

### Przepływ stanów, który toast odzwierciedla (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` w każdej chwili. Toast
pokazuje **pasek + `phase done/total · current · bytes`**. Terminale:
- **`DONE`** → zielony toast "v&lt;target&gt; zastosowana".
- **`PENDING_REBOOT`** (lub `reboot_pending=true`) → zielony toast + **trwały baner** "⚠️ Zrestartuj, aby
  aktywować nową `.so` (vX)".
- **`ERROR`** → czerwony toast z powodem (`journal.error`/stderr). Nigdy nie udaje sukcesu.
- **Anulowano** → "anulowano - N/M, wznawialne" + przycisk **Resume**.

## Uruchamianie demo

Otwórz `demo.html` w przeglądarce (`xdg-open webui/demo.html`). Zamockowany `ksu.exec` symuluje ewolucję `update.sh` i
`journal.json`; przyciski przełączają między scenariuszami **LIVE→DONE**, **reboot_pending**, **błąd w środku**
i **anulowalny**. To ten sam `vdlu.js`/`vdlu.css` co na urządzeniu.

## i18n (język)

Stringi widgetu domyślnie na **angielski** (neutralny dla publicznych wielojęzycznych modułów). Host nadpisuje
dowolny klucz, przekazując mapę w `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- definiuje window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Częściowy** merge jest ok: brakujący klucz spada do angielskiego domyślnego.
- Klucze phase/state to `ph_<phase>` / `st_<STATE>`; reszta jest płaska (`cancel`, `updateNow`, …).
- Pełna mapa kluczy = obiekt `DEFAULT_I18N` w `vdlu.js` (również eksponowany jako `VDLU.i18n`).
- Gotowe tłumaczenie jest dostarczone jako opracowany przykład: `i18n/pt-BR.js`. Nowe języki = plik
  `i18n/<lang>.js` w tej samej formie, lub host buduje mapę z własnego systemu i18n.

## Pojedyncze źródło (parzystość między modułami)

Te `vdlu.js`/`vdlu.css` są **kanoniczną kopią**. Każdy moduł osadzający widget
**re-wendoruje** tę kopię bajt-w-bajt do swojego `webroot/` - **nigdy** nie edytuje
swojej na miejscu. Nowa funkcja widgetu rodzi się tutaj i spływa w dół przez re-wendoring; odwrotność produkuje
cichy dryf (zdarzyło się w praktyce: wendorowana kopia została w tyle i brakowało jej `net_policy`, toasta
`DEFERRED` i pól `boot_retry`).

Strażnik: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) znajduje każdą kopię w drzewie źródeł i oznacza
te, które rozchodzą się z kanoniczną (tylko `vdlu.js`/`vdlu.css`; keyring to "weryfikuj, nie kopiuj").

```sh
tools/webui-parity.sh         # raport; wychodzi 1 jeśli jest dryf
tools/webui-parity.sh --fix   # re-wendoruje rozbieżne z kanonicznej
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) i engine (`vdlu/update.sh`) mają własną kadencję re-wendoringu;
> ten strażnik pokrywa **tylko widget WebUI**.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane; zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
