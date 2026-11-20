# WebUI

VDLU levert een optionele drop-in WebUI-widget mee: een klein "Updates"-paneel voor een KernelSU- of APatch-root-manager-WebUI. Het geeft een gebruiker een Check-knop, een Update now-knop, een live voortgangstoast met annuleren, een herstartbanner en een instellingenpaneel, allemaal zonder dat de gebruiker ooit een terminal aanraakt.

Het is **vanilla JavaScript**: geen framework, geen build-stap, geen CDN. Drie bestanden:

| Bestand | Wat het is |
|---|---|
| `vdlu.js` | de widget; stelt `window.VDLU` beschikbaar |
| `vdlu.css` | de stijlen voor de toast, banner en het paneel (donker thema, erft de CSS-variabelen van de host) |
| `demo.html` | een standalone pagina die de apparaatbrug mockt zodat de hele UI in een gewone browser draait |

De widget is volledig optioneel. De [[Engine]] draait prima op zichzelf vanaf boot-triggers; de WebUI is er slechts een vriendelijk gezicht bovenop. Zie [[Quick Start]] voor het bedraden ervan in een module.

---

## Hoe de UI met de engine praat: de `ksu.exec`-brug

De widget doet nooit zelf iets geprivilegieerds. Het bouwt een shellcommando en overhandigt het aan de `ksu.exec`-brug van de root-manager, die het als root draait en stdout / stderr / exitcode teruggeeft. Alles wat het paneel toont wordt teruggelezen uit bestanden die de engine schrijft.

De widget wikkelt die brug in een enkele `exec(cmd)`-functie die een `Promise` teruggeeft:

- **resolvet** met stdout wanneer het commando met 0 afsluit
- **rejectet** met stderr (of `rc=N`) anders

Elk commando draagt de omgeving van het contract, samengesteld door de widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Een paar concrete aanroepen:

- **Een update starten:** `update.sh run` wordt op de **achtergrond** gestart (`(... &)`) zodat de UI nooit wordt geblokkeerd door een lange download.
- **Voortgang lezen:** een lichte poll (ongeveer eens per seconde) van `cat $VDLU_DIR/journal.json`.
- **Annuleren:** `touch $VDLU_DIR/cancel` (de engine stopt bij het volgende veilige punt).
- **Config:** lees en schrijf `$VDLU_DIR/config` (key=value), met behoud van volgorde en onbekende sleutels en alleen de sleutels aanraken die de gebruiker wijzigde.

Als de host zijn eigen `exec`-, `toast`- en `confirm`-helpers aan `init()` doorgeeft, routeert de widget via de eigen geserialiseerde commandowachtrij en visuals van de host, zodat het eruitziet en zich gedraagt als de rest van die WebUI. Als ze worden weggelaten, valt de widget terug op het direct aanroepen van `ksu.exec` en injecteert zijn eigen mini-toast.

---

## De voortgangstoast (met annuleren)

Zodra een update draait, toont de widget een niet-blokkerende hoektoast en pollt `journal.json`. De toast weerspiegelt de toestandsmachine van de engine:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Het rendert een voortgangsbalk plus een regel `phase done/total - current file - bytes`, en draagt een **Cancel**-knop gedurende het geheel. De eindtoestanden krijgen elk hun eigen behandeling:

- **DONE** -> een groene toast, "vX applied - all verified".
- **PENDING_REBOOT** -> een groene toast plus een aanhoudende herstartbanner (hieronder).
- **ERROR** -> een rode toast met de reden uit `journal.error` of stderr, met Retry. Het veinst nooit succes.
- **Cancelled** -> een amberkleurige toast, "cancelled - N/M applied, resumable", met **Resume**.
- **DEFERRED** -> een zachte blauwe info-toast, "download deferred, waiting for the allowed network". Dit is een onschuldige netwerkbeleid-wachttijd, geen fout; het hervat bij de volgende check of boot op het juiste netwerk.

De poll is defensief. Een half geschreven journal (de engine schrijft gelijktijdig) wordt voor die tick genegeerd in plaats van verkeerd geparst. Als het journal afwezig raakt nadat er voortgang is gezien, betekent dat dat de commit het heeft gewist: de widget rapporteert DONE. Als het journal vanaf het begin 8 ticks lang afwezig is, rapporteert het "no response". En als het journal 20 ticks lang op dezelfde waarden blijft hangen, controleert de widget de `lock.d` van de engine: als de lock in leven is, is het slechts een trage fetch van één blob en blijft de toast wachten; als de lock dood is, is de run halverwege gestorven, dus laat de widget een fout zien met een Resume-knop in plaats van eindeloos op "updating" te blijven draaien.

---

## De herstartbanner

Sommige bestanden kunnen niet op een live systeem worden omgewisseld: een `.so`, een `/system`-overlay, een `sepolicy.rule`. De engine faseert die en markeert de transactie `PENDING_REBOOT`. De widget toont dan een **aanhoudende topbanner**: "Reboot to activate the new `.so` (vX)". Die blijft tot de gefaseerde bestanden bij de volgende boot worden omgewisseld. Bij het openen van de WebUI wordt de banner opnieuw geevalueerd vanuit het journal, zodat een gebruiker die de UI sluit en heropent hem nog steeds ziet. Zie [[Reboot Handling]] voor wat er bij boot gebeurt.

Merk op dat de banner afgaat op de eindtoestand `PENDING_REBOOT`, niet op de `reboot_pending`-vlag (die op true gaat zodra een `.so` het plan binnenkomt). Dat voorkomt dat de banner halverwege een run verschijnt voordat er daadwerkelijk iets is gefaseerd.

---

## Het "Updates"-paneel: onafhankelijke toggles per categorie

`mountUpdatesPanel(el)` rendert het instellingenpaneel in een lege `<div>` die de host levert. Het heeft drie secties, en elke besturing is onafhankelijk en bewaart op zichzelf:

**Actions**
- **Check for updates** -> draait `check`, toont het resultaat inline (up-to-date / nieuwer dan de feed / update beschikbaar met bestandsaantal en een reboot-tag).
- **Update now** -> vuurt `run` plus de voortgangstoast af.

**Automation** (onafhankelijke toggles, elk naar `config` geschreven op het moment dat die wordt omgezet)
- **On WebUI open** (`auto_on_webui_open`) -> draai een stille update wanneer de UI opent.
- **On reboot** (`auto_on_reboot`) -> pas toe in pre-zygote bij boot.
- **Boot retry every (s)** en **Boot retry up to (min)** -> numerieke velden voor het opnieuw proberen van een manifest-fetch wanneer het apparaat offline boot.

**Source**
- `source` (de feed-URL), `channel` (stable / canary), `profile` (trusted / hardened), en een **Network**-select die mapt naar `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Toggles en numerieke velden bewaren direct en draaien visueel terug als de schrijfbewerking mislukt. De tekst- en select-velden in de Source-sectie markeren zichzelf als dirty en bewaren samen op een expliciete Save-knop. Het paneel herschrijft alleen ooit de sleutels die de gebruiker aanraakte, zodat alle onbekende of toekomstige config-sleutels behouden blijven.

### Auto-open-gedrag

`onWebUIOpen()` wordt aangeroepen bij het laden van de host. Het evalueert het journal (toont de herstartbanner of biedt Resume aan voor een niet-eindige transactie die door een vorige sessie is achtergelaten), en draait daarna, als `auto_on_webui_open=1`, eerst een **stille** `check()`. De aanhoudende voortgangstoast en de daadwerkelijke `run` vuren alleen af wanneer er echt een download te doen is (`update && fetch > 0`). Als het apparaat up-to-date is of voorloopt op de feed, verschijnt het resultaat inline in het paneel en blijft er geen toast op het scherm achter, zodat de auto-update even onopdringerig is als de handmatige knop.

---

## i18n (strings per taal)

Elke UI-string valt standaard terug op **Engels**, wat de neutrale keuze is voor publieke meertalige modules. De volledige key-map leeft in het `DEFAULT_I18N`-object in `vdlu.js` (ook beschikbaar als `VDLU.i18n`). Een host overschrijft een willekeurige subset van sleutels door een map door te geven aan `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Een **gedeeltelijke** map is prima: elke ontbrekende sleutel valt terug op de Engelse standaard.
- Fase- en toestandslabels gebruiken de sleutels `ph_<phase>` en `st_<STATE>`; de rest zijn platte sleutels zoals `cancel`, `updateNow`.
- Een uitgewerkte vertaling (`i18n/pt-BR.js`) levert mee als sjabloon; een nieuwe taal is slechts een `i18n/<lang>.js`-bestand in dezelfde vorm, of de host bouwt de map uit zijn eigen i18n-systeem.

---

## demo.html: draai de UI zonder apparaat

`demo.html` mockt de `ksu.exec`-brug zodat exact dezelfde `vdlu.js` en `vdlu.css` in een gewone browser draaien, zonder root en zonder telefoon:

```sh
xdg-open webui/demo.html
```

De mock simuleert `update.sh` en een evoluerend `journal.json`, en de knoppen wisselen tussen de scenario's: een live update tot aan DONE, een `reboot_pending`-afronding, een fout halverwege, en een annuleerbare run. Het is de snelste manier om de UI te zien en erop te itereren, en het is wat je controleert voordat je de widget in een module vendort.

---

## Het bedraden in een module (de WebUI-open-trigger)

De host-`index.html` laadt de twee bestanden en roept drie functies aan:

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

De host hoeft alleen de Tier-2-paden te leveren en één lege `<div>` voor het paneel toe te wijzen; de toast en banner worden door de widget in `document.body` geinjecteerd. `onWebUIOpen()` is de WebUI-open-trigger: het is wat de herstartbanner evalueert, Resume aanbiedt bij een onderbroken transactie, en de stille auto-update draait wanneer `auto_on_webui_open` is gezet.

### Enkele bron, byte voor byte opnieuw gevendord

`vdlu.js` en `vdlu.css` zijn de **canonieke kopie**. Een module die de widget inbedt vendort deze bestanden ongewijzigd opnieuw in zijn `webroot/`; het bewerkt nooit zijn eigen kopie ter plekke. Een nieuwe functie wordt geboren in de canonieke bestanden en vloeit omlaag via opnieuw vendoren. Een gevendorde kopie bewerken produceert stille drift (het is gebeurd: een verschaalde kopie miste `net_policy`, de DEFERRED-toast en de boot-retry-velden). Een pariteitsbewaker in de bronboom vindt elke kopie en markeert of hervendort de kopieën die afwijken, en dekt alleen de widget; de keyring heeft zijn eigen verify-not-copy-cadans.

---

### Publieke API (`window.VDLU`)

| Functie | Doet |
|---|---|
| `init(opts)` | configureer de widget; geeft `window.VDLU` terug |
| `onWebUIOpen()` | aanroepen bij laden: banner, Resume-aanbod, en stille auto-update |
| `mountUpdatesPanel(el)` | rendert het Updates-paneel in `el` (id-string of element) |
| `check()` | draait `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | vuurt `run` op de achtergrond af plus de voortgangstoast met Cancel |
| `cancel()` | maakt `$VDLU_DIR/cancel` (engine stopt bij een veilig punt) |
| `resume()` | hervat de huidige transactie plus een toast |
| `refreshBanner()` | her-evalueer de aanhoudende pending-reboot-banner |

---

Zie ook: [[Engine]] voor de commando's die de widget aanstuurt, [[Quick Start]] voor volledige adoptiestappen, en [[Reboot Handling]] voor waar de banner op wacht.
