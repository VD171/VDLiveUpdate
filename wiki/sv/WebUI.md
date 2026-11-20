# WebUI

VDLU levereras med en valfri inbyggbar WebUI-widget: en liten "Updates"-panel för ett KernelSU- eller APatch-root-hanterar-WebUI. Den ger användaren en Check-knapp, en Update now-knapp, en levande förloppstoast med avbryt, en omstartsbanner och en inställningspanel, allt utan att användaren någonsin vidrör en terminal.

Den är **ren JavaScript**: inget ramverk, inget byggsteg, ingen CDN. Tre filer:

| Fil | Vad det är |
|---|---|
| `vdlu.js` | widgeten; exponerar `window.VDLU` |
| `vdlu.css` | stilarna för toasten, bannern och panelen (mörkt tema, ärver värdens CSS-variabler) |
| `demo.html` | en fristående sida som härmar enhetsbryggan så att hela gränssnittet körs i en vanlig webbläsare |

Widgeten är helt valfri. [[Engine]] körs fint på egen hand från boot-utlösare; WebUI är bara ett vänligt ansikte ovanpå den. Se [[Quick Start]] för att koppla in den i en modul.

---

## Hur gränssnittet talar med motorn: `ksu.exec`-bryggan

Widgeten gör aldrig något privilegierat själv. Den bygger ett skalkommando och överlämnar det till root-hanterarens `ksu.exec`-brygga, som kör det som root och returnerar stdout / stderr / returkod. Allt panelen visar läses tillbaka från filer motorn skriver.

Widgeten omsluter den bryggan i en enda `exec(cmd)`-funktion som returnerar ett `Promise`:

- **resolvar** med stdout när kommandot avslutas med 0
- **rejektar** med stderr (eller `rc=N`) annars

Varje kommando bär kontraktets miljö, sammansatt av widgeten:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Några konkreta anrop:

- **Starta en uppdatering:** `update.sh run` startas i **bakgrunden** (`(... &)`) så att gränssnittet aldrig blockeras av en lång nedladdning.
- **Läs förlopp:** en lätt pollning (ungefär en gång per sekund) av `cat $VDLU_DIR/journal.json`.
- **Avbryt:** `touch $VDLU_DIR/cancel` (motorn stannar vid nästa säkra punkt).
- **Konfiguration:** läs och skriv `$VDLU_DIR/config` (key=value), bevara ordning och okända nycklar och vidrör bara de nycklar användaren ändrade.

Om värden skickar sina egna `exec`-, `toast`- och `confirm`-hjälpfunktioner till `init()`, dirigerar widgeten genom värdens egen serialiserade kommandokö och visuella element, så att den ser ut och beter sig som resten av det WebUI:t. Om de utelämnas faller widgeten tillbaka på att anropa `ksu.exec` direkt och injicerar sin egen mini-toast.

---

## Förloppstoasten (med avbryt)

När en uppdatering väl körs visar widgeten en icke-blockerande hörntoast och pollar `journal.json`. Toasten speglar motorns tillståndsmaskin:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Den renderar en förloppsindikator plus en rad med `phase done/total - current file - bytes`, och bär en **Cancel**-knapp hela vägen. Sluttillstånden får vart och ett sin egen behandling:

- **DONE** -> en grön toast, "vX applied - all verified".
- **PENDING_REBOOT** -> en grön toast plus en bestående omstartsbanner (nedan).
- **ERROR** -> en röd toast med orsaken från `journal.error` eller stderr, som erbjuder Retry. Den fejkar aldrig framgång.
- **Cancelled** -> en gul toast, "cancelled - N/M applied, resumable", som erbjuder **Resume**.
- **DEFERRED** -> en mjuk blå info-toast, "download deferred, waiting for the allowed network". Detta är en ofarlig väntan på grund av nätverkspolicyn, inte ett fel; det återupptas vid nästa kontroll eller boot på rätt nätverk.

Pollningen är defensiv. En halvskriven journal (motorn skriver samtidigt) ignoreras för den tickningen i stället för att feltolkas. Om journalen försvinner efter att förlopp setts betyder det att committen rensade den: widgeten rapporterar DONE. Om journalen är frånvarande från start i 8 tickningar rapporterar den "no response". Och om journalen fryser på samma värden i 20 tickningar kontrollerar widgeten motorns `lock.d`: om låset lever är det bara en långsam hämtning av en enda blob och toasten fortsätter vänta; om låset är dött dog körningen mitt i, så widgeten lyfter fram ett fel med en Resume-knapp i stället för att snurra på "updating" för alltid.

---

## Omstartsbannern

Vissa filer kan inte bytas ut på ett aktivt system: en `.so`, ett `/system`-överlägg, en `sepolicy.rule`. Motorn förbereder dessa och markerar transaktionen `PENDING_REBOOT`. Widgeten visar sedan en **bestående toppbanner**: "Reboot to activate the new `.so` (vX)". Den stannar tills de förberedda filerna byts in vid nästa boot. Vid WebUI-öppning omvärderas bannern från journalen, så att en användare som stänger och öppnar gränssnittet igen fortfarande ser den. Se [[Reboot Handling]] för vad som händer vid boot.

Notera att bannern utgår från sluttillståndet `PENDING_REBOOT`, inte från `reboot_pending`-flaggan (som blir sann så fort någon `.so` kommer in i planen). Det håller bannern från att dyka upp mitt i körningen innan något faktiskt är förberett.

---

## "Updates"-panelen: oberoende växlingar per kategori

`mountUpdatesPanel(el)` renderar inställningspanelen in i en tom `<div>` som värden tillhandahåller. Den har tre sektioner, och varje kontroll är oberoende och sparar på egen hand:

**Åtgärder**
- **Check for updates** -> kör `check`, visar resultatet inline (aktuell / nyare än flödet / uppdatering tillgänglig med filantal och en omstartstagg).
- **Update now** -> avfyrar `run` plus förloppstoasten.

**Automatisering** (oberoende växlingar, var och en skriven till `config` i det ögonblick den vänds)
- **On WebUI open** (`auto_on_webui_open`) -> kör en tyst uppdatering när gränssnittet öppnas.
- **On reboot** (`auto_on_reboot`) -> tillämpa före zygote vid boot.
- **Boot retry every (s)** och **Boot retry up to (min)** -> numeriska fält för att försöka hämta ett manifest igen när enheten bootar offline.

**Källa**
- `source` (flödets URL), `channel` (stable / canary), `profile` (trusted / hardened), och ett **Network**-val som mappar till `net_policy` (Wi-Fi + mobildata / endast Wi-Fi / endast mobildata).

Växlingar och numeriska fält sparar omedelbart och återställs visuellt om skrivningen misslyckas. Text- och valfälten i Källa-sektionen markerar sig själva som ändrade och sparar tillsammans vid en uttrycklig Save-knapp. Panelen skriver bara någonsin om de nycklar användaren vidrörde, så alla okända eller framtida konfigurationsnycklar bevaras.

### Beteende vid automatisk öppning

`onWebUIOpen()` anropas vid värdens laddning. Den utvärderar journalen (visar omstartsbannern eller erbjuder Resume för en icke-slutlig transaktion lämnad av en tidigare session), och kör sedan, om `auto_on_webui_open=1`, en **tyst** `check()` först. Den bestående förloppstoasten och själva `run` avfyras bara när det finns en verklig nedladdning att göra (`update && fetch > 0`). Om enheten är aktuell eller ligger före flödet visas resultatet inline i panelen och ingen toast lämnas på skärmen, så att den automatiska uppdateringen är lika obetydlig som den manuella knappen.

---

## i18n (strängar per språk)

Varje gränssnittssträng har **engelska** som standard, vilket är det neutrala valet för publika flerspråkiga moduler. Den fullständiga nyckelkartan lever i `DEFAULT_I18N`-objektet i `vdlu.js` (också exponerad som `VDLU.i18n`). En värd åsidosätter valfri delmängd av nycklar genom att skicka en karta till `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- En **partiell** karta går bra: varje saknad nyckel faller tillbaka på den engelska standarden.
- Fas- och tillståndsetiketter använder nycklarna `ph_<phase>` och `st_<STATE>`; resten är platta nycklar som `cancel`, `updateNow`.
- En genomgången översättning (`i18n/pt-BR.js`) levereras som en mall; ett nytt språk är bara en `i18n/<lang>.js`-fil i samma form, eller så bygger värden kartan från sitt eget i18n-system.

---

## demo.html: kör gränssnittet utan någon enhet

`demo.html` härmar `ksu.exec`-bryggan så att exakt samma `vdlu.js` och `vdlu.css` körs i en vanlig webbläsare, utan root och utan telefon:

```sh
xdg-open webui/demo.html
```

Imitationen simulerar `update.sh` och en `journal.json` som utvecklas, och dess knappar växlar mellan scenarierna: en aktiv uppdatering hela vägen till DONE, en `reboot_pending`-avslutning, ett fel mitt i, och en avbrytbar körning. Det är det snabbaste sättet att se och iterera på gränssnittet, och det är vad du kontrollerar innan du bäddar in widgeten i en modul.

---

## Att koppla in det i en modul (WebUI-öppningsutlösaren)

Värdens `index.html` laddar de två filerna och anropar tre funktioner:

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

Värden behöver bara tillhandahålla Tier-2-sökvägarna och allokera en tom `<div>` för panelen; toasten och bannern injiceras i `document.body` av widgeten. `onWebUIOpen()` är WebUI-öppningsutlösaren: det är den som utvärderar omstartsbannern, erbjuder Resume vid en avbruten transaktion, och kör den tysta automatiska uppdateringen när `auto_on_webui_open` är satt.

### En enda källa, återinbäddad byte för byte

`vdlu.js` och `vdlu.css` är den **kanoniska kopian**. En modul som bäddar in widgeten återinbäddar dessa filer oförändrade in i sin `webroot/`; den redigerar aldrig sin egen kopia på plats. En ny funktion föds i de kanoniska filerna och flödar ner genom återinbäddning. Att redigera en inbäddad kopia ger tyst avdrift (det har hänt: en föråldrad kopia saknade `net_policy`, DEFERRED-toasten och boot-återförsöksfälten). En paritetsväktare i källträdet hittar varje kopia och flaggar eller återinbäddar de som avviker, och täcker bara widgeten; nyckelringen har sin egen verifiera-inte-kopiera-kadens.

---

### Publikt API (`window.VDLU`)

| Funktion | Gör |
|---|---|
| `init(opts)` | konfigurera widgeten; returnerar `window.VDLU` |
| `onWebUIOpen()` | anropa vid laddning: banner, Resume-erbjudande och tyst automatisk uppdatering |
| `mountUpdatesPanel(el)` | rendera Updates-panelen in i `el` (id-sträng eller element) |
| `check()` | kör `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | avfyra `run` i bakgrunden plus förloppstoasten med Cancel |
| `cancel()` | skapa `$VDLU_DIR/cancel` (motorn stannar vid en säker punkt) |
| `resume()` | återuppta den aktuella transaktionen plus en toast |
| `refreshBanner()` | omvärdera den bestående väntande-omstart-bannern |

---

Se även: [[Engine]] för kommandona widgeten driver, [[Quick Start]] för fullständiga införandesteg, och [[Reboot Handling]] för vad bannern väntar på.
