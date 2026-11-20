# Reboot Handling

Der ganze Sinn von VDLU ist, ein Modul zu aktualisieren, ohne es neu zu flashen, und, wo immer möglich, ohne überhaupt neu zu starten. Die meisten Dateien in einem Modul können ersetzt werden, während das Gerät läuft. Ein paar können es wirklich nicht, weil der Kernel oder der Zygote-Prozess sie bereits gemappt hat und eine Änderung erst beim nächsten Boot bemerkt.

VDLUs Aufgabe ist, diese zwei Gruppen automatisch auseinanderzuhalten, alles, was es sicher kann, **live** anzuwenden und nur die wirklich boot-gebundenen Dateien auf einen Neustart zu verschieben, den es klar markiert. Diese Seite erklärt, wie.

Für die Engine-Mechanik darunter siehe [[Engine]]. Für das große Bild siehe [[Architecture]].

## Warum nicht einfach jedes Mal neu starten

Ein Neustart ist das Teuerste, das ein Update von jemandem verlangen kann. Er unterbricht, was auch immer sie tun, er dauert eine Minute oder mehr, und er traniert Menschen, Updates zu fürchten. Ein guter inkrementeller Updater sollte sich unsichtbar anfühlen: du tippst auf Update, ein paar Dateien ändern sich unter dem laufenden System, und du bist bereits auf der neuen Version.

Also kehrt VDLU die übliche Annahme um. Der Standard ist live. Eine Datei wird nur dann auf einen Neustart verschoben, wenn sie nachweislich eine der kernel- oder zygote-gebundenen Arten ist, und selbst dann wartet nur diese Datei. Alles um sie herum aktualisiert sich weiterhin sofort.

## Die drei Klassen

Jeder Datei im Feed wird eine Klasse zugewiesen. Der Producer kann sie im Manifest explizit setzen, aber in der Praxis wird die Klasse aus dem Pfad abgeleitet, und die Engine wird eine Datei nur je in Richtung `reboot` hochstufen, nie in Richtung `live` herabstufen. Die Klassen sind:

**LIVE** ist der häufige Fall: Web-UI-Assets, Binaries, Skripte, die bei Bedarf gelesen werden, Konfig-Dateien, `module.prop` und alles andere, das nicht von den Regeln unten erfasst wird. Eine Live-Datei wird gesichert und dann atomar über das Ziel umbenannt, während das System läuft. Kein Neustart, und die Änderung ist in dem Moment wirksam, in dem das Rename landet.

**SOFT** sind die eigenen Lebenszyklus-Skripte des Moduls: `service.sh`, `post-fs-data.sh` und `boot-completed.sh`. Diese werden genau wie LIVE-Dateien live angewendet, sodass die neue Kopie bereits auf der Platte ist. Der Grund, warum sie ihre eigene Klasse bekommen, ist, dass das laufende System die alte Kopie diesen Boot bereits ausgeführt hat; die neue läuft einfach nächsten Boot, ohne Inszenierung und ohne Banner. Es gibt nichts zu verschieben, nur eine natürliche Übergabe.

**REBOOT-hard** ist der kleine Satz, der sich unter einem laufenden System nicht ändern kann:

- native Bibliotheken, `*.so` (alles unter einem `zygisk/`-Pfad), weil zygote sie beim Start in jede App mappt;
- `/system`-Overlay-Dateien, weil das Overlay beim Boot gemountet wird;
- `sepolicy.rule`-Dateien, weil die SELinux-Policy früh geladen wird.

Eine REBOOT-hard-Datei wird nie über ihren Live-Inode geschrieben, während das System läuft. Eine `.so` zu überschreiben, die zygote bereits gemappt hat, ist, wie man Abstürze und inkonsistenten Zustand bekommt. Stattdessen wird der neue Inhalt neben das Zustandsverzeichnis **inszeniert** und beim nächsten Boot eingetauscht, bevor irgendetwas ihn mappen kann.

## Pfad zu Klasse, auf einen Blick

Die Engine leitet die Klasse aus dem Pfad so ab:

| Pfadmuster | Klasse | Angewendet |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (die `.so`-Dateien) | REBOOT-hard | inszeniert, pre-zygote beim Boot getauscht |
| `system/**` (Overlay) | REBOOT-hard | inszeniert, beim Boot getauscht |
| `*.rule` (sepolicy) | REBOOT-hard | inszeniert, beim Boot getauscht |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | live geschrieben, läuft nächsten Boot |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, alles andere | LIVE | live geschrieben, sofort wirksam |

Das Manifest kann eine explizite `class` pro Datei tragen, aber die abgeleitete Klasse wirkt als Untergrenze: wenn eine Datei nach ihrem Pfad REBOOT-hard aussieht, wird sie als REBOOT-hard behandelt, selbst wenn das Manifest etwas anderes sagt. Das hält einen falsch beschrifteten Feed davon ab, je zu versuchen, eine `.so` hot-zu-tauschen.

## Wie ein Lauf beide Gruppen auf einmal handhabt

Während eines normalen `run` (der DIFF-zu-FETCH-zu-APPLY-zu-COMMIT-Zyklus, beschrieben in [[Engine]]) werden die zwei Gruppen in derselben Transaktion gehandhabt:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Also bist du nach einem Lauf, der eine `.so` berührt hat, bereits auf der neuen Version für jede Live-Datei, und nur die inszenierten Teile warten. Das Journal meldet `reboot_pending`, und die WebUI zeigt ein persistentes Banner, das zu einem Neustart einlädt, um die inszenierten Dateien zu aktivieren. Es gibt kein falsches "done": ein Lauf mit inszenierten Dateien endet in `PENDING_REBOOT`, nicht `DONE`.

## Der Tausch beim Boot

Die inszenierten Dateien werden vom `boot`-Befehl angewendet, den das Host-Modul in `post-fs-data.sh` verdrahtet, sodass er synchron und **pre-zygote** läuft, bevor irgendein Prozess die neue `.so` mappen kann.

`boot` führt ein `resume` (um jede unterbrochene Phase abzuschließen) und dann den Tausch aus. Für jede inszenierte REBOOT-hard-Datei:

1. bestätigt es, dass der inszenierte Pfad innerhalb des Modulverzeichnisses bleibt (eine Containment-Prüfung);
2. hasht `staged/<path>.vdlu-new` erneut gegen den Manifest-Hash;
3. sichert die aktuelle Live-Datei;
4. `mv -f` die inszenierte Datei über die Live-Datei und `chmod`-t sie;
5. hasht die jetzt an ihrem Platz befindliche Datei erneut, um zu bestätigen, dass der Tausch korrekt landete;
6. markiert sie als angewendet.

Erst wenn jede inszenierte Datei getauscht und erneut verifiziert ist, schließt die Transaktion von `PENDING_REBOOT` zu `DONE`. Schlägt ein Schritt fehl, zeichnet das Journal den Fehler auf und das Modul behält seine vorherigen Dateien; nichts wird halb getauscht gelassen.

Weil der Tausch eine Folge von erneutem Hashen und atomaren Umbenennungen ist, ist das Ausführen von `boot` sicher, selbst wenn es letztes Mal unterbrochen wurde. Es nimmt die inszenierten Dateien einfach wieder auf.

## auto_on_reboot

Die Inszenierung ist nur die Hälfte eines neustartfreien Gefühls; die andere Hälfte ist, dass der Nutzer sich nie merken sollte, den Tausch auszuführen. Mit `auto_on_reboot=1` in der Konfig ruft das `post-fs-data.sh` des Host-Moduls `update.sh boot` bei jedem Boot auf. Das bedeutet:

- wenn eine Transaktion auf einen Neustart wartet, werden die inszenierten Dateien automatisch getauscht, bevor zygote startet, und der Nutzer findet sich einfach vollständig auf der neuen Version wieder;
- wenn nichts aussteht, kann `boot` einen frischen Zyklus laufen und alles anwenden, einschließlich einer `.so`, in diesem einen Boot, da es bereits pre-zygote läuft.

Mit anderen Worten, eine inszenierte `.so` kostet den Nutzer nichts über einen Neustart hinaus, den sie ohnehin machen würden. Sie müssen das zweite Mal auf nichts tippen.

## Offline beim Boot, ohne den Akku zu leeren

Manchmal will `boot` den Feed prüfen, aber das Gerät hat noch kein Netz. VDLU kann darauf warten, geduldig und günstig, gesteuert durch `boot_retry_minutes` (0 schaltet es ab). Das Warten ist bewusst akkuschonend:

- zwischen Versuchen `sleep`t es einfach, was im Tiefschlaf einfriert, sodass das Gerät normal schläft und der Retry erst fortfährt, sobald das Gerät ohnehin wach ist;
- es hält keinen Wakelock und hält den Engine-Lock nicht, während es wartet, sodass ein manueller Lauf nie blockiert wird;
- vor jedem Versuch prüft es, ob das Netzwerk erlaubt ist, mit einer Kernel-Route-Abfrage, die kein Paket sendet und das Funkmodul nicht weckt;
- es versucht nie einen deterministischen Fehler erneut, wie eine schlechte Signatur oder ein blockiertes Downgrade, nur einen echten Netzwerk-abwesend-Zustand.

Die Manifest-Prüfung selbst bleibt in jedem Netzwerk gratis, sodass du immer erfährst, dass ein Update existiert; nur der Download wartet darauf, dass die Netzwerkrichtlinie erfüllt ist, und verschiebt sauber, statt zu fehlern.

## Siehe auch

- [[Engine]]: die Transaktion, die Apply-nach-Klasse-Logik und der `boot`-Befehl in voller Länge.
- [[Architecture]]: wo die Engine zwischen dem Producer und der WebUI sitzt.
