# Contributing

Beiträge sind willkommen. VDLU ist eine flashlose, inkrementelle Selbstaktualisierungs-Engine,
eingebettet in KernelSU- / APatch- / Magisk-Module. Diese Seite ist der praktische Entwickler-
Workflow; für die Art, wie die Teile zusammenpassen, lies zuerst [[Architecture]], [[Engine]] und
[[Producer]].

## Nichts kompiliert

VDLU besteht aus Skripten (POSIX sh, ein wenig Python auf der Release-Seite, Vanilla JS für die
WebUI), sodass es keinen Build-Schritt gibt. Du verifizierst eine Änderung, indem du die Pipeline
end-to-end ausführst und jedes Teil statisch prüfst.

## Nahtvertrag zuerst

Der Schnittstellenvertrag zwischen den Komponenten (die CLI-Signaturen, Dateinamen und
JSON-Schlüssel, die von der Engine, dem Producer und der WebUI geteilt werden) ist das **Gesetz der
Konvergenz**. Behandle ihn als unveränderlich. Wenn deine Änderung die
Producer-zu-Engine-Naht berührt (Manifest-Schema, Journal-Schema, Konfig-Schlüssel, die
Signatur-/Kanonisierungsregel), **richte zuerst den Schnittstellenvertrag aus**, dann
ändere den Code auf beiden Seiten passend. Eine Änderung auf einer Seite der Naht ohne
die andere bricht stillschweigend Adopter. Siehe [[Producer]] für die Kanonisierungs-
regel, auf die sich Signierer und Verifizierer Byte für Byte einigen müssen.

## End-to-end testen vor einem PR

Führe den Producer und die Engine zusammen auf einem Wegwerfbaum aus, genauso wie das Release
eines Adopters es tut:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Dann prüfe jede Komponente statisch:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Und öffne `webui/demo.html` in einem Browser: es bildet die Root-Manager-Brücke
(`ksu.exec`) nach, sodass du das Updates-Panel, den Fortschritts-Toast, Abbruch
und das Neustart-Banner ohne Gerät ausprobieren kannst. Siehe [[WebUI]].

## Hausregeln

- **POSIX sh auf dem Gerät.** Keine Bashismen über `local` hinaus, und kein `jq`. Es muss
  auf toybox / busybox laufen.
- **Sicherheit ist nicht verhandelbar.** Jedes Manifest-Feld ist feindliche Eingabe;
  `validate_plan()` bleibt fail-closed, und der private Signaturschlüssel berührt nie
  CI oder ein Gerät. Lockere keine Prüfung, um einen Test zu bestehen.
- **Rigorosität beim Fehler.** Halte die Transaktion wiederaufnehmbar: nichts meldet "done"
  ohne ein passendes erneutes Hashen, nichts wird ohne ein Backup überschrieben, und
  Applies bleiben atomar.
- **Immer Release-Qualität.** Halte Kommentare knapp; keine überflüssigen Kommentare.
- **Eine logische Änderung pro PR.** Sage, was sich geändert hat und warum.

## Issues einreichen

Öffne ein Issue, das beschreibt, was du getan hast, was du erwartet hast und was passiert ist.
Für einen Bug, füge die Modul-Id, das Quellprofil (`hardened` oder `trusted`),
den `update.sh`-Befehl, den du ausgeführt hast, und das relevante `journal.json` hinzu (es zeichnet die
Phase, den Zustand und den Fehler auf). Für ein Feature, sage, welche Komponente es berührt (Engine,
Producer oder WebUI), sodass die Nahtwirkung von vornherein klar ist.
