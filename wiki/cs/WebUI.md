# WebUI

VDLU dodává volitelný drop-in WebUI widget: malý panel "Updates" pro WebUI root manageru KernelSU nebo APatch. Dává uživateli tlačítko Check, tlačítko Update now, živý toast postupu se zrušením, banner restartu a panel nastavení, vše aniž by se uživatel kdy dotkl terminálu.

Je to **vanilla JavaScript**: žádný framework, žádný build krok, žádné CDN. Tři soubory:

| Soubor | Co to je |
|---|---|
| `vdlu.js` | widget; vystavuje `window.VDLU` |
| `vdlu.css` | styly pro toast, banner a panel (tmavý motiv, dědí CSS proměnné hostitele) |
| `demo.html` | samostatná stránka, která napodobuje most zařízení, takže celé UI běží v obyčejném prohlížeči |

Widget je zcela volitelný. [[Engine]] běží dobře sám o sobě z boot triggeru; WebUI je jen přátelská tvář nad ním. Viz [[Quick Start]] pro zapojení do modulu.

---

## Jak UI mluví s enginem: most `ksu.exec`

Widget sám nikdy nedělá nic privilegovaného. Sestaví shellový příkaz a předá ho mostu `ksu.exec` root manageru, který ho spustí jako root a vrátí stdout / stderr / návratový kód. Vše, co panel zobrazuje, se čte zpět ze souborů, které engine zapisuje.

Widget obalí tento most do jediné funkce `exec(cmd)`, která vrací `Promise`:

- **resolvuje** s stdout, když příkaz skončí s 0
- **odmítá** s stderr (nebo `rc=N`) jinak

Každý příkaz nese prostředí kontraktu, sestavené widgetem:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Několik konkrétních volání:

- **Spustit aktualizaci:** `update.sh run` se spustí na **pozadí** (`(... &)`), takže UI nikdy není blokováno dlouhým stahováním.
- **Číst postup:** lehký polling (asi jednou za sekundu) `cat $VDLU_DIR/journal.json`.
- **Zrušení:** `touch $VDLU_DIR/cancel` (engine se zastaví v příštím bezpečném bodě).
- **Konfigurace:** čtení a zápis `$VDLU_DIR/config` (key=value), zachovávající pořadí a neznámé klíče a dotýkající se jen klíčů, které uživatel změnil.

Pokud hostitel předá vlastní pomocníky `exec`, `toast` a `confirm` do `init()`, widget směruje přes vlastní serializovanou frontu příkazů a vizuál hostitele, takže vypadá a chová se jako zbytek té WebUI. Pokud jsou vynechány, widget se vrátí k přímému volání `ksu.exec` a vloží svůj vlastní mini-toast.

---

## Toast postupu (se zrušením)

Jakmile aktualizace běží, widget zobrazí neblokující rohový toast a polluje `journal.json`. Toast odráží stavový automat enginu:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Vykreslí progress bar plus řádek `phase done/total - current file - bytes` a nese tlačítko **Cancel** po celou dobu. Koncové stavy každý dostanou vlastní zacházení:

- **DONE** -> zelený toast, "vX applied - all verified".
- **PENDING_REBOOT** -> zelený toast plus trvalý banner restartu (níže).
- **ERROR** -> červený toast s důvodem z `journal.error` nebo stderr, nabízející Retry. Nikdy nepředstírá úspěch.
- **Cancelled** -> jantarový toast, "cancelled - N/M applied, resumable", nabízející **Resume**.
- **DEFERRED** -> jemný modrý informační toast, "download deferred, waiting for the allowed network". To je neškodné čekání na síťovou politiku, ne chyba; obnoví se při příští kontrole nebo bootu na správné síti.

Polling je defenzivní. Napůl zapsaný žurnál (engine zapisuje souběžně) se pro ten tick ignoruje místo špatného parsování. Pokud žurnál zmizí poté, co byl viděn postup, znamená to, že ho commit vymazal: widget nahlásí DONE. Pokud je žurnál nepřítomný od začátku po 8 ticků, nahlásí "no response". A pokud žurnál zamrzne na stejných hodnotách po 20 ticků, widget zkontroluje `lock.d` enginu: pokud je zámek živý, je to jen pomalé stahování jednoho blobu a toast dále čeká; pokud je zámek mrtvý, běh zemřel v půlce, takže widget vynoří chybu s tlačítkem Resume místo donekonečna točit na "updating".

---

## Banner restartu

Některé soubory nelze vyměnit na živém systému: `.so`, overlay `/system`, `sepolicy.rule`. Engine je inscenuje a označí transakci `PENDING_REBOOT`. Widget pak zobrazí **trvalý horní banner**: "Reboot to activate the new `.so` (vX)". Zůstává, dokud se inscenované soubory při příštím bootu nevymění. Při otevření WebUI se banner znovu vyhodnotí ze žurnálu, takže uživatel, který UI zavře a znovu otevře, ho stále vidí. Viz [[Reboot Handling]] pro to, co se stane při bootu.

Všimněte si, že banner se řídí koncovým stavem `PENDING_REBOOT`, ne příznakem `reboot_pending` (který se stane pravdivým, jakmile jakékoli `.so` vstoupí do plánu). To brání banneru objevit se uprostřed běhu dříve, než se něco skutečně inscenuje.

---

## Panel "Updates": nezávislé přepínače po kategoriích

`mountUpdatesPanel(el)` vykreslí panel nastavení do prázdného `<div>`, který hostitel poskytne. Má tři sekce a každé ovládání je nezávislé a ukládá se samo:

**Actions**
- **Check for updates** -> spustí `check`, zobrazí výsledek inline (aktuální / novější než feed / aktualizace k dispozici s počtem souborů a tagem restartu).
- **Update now** -> spustí `run` plus toast postupu.

**Automation** (nezávislé přepínače, každý zapsán do `config` v okamžiku přepnutí)
- **On WebUI open** (`auto_on_webui_open`) -> spustit tichou aktualizaci, když se UI otevře.
- **On reboot** (`auto_on_reboot`) -> aplikovat v pre-zygote při bootu.
- **Boot retry every (s)** a **Boot retry up to (min)** -> číselná pole pro opakování fetche manifestu, když zařízení bootuje offline.

**Source**
- `source` (URL feedu), `channel` (stable / canary), `profile` (trusted / hardened) a výběr **Network** mapující na `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Přepínače a číselná pole se ukládají okamžitě a vizuálně se vrátí, pokud zápis selže. Textová a výběrová pole v sekci Source se označí jako změněná a ukládají se společně při explicitním tlačítku Save. Panel vždy přepisuje jen klíče, kterých se uživatel dotkl, takže jakékoli neznámé nebo budoucí konfigurační klíče jsou zachovány.

### Chování auto-open

`onWebUIOpen()` se volá při načtení hostitele. Vyhodnotí žurnál (zobrazí banner restartu nebo nabídne Resume pro nekoncovou transakci zanechanou předchozí relací), pak, pokud `auto_on_webui_open=1`, nejprve spustí **tichý** `check()`. Trvalý toast postupu a samotný `run` se spustí jen tehdy, když je co skutečně stahovat (`update && fetch > 0`). Pokud je zařízení aktuální nebo před feedem, výsledek se zobrazí inline v panelu a na obrazovce nezůstane žádný toast, takže auto-aktualizace je stejně nevtíravá jako ruční tlačítko.

---

## i18n (řetězce po jazycích)

Každý UI řetězec se výchozí hodnotou vrátí k **angličtině**, což je neutrální volba pro veřejné vícejazyčné moduly. Úplná mapa klíčů žije v objektu `DEFAULT_I18N` v `vdlu.js` (také vystavena jako `VDLU.i18n`). Hostitel přepíše jakoukoli podmnožinu klíčů předáním mapy do `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- **Částečná** mapa je v pořádku: jakýkoli chybějící klíč se vrátí k anglickému výchozímu.
- Štítky fází a stavů používají klíče `ph_<phase>` a `st_<STATE>`; zbytek jsou ploché klíče jako `cancel`, `updateNow`.
- Propracovaný překlad (`i18n/pt-BR.js`) se dodává jako šablona; nový jazyk je prostě soubor `i18n/<lang>.js` ve stejném tvaru, nebo hostitel sestaví mapu ze svého vlastního i18n systému.

---

## demo.html: spustit UI bez zařízení

`demo.html` napodobuje most `ksu.exec`, takže přesně tytéž `vdlu.js` a `vdlu.css` běží v obyčejném prohlížeči, bez rootu a bez telefonu:

```sh
xdg-open webui/demo.html
```

Mock simuluje `update.sh` a vyvíjející se `journal.json` a jeho tlačítka přepínají mezi scénáři: živá aktualizace až do DONE, dokončení `reboot_pending`, chyba v půlce a zrušitelný běh. Je to nejrychlejší způsob, jak vidět a iterovat UI, a je to to, co zkontrolujete, než widget vendorujete do modulu.

---

## Zapojení do modulu (trigger otevření WebUI)

Hostitelský `index.html` načte dva soubory a volá tři funkce:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

Hostitel potřebuje jen dodat Tier-2 cesty a alokovat jeden prázdný `<div>` pro panel; toast a banner vkládá widget do `document.body`. `onWebUIOpen()` je trigger otevření WebUI: je to to, co vyhodnocuje banner restartu, nabízí Resume při přerušené transakci a spouští tichou auto-aktualizaci, když je nastaveno `auto_on_webui_open`.

### Jediný zdroj, znovu vendorovaný bajt po bajtu

`vdlu.js` a `vdlu.css` jsou **kanonická kopie**. Modul, který widget vkládá, znovu vendoruje tyto soubory nezměněné do svého `webroot/`; nikdy neupravuje svou vlastní kopii na místě. Nová funkce se narodí v kanonických souborech a steče dolů znovu-vendorováním. Úprava vendorované kopie produkuje tiché posunutí (stalo se to: zastaralá kopie postrádala `net_policy`, toast DEFERRED a pole opakování bootu). Strážce parity ve zdrojovém stromu najde každou kopii a označí nebo znovu vendoruje ty, které se odchylují, pokrývající jen widget; keyring má vlastní kadenci verify-not-copy.

---

### Veřejné API (`window.VDLU`)

| Funkce | Dělá |
|---|---|
| `init(opts)` | nakonfigurovat widget; vrací `window.VDLU` |
| `onWebUIOpen()` | volat při načtení: banner, nabídka Resume a tichá auto-aktualizace |
| `mountUpdatesPanel(el)` | vykreslit panel Updates do `el` (id řetězec nebo element) |
| `check()` | spustit `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | spustit `run` na pozadí plus toast postupu s Cancel |
| `cancel()` | vytvořit `$VDLU_DIR/cancel` (engine se zastaví v bezpečném bodě) |
| `resume()` | obnovit aktuální transakci plus toast |
| `refreshBanner()` | znovu vyhodnotit trvalý banner čekajícího restartu |

---

Viz také: [[Engine]] pro příkazy, které widget řídí, [[Quick Start]] pro úplné kroky převzetí a [[Reboot Handling]] pro to, na co banner čeká.
