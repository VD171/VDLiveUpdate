# WebUI

VDLU liefert ein optionales Drop-in-WebUI-Widget: ein kleines "Updates"-Panel für eine KernelSU- oder APatch-Root-Manager-WebUI. Es gibt einem Nutzer einen Check-Button, einen Jetzt-aktualisieren-Button, einen Live-Fortschritts-Toast mit Abbruch, ein Neustart-Banner und ein Einstellungs-Panel, alles ohne dass der Nutzer je ein Terminal berührt.

Es ist **Vanilla JavaScript**: kein Framework, kein Build-Schritt, kein CDN. Drei Dateien:

| Datei | Was es ist |
|---|---|
| `vdlu.js` | das Widget; stellt `window.VDLU` bereit |
| `vdlu.css` | die Stile für Toast, Banner und Panel (dunkles Theme, erbt die CSS-Variablen des Hosts) |
| `demo.html` | eine eigenständige Seite, die die Gerätebrücke nachbildet, sodass die gesamte UI in einem schlichten Browser läuft |

Das Widget ist völlig optional. Die [[Engine]] läuft für sich allein von Boot-Triggern aus einwandfrei; die WebUI ist nur ein freundliches Gesicht obendrauf. Siehe [[Quick Start]] für die Verdrahtung in ein Modul.

---

## Wie die UI mit der Engine spricht: die `ksu.exec`-Brücke

Das Widget tut selbst nie etwas Privilegiertes. Es baut einen Shell-Befehl und übergibt ihn an die `ksu.exec`-Brücke des Root-Managers, die ihn als root ausführt und stdout / stderr / Exit-Code zurückgibt. Alles, was das Panel zeigt, wird aus Dateien zurückgelesen, die die Engine schreibt.

Das Widget umhüllt diese Brücke in einer einzigen `exec(cmd)`-Funktion, die ein `Promise` zurückgibt:

- **löst auf** mit stdout, wenn der Befehl mit 0 beendet
- **lehnt ab** mit stderr (oder `rc=N`) andernfalls

Jeder Befehl trägt die Umgebung des Vertrags, zusammengesetzt vom Widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Ein paar konkrete Aufrufe:

- **Ein Update starten:** `update.sh run` wird im **Hintergrund** (`(... &)`) gestartet, sodass die UI nie durch einen langen Download blockiert wird.
- **Fortschritt lesen:** ein leichtes Polling (etwa einmal pro Sekunde) von `cat $VDLU_DIR/journal.json`.
- **Abbruch:** `touch $VDLU_DIR/cancel` (die Engine stoppt am nächsten sicheren Punkt).
- **Konfig:** `$VDLU_DIR/config` lesen und schreiben (key=value), unter Wahrung der Reihenfolge und unbekannter Schlüssel und nur die vom Nutzer geänderten Schlüssel berührend.

Übergibt der Host seine eigenen `exec`-, `toast`- und `confirm`-Helfer an `init()`, leitet das Widget durch die eigene serialisierte Befehlswarteschlange und Optik des Hosts, sodass es wie der Rest jener WebUI aussieht und sich verhält. Werden sie weggelassen, fällt das Widget darauf zurück, `ksu.exec` direkt aufzurufen, und injiziert seinen eigenen Mini-Toast.

---

## Der Fortschritts-Toast (mit Abbruch)

Sobald ein Update läuft, zeigt das Widget einen nicht-blockierenden Eck-Toast und pollt `journal.json`. Der Toast spiegelt den Zustandsautomaten der Engine wider:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Er rendert einen Fortschrittsbalken plus eine Zeile `phase done/total - current file - bytes` und trägt durchgehend einen **Cancel**-Button. Die Endzustände bekommen jeweils ihre eigene Behandlung:

- **DONE** -> ein grüner Toast, "vX applied - all verified".
- **PENDING_REBOOT** -> ein grüner Toast plus ein persistentes Neustart-Banner (unten).
- **ERROR** -> ein roter Toast mit dem Grund aus `journal.error` oder stderr, der Retry anbietet. Er täuscht nie Erfolg vor.
- **Cancelled** -> ein bernsteinfarbener Toast, "cancelled - N/M applied, resumable", der **Resume** anbietet.
- **DEFERRED** -> ein sanfter blauer Info-Toast, "download deferred, waiting for the allowed network". Dies ist ein harmloses Warten auf die Netzwerkrichtlinie, kein Fehler; es wird beim nächsten Check oder Boot im richtigen Netzwerk fortgesetzt.

Das Polling ist defensiv. Ein halb geschriebenes Journal (die Engine schreibt nebenläufig) wird für diesen Tick ignoriert, statt falsch geparst. Verschwindet das Journal, nachdem Fortschritt gesehen wurde, bedeutet das, dass der Commit es geleert hat: das Widget meldet DONE. Ist das Journal von Anfang an für 8 Ticks abwesend, meldet es "no response". Und friert das Journal für 20 Ticks auf denselben Werten ein, prüft das Widget den `lock.d` der Engine: lebt der Lock, ist es nur ein langsames Einzel-Blob-Fetch und der Toast wartet weiter; ist der Lock tot, ist der Lauf auf halbem Weg gestorben, sodass das Widget einen Fehler mit einem Resume-Button auftauchen lässt, statt ewig auf "updating" zu drehen.

---

## Das Neustart-Banner

Manche Dateien können auf einem Live-System nicht getauscht werden: eine `.so`, ein `/system`-Overlay, eine `sepolicy.rule`. Die Engine inszeniert diese und markiert die Transaktion `PENDING_REBOOT`. Das Widget zeigt dann ein **persistentes oberes Banner**: "Reboot to activate the new `.so` (vX)". Es bleibt, bis die inszenierten Dateien beim nächsten Boot getauscht werden. Beim Öffnen der WebUI wird das Banner aus dem Journal neu bewertet, sodass ein Nutzer, der die UI schließt und wieder öffnet, es dennoch sieht. Siehe [[Reboot Handling]] für das, was beim Boot geschieht.

Beachte, dass das Banner sich am Endzustand `PENDING_REBOOT` orientiert, nicht am `reboot_pending`-Flag (das wahr wird, sobald irgendeine `.so` in den Plan eintritt). Das verhindert, dass das Banner mitten im Lauf erscheint, bevor tatsächlich etwas inszeniert ist.

---

## Das "Updates"-Panel: unabhängige Umschalter pro Kategorie

`mountUpdatesPanel(el)` rendert das Einstellungs-Panel in ein leeres `<div>`, das der Host bereitstellt. Es hat drei Abschnitte, und jedes Steuerelement ist unabhängig und speichert für sich selbst:

**Actions**
- **Check for updates** -> führt `check` aus, zeigt das Ergebnis inline (aktuell / neuer als der Feed / Update verfügbar mit Dateianzahl und einem Reboot-Tag).
- **Update now** -> feuert `run` plus den Fortschritts-Toast.

**Automation** (unabhängige Umschalter, jeder in `config` geschrieben, sobald er umgelegt wird)
- **On WebUI open** (`auto_on_webui_open`) -> ein stilles Update ausführen, wenn die UI öffnet.
- **On reboot** (`auto_on_reboot`) -> in pre-zygote beim Boot anwenden.
- **Boot retry every (s)** und **Boot retry up to (min)** -> numerische Felder für das erneute Versuchen eines Manifest-Fetches, wenn das Gerät offline bootet.

**Source**
- `source` (die Feed-URL), `channel` (stable / canary), `profile` (trusted / hardened) und ein **Network**-Select, das auf `net_policy` abbildet (Wi-Fi + mobile / Wi-Fi only / mobile only).

Umschalter und numerische Felder speichern sofort und setzen sich visuell zurück, wenn der Schreibvorgang fehlschlägt. Die Text- und Select-Felder im Source-Abschnitt markieren sich selbst als dirty und speichern gemeinsam bei einem expliziten Save-Button. Das Panel schreibt nur je die vom Nutzer berührten Schlüssel neu, sodass alle unbekannten oder zukünftigen Konfig-Schlüssel erhalten bleiben.

### Auto-Open-Verhalten

`onWebUIOpen()` wird beim Host-Laden aufgerufen. Es bewertet das Journal (zeigt das Neustart-Banner oder bietet Resume für eine nicht-terminale Transaktion an, die eine vorherige Sitzung hinterlassen hat), dann, wenn `auto_on_webui_open=1`, führt es zuerst einen **stillen** `check()` aus. Der persistente Fortschritts-Toast und das eigentliche `run` feuern nur, wenn es einen echten Download zu erledigen gibt (`update && fetch > 0`). Ist das Gerät aktuell oder dem Feed voraus, zeigt sich das Ergebnis inline im Panel und kein Toast bleibt auf dem Bildschirm, sodass das Auto-Update so unaufdringlich ist wie der manuelle Button.

---

## i18n (Strings pro Sprache)

Jeder UI-String fällt standardmäßig auf **Englisch** zurück, was die neutrale Wahl für öffentliche mehrsprachige Module ist. Die vollständige Schlüsselkarte lebt im `DEFAULT_I18N`-Objekt in `vdlu.js` (auch als `VDLU.i18n` bereitgestellt). Ein Host überschreibt eine beliebige Teilmenge von Schlüsseln, indem er eine Karte an `init({ i18n: ... })` übergibt:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Eine **partielle** Karte ist in Ordnung: jeder fehlende Schlüssel fällt auf den englischen Standard zurück.
- Phasen- und Zustandslabels verwenden die Schlüssel `ph_<phase>` und `st_<STATE>`; der Rest sind flache Schlüssel wie `cancel`, `updateNow`.
- Eine durchgearbeitete Übersetzung (`i18n/pt-BR.js`) wird als Vorlage ausgeliefert; eine neue Sprache ist einfach eine `i18n/<lang>.js`-Datei in derselben Form, oder der Host baut die Karte aus seinem eigenen i18n-System.

---

## demo.html: die UI ohne Gerät ausführen

`demo.html` bildet die `ksu.exec`-Brücke nach, sodass genau dasselbe `vdlu.js` und `vdlu.css` in einem schlichten Browser laufen, ohne root und ohne Telefon:

```sh
xdg-open webui/demo.html
```

Der Mock simuliert `update.sh` und ein sich entwickelndes `journal.json`, und seine Buttons wechseln zwischen den Szenarien: ein Live-Update bis zu DONE, ein `reboot_pending`-Abschluss, ein Fehler auf halbem Weg und ein abbrechbarer Lauf. Es ist der schnellste Weg, die UI zu sehen und an ihr zu iterieren, und es ist das, was du prüftst, bevor du das Widget in ein Modul einbettest.

---

## Verdrahtung in ein Modul (der WebUI-Open-Trigger)

Die Host-`index.html` lädt die beiden Dateien und ruft drei Funktionen auf:

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

Der Host muss nur die Tier-2-Pfade liefern und ein leeres `<div>` für das Panel bereitstellen; der Toast und das Banner werden vom Widget in `document.body` injiziert. `onWebUIOpen()` ist der WebUI-Open-Trigger: er ist das, was das Neustart-Banner bewertet, Resume bei einer unterbrochenen Transaktion anbietet und das stille Auto-Update ausführt, wenn `auto_on_webui_open` gesetzt ist.

### Einzige Quelle, Byte für Byte neu eingebettet

`vdlu.js` und `vdlu.css` sind die **kanonische Kopie**. Ein Modul, das das Widget einbettet, bettet diese Dateien unverändert in sein `webroot/` neu ein; es bearbeitet nie seine eigene Kopie an Ort und Stelle. Ein neues Feature wird in den kanonischen Dateien geboren und fließt durch erneutes Einbetten nach unten. Das Bearbeiten einer eingebetteten Kopie erzeugt stille Drift (es ist passiert: einer veralteten Kopie fehlten `net_policy`, der DEFERRED-Toast und die Boot-Retry-Felder). Ein Paritätswächter im Quellbaum findet jede Kopie und markiert oder bettet die abweichenden neu ein, wobei er nur das Widget abdeckt; der Keyring hat seine eigene Verify-not-copy-Kadenz.

---

### Öffentliche API (`window.VDLU`)

| Funktion | Tut |
|---|---|
| `init(opts)` | das Widget konfigurieren; gibt `window.VDLU` zurück |
| `onWebUIOpen()` | beim Laden aufrufen: Banner, Resume-Angebot und stilles Auto-Update |
| `mountUpdatesPanel(el)` | das Updates-Panel in `el` rendern (Id-String oder Element) |
| `check()` | `update.sh check` ausführen; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | `run` im Hintergrund feuern plus den Fortschritts-Toast mit Cancel |
| `cancel()` | `$VDLU_DIR/cancel` erstellen (Engine stoppt an einem sicheren Punkt) |
| `resume()` | die aktuelle Transaktion fortsetzen plus einen Toast |
| `refreshBanner()` | das persistente Pending-Reboot-Banner neu bewerten |

---

Siehe auch: [[Engine]] für die Befehle, die das Widget antreibt, [[Quick Start]] für die vollständigen Übernahmeschritte und [[Reboot Handling]] für das, worauf das Banner wartet.
