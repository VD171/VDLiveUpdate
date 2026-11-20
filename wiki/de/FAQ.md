# FAQ

Kurze Antworten auf die Fragen, die am häufigsten aufkommen. Jede verlinkt auf die Seite mit
der vollständigen Geschichte.

## Was bedeutet "flashlos"? Muss ich das erste Mal trotzdem flashen?

Ja, du flashst einmal. Das Modul wird auf normalem Weg installiert (das Zip in
deinem Root-Manager flashen). "Flashlos" beschreibt jedes Update danach: VDLU lädt
nur die geänderten Dateien und wendet sie an Ort und Stelle an, sodass du nie ein
volles Zip neu flashst, nur um ein paar geänderte Zeilen auszuliefern. Siehe [[Architecture]].

## Braucht ein Update einen Neustart?

Meist nein. Die meisten Dateien (deine WebUI, Binaries, Bibliotheken, Konfigs, `module.prop`)
sind **live**-Klasse und werden atomar ohne Neustart angewendet. Nur Dateien der Reboot-Klasse
(eine `.so` unter `zygisk/`, ein `/system/**`-Overlay, eine `*.rule`-sepolicy-Datei) werden
**inszeniert** und beim nächsten Boot eingetauscht, weil ein laufender Prozess den Live-Inode bereits
gemappt hat. Wenn das geschieht, zeigt die WebUI ein persistentes "reboot to
activate"-Banner. Siehe [[Reboot Handling]].

## Ist es sicher, wenn der Feed MITM'd oder vergiftet ist?

Ja, auf einem `hardened`-Feed. Jedes Manifest-Feld wird als feindliche Eingabe behandelt.
Das Manifest muss eine gültige ed25519-Signatur über seine kanonische Form tragen, und
`validate_plan()` läuft fail-closed **vor jedem Download**: es verwirft das gesamte
Manifest bei einem absoluten oder `..`-Pfad, einem `sha256`, der nicht 64 Hex-Zeichen hat,
oder einem ungültigen Modus, einer ungültigen Klasse oder Kodierung. Das Manifest ist auch an deine Modul-
Id gebunden, sodass ein gültig signierter Feed für ein anderes Modul nicht an seiner Stelle serviert werden kann.
Der sha256 jedes Blobs wird nach dem Download unabhängig vom Profil verifiziert. Siehe
[[Security and Trust Model]].

## Was braucht es auf dem Gerät (Abhängigkeiten)?

Sehr wenig. Reines POSIX sh (mksh / busybox / toybox) plus toybox' `sha256sum`,
`gzip`, `base64` und `date`; den eingebetteten `ed25519-mini`-Verifizierer; und, nur für
eine `https`-Quelle, ein statisches `curl`, das einmal geladen und in Tier-2 gecacht wird.
Eine `file://`-Quelle braucht überhaupt kein curl. Es gibt **keine Abhängigkeit von `jq`**: die
Engine parst JSON mit einem gron-artigen Flattener, geschrieben in `awk`. Siehe [[Engine]].

## Ist openssl auf dem Gerät erforderlich?

Nein. `openssl` wird nur auf der PC-/Release-Seite verwendet (`vdlu-keygen`, `vdlu-sign`).
Auf dem Gerät nutzt die Signaturprüfung das schlanke eingebettete `ed25519-mini`-
Binary, das einen ROHEN 32-Byte-öffentlichen-Schlüssel liest. Siehe [[Producer]] und
[[Security and Trust Model]].

## Wie rotiere ich den Signaturschlüssel?

Erzeuge ein neues Schlüsselpaar mit `vdlu-keygen`, füge den neuen ROHEN 32-Byte-öffentlichen-Schlüssel zum
Geräte-Keyring neben dem vorherigen hinzu und beginne mit dem neuen `key_id` zu signieren.
Das Gerät wählt `<keyring>/<key_id>.pub` nach dem `key_id` des Manifests,
sodass keine Engine-Änderung nötig ist. Sowohl den aktuellen als auch den vorherigen öffentlichen Schlüssel auszuliefern
bedeutet, dass ein rotierter Schlüssel nie ältere Installationen kaputt macht. Weil eine Rotation mehr als einen Schlüssel im Keyring hinterlässt, musst du auch fixieren, welcher Schlüssel ein Modul-Update signieren darf: setze die `key_id`-Konfig (kommagetrennt während des Rotationsfensters). Ein Keyring mit einem einzigen Schlüssel fixiert automatisch und braucht keine Konfig. Siehe [[Security and Trust Model]].

## hardened vs trusted - welches verwende ich?

Verwende `hardened` für jeden öffentlichen Feed (über `https` serviert, z. B. GitHub Pages).
Es macht die Signatur zur Pflicht und blockiert Downgrades. Verwende `trusted` nur für eine
private `file://`- oder SSH-inszenierte Quelle, die du bereits kontrollierst, wo die Signatur
Best-Effort ist (der Hash jedes Blobs wird dennoch geprüft). Im Zweifel verwende `hardened`:
es ist der fail-closed-Standard, und jeder nicht-`trusted`-Wert wird als
`hardened` behandelt. Siehe [[Security and Trust Model]].

## Was, wenn ein Blob manipuliert oder das Manifest fehlerhaft ist?

Das Update bricht ab und nichts wird angewendet. Ein fehlerhaftes Manifest wird ganz
von `validate_plan()` vor jedem Fetch verworfen. Ein Blob, dessen sha256 nicht zum
Manifest passt, wird abgelehnt; drei Fehlschläge beim selben Blob brechen die Fetch-Phase ab, ohne dass
etwas angewendet wird. Bei jedem harten Fehler zeichnet das Journal `ERROR` auf und das Modul
wird intakt gelassen. Siehe [[Engine]].

## Kann ein Update meine Dateien löschen oder das Gerät kaputt machen?

Das Risiko ist durch Design eingegrenzt. Überschriebene und gelöschte Dateien werden zuerst nach
`rollback/<version>/` gesichert, und `apply` bricht ab, statt ohne ein erfolgreiches
Backup zu überschreiben. Löschungen laufen nur, wenn eine Transaktion `DONE` erreicht, nie
während ein Neustart noch aussteht. Ein fehlgeschlagenes Apply setzt die Live-Dateien zurück, die es bereits
geschrieben hat. Pfade werden vor der Verwendung auf Containment innerhalb des Modulverzeichnisses validiert,
sodass ein Manifest nicht außerhalb des Baums schreiben oder löschen kann. Siehe [[Engine]] und
[[Security and Trust Model]].

## Funktioniert es auf KernelSU UND Magisk UND APatch?

Ja. VDLU ist schlichtes POSIX sh plus eine WebUI, eingebettet in das Modul, sodass es auf
KernelSU, APatch und Magisk gleichermaßen läuft. Es nutzt die WebUI-Brücke des Root-Managers
(`ksu.exec`), um die Engine anzutreiben und den Fortschritt zu pollen. Siehe [[Architecture]] und
[[WebUI]].

## Wie groß ist der geräteseitige Fußabdruck?

Klein. Die Engine ist Skripte; die einzigen Binaries sind der Per-ABI-`ed25519-mini`-
Verifizierer (winzig) und, für eine `https`-Quelle, ein statisches `curl` (~1MB), das
einmal geladen und gecacht wird. Ein Modul, das bereits sein eigenes `curl` bündelt, nutzt es wieder
und fügt überhaupt keinen Download hinzu. Der Tier-2-Blob-Cache hält verifizierten Inhalt plus
die letzten 3 Rollback-Versionen. Siehe [[Engine]] und [[Architecture]].
