# Security and Trust Model

VDLU aktualisiert ein Modul an Ort und Stelle, über das Netzwerk, als root. Das ist eine Menge Macht, die auf eine Datei gerichtet ist, die aus einem Feed kommt, daher ist die gesamte Engine auf einer einzigen Annahme gebaut:

> **Jedes Feld im Manifest ist feindliche Eingabe.**

Ein Feed kann an der Quelle vergiftet oder im Transit von einem MITM getauscht und verstümmelt werden. Wenn das geschieht, kommt das Manifest dennoch an und sieht aus wie ein Manifest: es trägt Dateipfade, `sha256`-Strings, eine `delete[]`-Liste, Modi, Klassen und ein Kodierungs-Flag. VDLU behandelt nichts davon als vertrauenswürdig. Es validiert den gesamten Plan, bevor es ein einziges Byte lädt, und es lässt nie einen Manifest-Wert eine Shell erreichen.

Diese Seite ist die vollständige Vertrauensgeschichte. Siehe [[Feed Format]] für das Manifest-Schema, das es validiert, und [[Engine]] für die Stelle, an der diese Prüfungen in der DIFF -> FETCH -> APPLY -> COMMIT-Transaktion sitzen.

---

## Die Kernidee: fail-closed, bevor irgendetwas geschieht

`validate_plan()` läuft innerhalb der `check`/diff-Phase, **vor** jedem Fetch und **vor** jedem Apply. Es geht jeden Eintrag im geplanten Dateibaum und jeden Eintrag in `delete[]` durch, und wenn ein einziger Eintrag fehlerhaft ist, **verwirft es das gesamte Manifest** und die Transaktion startet nie. Es gibt keine partielle Annahme, kein "den schlechten überspringen und den Rest anwenden". Ein schlechtes Feld vergiftet die Charge, mit Absicht.

Ein Manifest wird nur akzeptiert, wenn **alle** diese Bedingungen für **jeden** Eintrag gelten:

| Feld | Regel | Warum |
|---|---|---|
| `path` | nicht absolut, keine `..`-Komponente, keine `.`-Komponente, kein führendes `./`, kein eingebettetes `/./`, kein nachgestellter Schrägstrich, kein Steuerzeichen (Tab / Zeilenumbruch) | ein Pfad muss innerhalb von `MODULE_DIR` bleiben; ein absoluter oder `..`-Pfad ist Schreiben-überall |
| `sha256` | passt exakt auf `^[0-9a-f]{64}$` | ein nicht-hex-sha würde sonst in einen Shell-Pfad interpoliert; es ist die Inhaltsadresse, also muss es ein reines Hex-Digest und nichts anderes sein |
| `mode` | nur oktal (`[0-7]`) | ein Modus-String wird zu einem `chmod`-Argument |
| `size` | nur Ziffern, und `<=` der Größenobergrenze der Engine | begrenzt den Download und die Dekompression |
| `class` | exakt `live`, `soft` oder `reboot` | die Klasse entscheidet, ob eine Datei live angewendet oder für einen Neustart inszeniert wird |
| `enc` | exakt `raw` oder `gz` | die Kodierung entscheidet, ob der Blob gunzippt wird |
| `delete[]`-Einträge | dieselben Pfadregeln wie oben | ein `delete[]`-Eintrag treibt eine Entfernung an; ein ungeprüfter `..` wäre `rm` außerhalb des Baums |

Weil dies zuerst läuft, kann ein vergiftetes Manifest nie außerhalb des Moduls schreiben, nie außerhalb des Moduls löschen und nie einen nicht-hex-Token in eine Befehlszeile injizieren.

### Manifest-Werte berühren nie eine Shell

Die zweite Hälfte der Regel: selbst nachdem ein Wert die Validierung besteht, wird er nie in `sh` interpoliert und nie an `awk system()` gefüttert. Der Check-Befehl wurde bewusst neu geschrieben, sodass er keinen `system()`-Aufruf enthält. Die Inhaltsadressierung erledigt den Rest der Arbeit: ein Blob wird nach seinem `sha256` geladen, in einen Cache-Pfad geschrieben, der nach demselben `sha256` benannt ist, und die heruntergeladenen Bytes werden erneut gehasht und verglichen, bevor etwas angewendet wird. Ein Wert, der kein sauberes 64-Hex-Digest ist, kommt nie so weit, weil `validate_plan()` ihn bereits verworfen hat.

### Eine zweite Verteidigungslinie zur Apply-Zeit

`validate_plan()` blockiert `..` **lexikalisch**, aber ein bereits im Baum vorhandener Symlink könnte einen Schreibvorgang dennoch umleiten. Daher löst `contained()` zur Apply-Zeit den echten Zielpfad auf und bestätigt, dass er unter der Modulbasis liegt, und fällt fail-closed, wenn es ihn nicht auflösen kann. Schreibvorgänge sind atomar (in einen temporären Namen schreiben, dann `rename` über das Ziel) und jedes Überschreiben wird zuerst nach `rollback/` gesichert; ein fehlgeschlagenes Backup bricht das Apply ab, statt ohne Sicherheitsnetz zu überschreiben.

---

## Die zwei Profile

VDLU läuft in einem von zwei Vertrauensprofilen, gesetzt durch `profile=` in der Konfig.

### `hardened` (der öffentliche Standard)

- **Signatur ist Pflicht.** Das Manifest muss eine gültige ed25519-Signatur von einem Schlüssel im geräteseitigen Keyring tragen, oder die Transaktion bricht ab.
- **Downgrade ist blockiert.** Ein Manifest, dessen `version` niedriger als die installierte Version ist, wird abgelehnt. Ein Angreifer kann dich nicht auf einen bekannt verwundbaren Build zurückrollen.
- Dies ist das Profil für jedes Modul, das über `https://` an die Öffentlichkeit verteilt wird.

### `trusted` (private, SSH-inszenierte Quelle)

- Die Signaturprüfung ist **Best-Effort**: die Quelle ist ein privater `file://`- oder SSH-inszenierter Feed, den du kontrollierst, sodass eine fehlende oder nicht verifizierbare Signatur nicht hart abbricht.
- **Aber der `sha256` jedes Blobs wird dennoch immer geprüft.** `trusted` lockert *wer das Manifest signiert hat*, nie *ob die Bytes zum Plan passen*. Inhaltsintegrität ist in beiden Profilen nicht verhandelbar.

---

## Fail-closed durch Inversion

Dies ist der subtile Teil, und es ist der Teil, den die meisten Systeme falsch machen.

`trusted` ist der **einzige** String, der sich für gelockerte Prüfung entscheidet. Die Engine testet nicht "ist das `hardened`?" Sie testet "ist das **nicht** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Also löst **alles** andere als das wörtliche `trusted` zu hardened-Verhalten auf:

- die Zeile fehlt vollständig -> hardened
- ein Tippfehler wie `hardend` -> hardened
- `trusted ` mit einem nachgestellten Leerzeichen, oder ein `\r` von CRLF -> hardened
- `Trusted` mit falscher Groß-/Kleinschreibung -> hardened
- ein von MITM verstümmelter Wert -> hardened

Eine frühere Version setzte eine *fehlende* Zeile auf hardened als Standard, was dennoch einen beschädigten *Wert* zum offenen Pfad durchfallen ließ. Das war ein Fail-open: ein verstümmelter Profil-String konnte stillschweigend ein unsigniertes Manifest akzeptieren, und ein unsigniertes Manifest bedeutet eine vom Angreifer gelieferte `.so`, die unter MITM eingetauscht wird, was Remote-Code-Ausführung auf Root-Ebene ist. Die Inversion schließt das. Der einzige Weg, gelockerte Prüfung zu bekommen, ist, `trusted` exakt zu schreiben, und selbst dann werden die Blob-Hashes geprüft. Die Engine ist nie einen Tippfehler davon entfernt, unsignierten Code zu akzeptieren. (Das `tr -d` entfernt stray Whitespace, sodass ein legitimes `trusted` mit nachlässigen Leerzeichen nicht fälschlich abgelehnt wird, ohne das Loch wieder zu öffnen.)

**Dieser Test ist tragend. Er muss `!= trusted` bleiben und nie `== hardened` werden.**

---

## Das Manifest ist an das Modul gebunden

Ein einziger Release-Schlüssel signiert viele Module. Also könnte ein gültig signiertes Manifest, für ein *anderes* Modul, im Prinzip diesem serviert werden (eine Feed-Fehlkonfiguration, ein Quellentausch oder eine MITM-Umleitung) und seine Signatur würde aufgehen.

VDLU schließt das mit einer Bindung: das signierte `module`-Feld innerhalb des Manifests muss der `MODID` dieser Installation entsprechen, oder das Manifest wird als modulübergreifender Feed abgelehnt. Weil `module` innerhalb der signierten kanonischen Form ist, kann ein Angreifer es nicht ändern, ohne die Signatur zu brechen. Ein gültig signierter Feed für Modul B kann schlicht nicht auf Modul A angewendet werden.

---

## Der schlanke geräteseitige Verifizierer

Die Prüfung auf dem Gerät nutzt **ed25519-mini**, einen winzigen Nur-Prüf-Checker, gebaut auf TweetNaCl (gemeinfrei). Es gibt **kein `openssl` auf dem Gerät**.

- Der Keyring-Eintrag ist der **rohe 32-Byte-öffentliche-Schlüssel**, gespeichert als `keyring/<key_id>.pub`. (Der PEM-öffentliche-Schlüssel ist nur ein PC-seitiges Artefakt; das Kopieren einer PEM in den Geräte-Keyring bricht die Prüfung, da der Verifizierer genau 32 rohe Bytes erwartet.)
- `vdlu-verify <manifest.json> <keyring_dir>` rekonstruiert die kanonische Form (den Manifest-Text mit entferntem `sig`-Feld, kompakt, sortierte Schlüssel), hasht sie zur 64-Zeichen-Hex-Nachricht, die die Signatur abdeckt, dekodiert die base64-Signatur, prüft, dass sie 64 Byte ist, und fragt `ed25519-mini <pub32> <msg> <sig64>` nach einem Urteil. rc 0 = gültig, alles andere = Ablehnung.
- Das Binary ist statisch pro ABI (arm64-v8a, armeabi-v7a, x86, x86_64), mit einem `PROVENANCE.json`, das die exakten TweetNaCl-Quellen, den Wrapper-Hash und die Build-Flags fixiert, sodass das Ding, das als root läuft, auditierbar ist.
- Das `key_id` aus dem Manifest wird selbst saniert (kein `/`, kein `..`, kein Anführungszeichen), bevor es verwendet wird, um eine Keyring-Datei auszuwählen, sodass es nicht aus dem Keyring-Verzeichnis entkommen kann.

### Der Keyring ist flash-only, verify-not-copy, stabil

Der Keyring wird zur Flash-Zeit innerhalb des Moduls ausgeliefert und wird von der Update-Engine nicht neu geschrieben. Beim erneuten Einbetten lautet die Regel **verify, do not copy**: der Keyring ändert sich nur bei einer bewussten Schlüsselrotation, nie als Nebeneffekt eines Updates.

### Schlüsselrotation macht ältere Installationen nicht kaputt

Wenn ein Signaturschlüssel rotiert wird, liefert der Keyring **sowohl den aktuellen als auch den vorherigen rohen öffentlichen Schlüssel**. Der Verifizierer wählt die Schlüsseldatei nach dem `key_id` des Manifests, sodass ein noch vom alten Schlüssel signierter Feed gegen den alten Pubkey verifiziert, und ein vom neuen Schlüssel signierter Feed gegen den neuen. Ein Gerät, das nicht über die Rotation hinaus aktualisiert hat, funktioniert weiter; nichts wird gestrandet.

---

## Die Modul-Update-`key_id`-Allowlist

Schlüsselrotation bedeutet bereits, dass der Keyring legitim mehr als einen Schlüssel halten kann, und ein Modul kann aus einem zweiten Grund mehr als einen halten: es kann einen weniger vertrauenswürdigen Schlüssel mitliefern, der einen *anderen* Feed signiert. Der Fingerprint-Feed ist genau dieser Fall. Ein Modul kann einen eng begrenzten Schlüssel tragen, dessen einzige Aufgabe es ist, einen Fingerprint-Feed zu signieren, und der im selben Keyring direkt neben dem Release-Schlüssel sitzt, der das Modul selbst signiert.

Das wirft eine Frage auf, die die Rotationsgeschichte allein nicht beantwortet: sobald zwei Schlüssel im Keyring leben, *welcher* von ihnen darf ein **Modul-Update** signieren? Ein Modul-Update ist das Mächtigste, worum ein Manifest bitten kann, weil es Dateien neu schreibt, die das Gerät als root ausführt. Der Verifizierer wählte früher den Pubkey, der durch das `key_id` des Manifests benannt war, und akzeptierte jeden Schlüssel, der zufällig im Keyring vorhanden war. Der weniger vertrauenswürdige Fingerprint-Feed-Schlüssel könnte also, wenn er geleakt würde, ein Modul-Update-Manifest signieren und das Gerät würde es honorieren. Das ist eine Umgehung der Vertrauenswurzel: ein Schlüssel, der für eine einzige eng begrenzte Aufgabe gedacht ist, könnte ein vollständiges flashless Root-Update antreiben.

Die Korrektur fixiert das akzeptierte Modul-Update-`key_id` auf eine fail-closed **Allowlist**, die geprüft wird, **bevor** der Pubkey je ausgewählt wird. Der Konfig-Schlüssel ist `key_id`, und die Engine löst ihn so auf:

- **Ein Keyring mit einem einzigen Schlüssel fixiert diesen einen Schlüssel automatisch.** Der häufige Fall braucht gar keine Konfig: wenn der Keyring genau einen Schlüssel hält, *ist* dieser Schlüssel die Allowlist, und nichts anderes kann ein Modul-Update signieren.
- **Ein Keyring mit mehreren Schlüsseln muss `key_id` setzen.** In dem Moment, in dem ein zweiter Schlüssel auftaucht, weigert sich die Engine zu raten. Sie fällt fail-closed mit "multiple keys in keyring; config must pin key_id", bis die Konfig den Schlüssel (oder die Schlüssel, kommagetrennt während eines Rotationsfensters) benennt, der Modul-Updates signieren darf.

Weil die Prüfung vor der Pubkey-Auswahl läuft, wird ein Manifest, das einen Schlüssel benennt, der vorhanden, aber nicht in der Allowlist ist, abgelehnt, ohne dass der Verifizierer diesen Schlüssel je lädt. Die aufgelöste Menge wird über `VDLU_KEYID_ALLOW` in `vdlu-verify` gespiegelt, sodass der schlanke geräteseitige Checker dieselbe Fixierung durchsetzt und die beiden nicht uneinig sein können. Das gilt in **beiden** Profilen: `hardened` und `trusted` konsultieren beide die Allowlist, weil die Allowlist entscheidet, *welcher Schlüssel* eine gültige Modul-Update-Wurzel ist, nicht *ob* eine Signatur erforderlich ist.

Der Fingerprint-Feed behält seine eigene separate fixierte Vertrauenswurzel, `FEED_KEY_ID`. Sie ist eine eigenständige Wurzel mit einer eigenständigen Aufgabe, nie über den obigen Modul-Update-Pfad erreichbar, sodass das Fixieren der Modul-Update-Allowlist sie nicht berührt und ein geleakter Feed-Schlüssel dennoch kein Modul-Update signieren kann. Diese Änderung hob `ENGINE_VERSION` auf 4 an.

---

## Was das Tools-Manifest schließt

Der schlanke Fetch-Bootstrap lädt bei der ersten Nutzung ein statisches `curl` für Module herunter, die kein eigenes mitliefern. Weil dieses Binary als root läuft, ist seine eigene Manifest-Signatur (ed25519-mini) und sein Hash in jedem Profil **Pflicht**, einschließlich `trusted`, bevor es je installiert oder ausgeführt wird. Die Webview ist nur Transport; Vertrauen kommt aus der geräteseitigen Signatur- und Hash-Prüfung, nie aus der Tatsache, dass ein Download gelang.

---

## Was ein Angreifer NICHT tun kann

Selbst wenn er den Feed besitzt oder als voller MITM auf der Leitung sitzt, kann ein Angreifer nicht:

- **Außerhalb des Moduls schreiben.** Absolute Pfade, `..`, `.`, Steuerzeichen und nachgestellte Schrägstriche werden alle vor jedem Apply abgelehnt, und Symlink-Umleitung wird zur Apply-Zeit erneut abgefangen.
- **Außerhalb des Moduls löschen.** `delete[]`-Einträge bestehen dieselbe Pfadvalidierung.
- **Einen Befehl injizieren.** Kein Manifest-Wert wird in eine Shell oder `awk system()` interpoliert; `sha256` muss reines 64-Hex sein oder das gesamte Manifest wird abgelehnt.
- **Unsignierten Code an eine öffentliche Installation ausliefern.** `hardened` macht die Signatur zur Pflicht, und das Profil ist durch Inversion fail-closed, sodass kein Tippfehler oder verstümmelter Wert das herabstuft.
- **Ein Modul-Update mit einem weniger vertrauenswürdigen Schlüssel signieren.** Das Modul-Update-`key_id` ist auf eine fail-closed Allowlist fixiert, geprüft bevor der Pubkey ausgewählt wird, sodass ein geleakter Fingerprint-Feed-Schlüssel, der sich den Keyring teilt, kein vollständiges Root-Update signieren kann.
- **Den signierten Feed eines anderen Moduls hier servieren.** Das signierte `module`-Feld muss dieser `MODID` entsprechen.
- **Dich zurückrollen.** Downgrade ist in `hardened` blockiert.
- **Einen Blob unbemerkt beschädigen.** Jeder heruntergeladene Blob wird in beiden Profilen erneut gegen den Manifest-`sha256` gehasht; eine Nichtübereinstimmung nach drei Versuchen bricht die Phase ab, ohne dass etwas angewendet wird.
- **Einen gefälschten Root-Fetcher einschleusen.** Das gebootstrappte `curl` wird in jedem Profil signatur- und hash-geprüft, bevor es installiert oder ausgeführt wird.
- **Ein korruptes Update halb anwenden.** Die Transaktion erreicht `DONE` nur, wenn ein erneutes Hashen von allem übereinstimmt; ein fehlgeschlagenes Apply rollt zurück, statt ohne Backup zu überschreiben.

---

Siehe auch: [[Feed Format]] für das Manifest-Schema, [[Engine]] für die Transaktion, in der diese Prüfungen leben, und [[Architecture]] für das große Bild.
