# Engine

Die Engine ist die Geräteseite von VDLU: der Teil, der auf dem Telefon läuft, entscheidet, was sich geändert hat, es herunterlädt und anwendet. Es ist ein einziges POSIX-Shell-Skript, `engine/update.sh`, plus einem winzigen Signaturprüfer, `engine/vdlu-verify`. Beide werden in das Host-Modul unter `<module>/vdlu/` eingebettet und von root ausgeführt.

Die gesamte Engine ist um eine Idee herum gebaut: ein Update ist eine **wiederaufnehmbare Transaktion**. Wird das Telefon neu gestartet, abgewürgt oder verliert auf halbem Weg das Netz, setzt der nächste Lauf genau dort an, wo er aufhörte, und das Modul wird nie halb angewendet gelassen, während es vorgibt, fertig zu sein.

Wenn du zuerst das große Bild möchtest, siehe [[Architecture]]. Für die Art, wie Updates einen Neustart vermeiden, wann immer sie können, siehe [[Reboot Handling]].

## Für das Gerät geschrieben, nicht für deinen Laptop

`update.sh` ist reines POSIX `sh`. Es läuft unter mksh, busybox oder toybox, ohne bash-spezifische Features, und es besteht `sh -n`. Das ist wichtig, weil die Umgebung auf einem gerooteten Android-Gerät klein und streng ist.

Insbesondere gibt es kein `jq`. VDLU parst `manifest.json` mit einem kleinen gron-artigen Flattener, geschrieben in `awk`: er geht das JSON Zeichen für Zeichen durch und gibt eine `path<TAB>value`-Zeile pro Blatt aus (zum Beispiel `files/0/sha256<TAB>ab..` oder `version<TAB>6`). Die Shell liest diese Zeilen dann mit `grep` und `cut`. Das funktioniert sowohl bei kompaktem als auch bei hübsch formatiertem JSON, und es ruft nie ein JSON-Werkzeug auf, das nicht da ist.

Die Engine hängt nur von dem ab, was toybox ohnehin mitbringt (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), vom eingebetteten `ed25519-mini`-Verifizierer und, für `https://`-Feeds, von einem kleinen statischen `curl`, das einmal geladen und verifiziert wird. Ein `file://`-Feed braucht überhaupt kein `curl`.

## Die sechs Befehle

Du rufst die Engine mit den Pfaden des Moduls in der Umgebung und einem Befehl auf:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Exit-Code `0` bedeutet Erfolg; jeder andere Code bedeutet einen Fehler, mit dem Grund auf stderr ausgegeben.

| Befehl | Was er tut |
|---|---|
| `check` | Schreibgeschütztes Diff. Lädt das Manifest, vergleicht es mit dem Installierten und gibt eine einzeilige JSON-Zusammenfassung aus: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Ändert nichts auf der Platte. Ist das Gerät neuer als der Feed (ein blockiertes Downgrade), meldet es `{"update":false,"ahead":true,...}` mit Exit `0`, kein Fehler. |
| `run` | Der volle Live-Zyklus: DIFF, FETCH, APPLY, COMMIT. Wendet jede Live-Datei sofort an und inszeniert die wenigen Dateien der Reboot-Klasse. Respektiert `cancel`. Schreibt den Fortschritt nach `journal.json`. |
| `resume` | Setzt eine unterbrochene Transaktion fort, beginnend bei der Phase, in der sie war. Idempotent. Es tauscht **keine** inszenierte `.so` (das ist `boot` vorbehalten). |
| `boot` | Der Pre-Zygote-Pfad. Führt ein `resume` aus und tauscht dann alle inszenierten `*.vdlu-new`-Dateien an ihren Platz, womit `PENDING_REBOOT` zu `DONE` geschlossen wird. Gibt es keine ausstehende Transaktion, läuft ein frischer Zyklus und wendet alles an, einschließlich der `.so`, in diesem einen Boot. |
| `status` | Gibt `journal.json` aus, oder `{"state":"idle"}`, wenn nichts im Gange ist. |
| `cancel` | Erstellt einen `cancel`-Marker. Ein laufender `run` stoppt sauber am nächsten sicheren Punkt. |

Der `check`-Befehl ist bewusst billig, damit die UI dir in jedem Netzwerk sagen kann, dass ein Update existiert. Der eigentliche Download wird separat gesteuert (siehe die Fetch-Phase unten).

## Die Transaktion, Schritt für Schritt

Jeder `run` durchläuft einen festen Zustandsautomaten, aufgezeichnet in `journal.json`, sodass die WebUI (und du) ihn beobachten können:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Die Engine lädt `manifest.json`, validiert jedes Feld (siehe unten und [[Security and Trust Model]]) und vergleicht den signierten Zielbaum mit `current.json`, dem Manifest der bereits installierten Version. Das Ergebnis ist ein Plan pro Datei, geschrieben nach `plan.tsv`: eine Zeile pro Datei, die ihre Klasse, den Ziel-Hash, den Modus und den Fortschrittszustand trägt. Dateien, die bereits den Ziel-Hash haben, werden zum Überspringen markiert.

**FETCH.** Für jede noch benötigte Datei lädt die Engine ihren inhaltsadressierten Blob von `<source>/blobs/<sha>` (oder `<sha>.gz`, wenn komprimiert) in eine `.part`-Datei. Ist der Blob gezippt, wird er dekomprimiert, dann wird sein SHA-256 gegen das Manifest geprüft. Nur bei einer Übereinstimmung wird er atomar nach `blobs/<sha>` verschoben (`mv`). Ein bereits mit korrektem Hash zwischengespeicherter Blob wird komplett übersprungen, und eine unveränderte lokale Datei kann den Cache ohne jeden Download seeden. Drei Fehlschläge beim selben Blob brechen die Phase ab, ohne dass etwas angewendet wird. Die Phase erreicht `FETCHED` erst, sobald jeder Blob im Plan vorhanden und verifiziert ist. Für das [[Feed Format]], aus dem diese Blobs stammen, siehe jene Seite. Bei der Toolchain-Einrichtung loggt die Engine das aufgelöste TLS-Trust - den CA-Pfad und ob er lesbar ist, dazu die Größe des Bundles und die Zertifikatszahl - sodass ein curl-`rc 77` zur Boot-Zeit in `boot.log` selbsterklärend ist (es unterscheidet einen leeren Trust-Store von einem unlesbaren, der Boot-SELinux-Kontext-Fall).

Das Fetch wird durch die Netzwerkrichtlinie gesteuert: ein Feed kann auf nur WLAN, nur Mobilfunk oder jedes Netzwerk beschränkt sein. Wenn das aktuelle Netzwerk nicht erlaubt ist, schlägt das Fetch nicht fehl; es geht in den harmlosen `DEFERRED`-Zustand, hält den Plan und das Ziel fixiert, und wird beim nächsten Check oder Boot fortgesetzt, sobald das richtige Netzwerk erscheint. In der Zwischenzeit werden keine Daten verbraucht.

**APPLY.** Wird nur je aus `FETCHED` betreten. Für jede Datei handelt die Engine nach Klasse:

- `live`- und `soft`-Dateien: die aktuelle Datei nach `rollback/<version>/<path>` sichern, den neuen Inhalt in eine `.vdlu-tmp`-Geschwisterdatei schreiben, sie `chmod`-en, ihren Hash verifizieren, dann atomar über das Ziel `rename`-n. Eine Datei, die bereits den Ziel-Hash hat, wird übersprungen.
- `reboot`-Dateien (eine `.so`, ein `/system`-Overlay, eine `sepolicy.rule`): materialisieren nach `staged/<path>.vdlu-new`. Der Live-Inode wird hier nie berührt. Siehe [[Reboot Handling]].
- Löschungen: sichern, dann entfernen. Löschungen werden erst ganz am Ende angewendet, bei einem sauberen `DONE`, nie während ein Neustart noch aussteht.

**COMMIT.** Die Engine hasht jede berührte Live- und Soft-Datei erneut. Nur wenn alle übereinstimmen, schreibt sie `current.json` und macht die neue Version zur Diff-Basis. Wurde eine Datei der Reboot-Klasse inszeniert, wird der Zustand `PENDING_REBOOT` statt `DONE`; der Tausch und die abschließende erneute Prüfung geschehen später unter dem `boot`-Befehl.

## Ausfallsicher durch Konstruktion

Die Garantien, die den unbeaufsichtigten Betrieb sicher machen:

- **Nichts wird als `DONE` markiert ohne ein passendes erneutes Hashen.** `DONE` wird erst erreicht, nachdem jede angewendete Datei zurückgelesen und ihr SHA-256 mit dem Manifest verglichen wurde. Eine inszenierte Reboot-Datei erzwingt `PENDING_REBOOT`, nie ein falsches `DONE`.
- **Nichts geht verloren.** Jede Datei wird nach `rollback/<version>/` gesichert, bevor sie überschrieben wird, und die letzten drei Versionen werden aufbewahrt. Schlägt ein Apply fehl, werden die Live-Dateien aus dem Backup zurückgesetzt; das Modul wird nie halb angewendet gelassen, während es darüber lügt. `apply_live` bricht sofort ab, wenn der Backup-Schritt fehlschlägt, statt ohne Rückweg zu überschreiben.
- **Alles ist atomar.** Neuer Inhalt landet über `rename`/`mv` über dem Ziel, sodass ein Leser je entweder die alte oder die neue Datei sieht, nie einen abgeschnittenen Schreibvorgang.
- **Wiederaufnehmbar nach einem Absturz oder Abwürgen.** Ein Absturz, ein verlorenes Netz oder ein Neustart auf halbem Weg hinterlässt ein gültiges Journal; `resume` (oder `boot`) setzt bei der aufgezeichneten Phase fort. Das Design nimmt an, dass es unterbrochen wird.
- **Degradiert sauber.** Ein fehlendes Binary, ein ausgefallenes Netz oder eine volle Platte erzeugt einen klaren Fehler auf stderr und `state:ERROR` im Journal, ohne das Modul zu beschädigen.
- **Der Vertrauensanker ist ausgeschlossen (`ENGINE_VERSION` 5).** Die Engine ignoriert jeden `vdlu/`-Pfad in einem geholten Plan - ihr eigenes `update.sh`, `vdlu-verify`, die `verify/`-Binaries, den Keyring und die Konfig - sodass ein Feed den Verifizierer oder den Signaturschlüssel niemals über die Leitung tauschen kann; der Anker ändert sich nur durch ein vollständiges signiertes Re-Flash. Siehe [[Security and Trust Model]].
- **Ein Update verschiebt sich, während das Modul beschäftigt ist.** Mit dem optionalen `apply_busy_file`, gesetzt auf einen absoluten Pfad, den das Host-Modul während seiner eigenen Operationen berührt (zum Beispiel ein laufendes Backup), wartet APPLY, solange dieser Pfad existiert, sodass Dateien nie mitten in einer Operation getauscht werden; die Blobs sind bereits geholt, sodass der nächste Trigger ohne erneuten Download anwendet.
- **Größen-Obergrenzen.** Eine Datei ist auf **128 MiB** und das Manifest auf **2 MiB** begrenzt, durchgesetzt vor dem Lesen beider sowohl in `update.sh` als auch in `vdlu-verify` (Anti-Dekompressionsbombe / Anti-OOM).
- **Ein Modul, das dem Feed voraus ist, wird nie zurückgesetzt (`ENGINE_VERSION` 7).** Der live installierte `versionCode`, aus dem eigenen `module.prop` des Moduls gelesen, bildet die Untergrenze der "from"-Version, sodass ein Gerät, das manuell über einen veralteten Feed hinaus aktualisiert wurde, als *voraus* gelesen wird: die Downgrade-Guard liefert benign zurück, ohne Plan und ohne Rücksetzung. `boot` self-healt zudem eine bestehende Installation - ein persistierter Plan, dessen Target unter der installierten Version liegt, oder ein veraltetes Journal mit `target <= 0` (`ENGINE_VERSION` 6), wird vor jedem Resume gelöscht.

## Der Lock

Nur eine Transaktion darf den Zustand gleichzeitig berühren. `flock` ist auf toybox nicht zuverlässig, daher serialisiert VDLU mit einem Verzeichnis-Lock: `mkdir "$VDLU_DIR/lock.d"` gelingt für genau einen Aufrufer und schlägt für den Rest fehl, was auf jedem vernünftigen Dateisystem atomar ist. Ein von einem toten Prozess hinterlassener veralteter Lock wird durch Prüfung der aufgezeichneten PID wiederhergestellt.

Der geduldige Boot-Zeit-Retry (verwendet, wenn das Gerät beim Boot offline ist) hält diesen Lock **nicht**, während er wartet. Er erwirbt und gibt ihn zwischen Versuchen frei, sodass ein manueller `run` nie von einem Boot blockiert wird, der auf das Netzwerk wartet, und er hält nie einen Wakelock. Akkuschonend durch Design. Mehr dazu in [[Reboot Handling]].

## Signaturprüfung: `vdlu-verify`

`vdlu-verify` ist der geräteseitige Signaturprüfer, bewusst schlank gehalten:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Exit `0` bedeutet, dass die Signatur des Manifests gegen den öffentlichen Keyring-Schlüssel gültig ist, dessen Id mit dem `key_id` des Manifests übereinstimmt; jeder andere Code ist eine Ablehnung.

Was ihn schlank macht, ist, dass er **kein `openssl` auf dem Gerät** nutzt. Er liest den öffentlichen Keyring-Schlüssel als **rohe 32-Byte**-Datei, kanonisiert das Manifest (den Manifest-Text mit entferntem `sig`-Feld), hasht es mit toybox `sha256sum`, dekodiert die Signatur mit base64 und übergibt den rohen Schlüssel, die Nachricht und die 64-Byte-Signatur an das eingebettete `ed25519-mini`-Binary. Der Prüfer verweigert auch alles Fehlerhafte, bevor er überhaupt verifiziert: ein fehlendes oder leeres `key_id` oder `sig`, ein `key_id`, das Pfadtrenner enthält, einen öffentlichen Schlüssel, der nicht genau 32 Byte ist, oder eine Signatur, die nicht genau 64 Byte ist.

Bevor sie überhaupt einen Schlüssel auswählt, setzt die Engine eine **`key_id`-Allowlist** durch: das `key_id` des Manifests muss eines sein, dem die Konfig erlaubt, ein *Modul-Update* zu signieren, und ein Schlüssel, der lediglich im Keyring vorhanden, aber nicht in der Allowlist ist, wird abgelehnt, bevor sein Pubkey je geladen wird. Ein Keyring mit einem einzigen Schlüssel fixiert diesen einen Schlüssel automatisch ohne Konfig; ein Keyring mit mehreren Schlüsseln muss `key_id` fixieren, oder die Engine fällt fail-closed. Die erlaubte Menge wird als `VDLU_KEYID_ALLOW` an `vdlu-verify` weitergereicht und gilt in beiden Profilen. Das hindert einen weniger vertrauenswürdigen Schlüssel, etwa einen Fingerprint-Feed-Schlüssel, der sich den Keyring teilt, daran, ein vollständiges Root-Update zu signieren; der separate Fingerprint-Feed behält seinen eigenen fixierten Schlüssel, `FEED_KEY_ID`. Die vollständige Geschichte steht in [[Security and Trust Model]].

Die Kanonisierung ist Byte für Byte identisch mit dem Signierer des Producers, was eine Signatur werkzeugübergreifend verifizierbar macht. Der passende private Schlüssel berührt nie ein Gerät oder CI; nur der rohe öffentliche Schlüssel ist eingebettet. Die vollständige Vertrauensgeschichte, die zwei Profile und warum `hardened` durch Inversion fail-closed ist, stehen in [[Security and Trust Model]].

Die Engine ruft `vdlu-verify` während der Diff-Phase auf. Unter dem `hardened`-Profil bricht eine fehlgeschlagene Prüfung das gesamte Update ab; unter `trusted` ist die Prüfung Best-Effort, aber der Hash jedes Blobs wird dennoch immer geprüft, sodass beschädigter Inhalt unabhängig vom Profil erkannt wird.

## Zustand auf der Platte

Der gesamte Zustand der Engine lebt in `$VDLU_DIR` (außerhalb des Modulverzeichnisses), sodass der Modulbaum selbst nur je fertige Dateien enthält:

| Pfad | Rolle |
|---|---|
| `config` | key=value-Einstellungen (Quelle, Profil, Kanal, Netzwerkrichtlinie, Boot-Retry) |
| `current.json` | Manifest der aktiven Version; dies ist die Diff-Basis. Abwesend bedeutet nie aktualisiert |
| `target.json` | das fixierte Manifest der laufenden Transaktion. Seine Anwesenheit markiert eine aktive Transaktion; es wird bei `DONE` zu `current.json` |
| `plan.tsv` / `plan.del` | der Plan und Fortschritt pro Datei, und die Liste der zu löschenden Pfade |
| `journal.json` | Fortschritt für die WebUI, bei jeder Zustandsänderung neu geschrieben |
| `blobs/<sha256>` | Cache verifizierten, dekomprimierten Originalinhalts |
| `rollback/<version>/<path>` | Backups überschriebener Dateien; die letzten drei Versionen werden aufbewahrt |
| `staged/<path>.vdlu-new` | eine Datei der Reboot-Klasse, die auf den Boot-Tausch wartet |
| `lock.d/` | der mkdir-Lock |
| `tools/<abi>/curl` | das geladene, verifizierte statische curl; bleibt über Updates hinweg bestehen |
| `cancel` | eine Abbruchanforderung |

## Siehe auch

- [[Reboot Handling]]: wie das Klassensystem die meisten Updates neustartfrei hält, und wie eine inszenierte `.so` pre-zygote getauscht wird.
- [[Security and Trust Model]]: die zwei Profile, Fail-closed-Validierung und die Roh-Schlüssel-ed25519-Kette.
- [[Feed Format]]: das Manifest und die inhaltsadressierten Blobs, die die Engine konsumiert.
- [[Architecture]]: wie Engine, Producer und WebUI zusammenpassen.
