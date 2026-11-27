> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · Deutsch · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Sicherheitsrichtlinie

VDLiveUpdate (VDLU) wendet flashless Root-Updates auf ein laufendes Modul an: Es schreibt
in das eigene Verzeichnis des Moduls und tauscht beim Boot eine Zygisk-`.so` aus, wobei es
im Root-Kontext des Moduls läuft. Wir nehmen Sicherheit ernst.

## Eine Schwachstelle melden

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Füge eine klare Beschreibung bei und, wenn möglich, ein Manifest oder einen Feed, der das
Problem reproduziert. Wir antworten so schnell wir können und nennen dich, wenn du möchtest.

## Hinweise zum Geltungsbereich

- Updates sind content-addressed Blobs plus eine mit ed25519 signierte `manifest.json`. Das
  Gerät verifiziert die Signatur mit einem eingebetteten `ed25519-mini` (kein openssl auf
  dem Gerät), und jeder Blob wird vor der Verwendung gegen seinen `sha256` geprüft.
- Das hardened Profil (die öffentliche Voreinstellung) verlangt eine gültige Signatur und
  blockiert Downgrade. Die "Von"-Version wird durch den `versionCode` des installierten
  Moduls (gelesen aus `module.prop`) nach unten begrenzt, sodass ein Modul nie hinter den
  Feed zurückgesetzt wird.
- Die Vertrauenswurzel (der rohe ed25519-Public-Key im `keyring/` und die Binaries in
  `verify/`) ist flash-only und wird nie über das Netz rotiert. Der Producer schließt sie
  vom Feed aus und die Engine ignoriert jeden `vdlu/`-Pfad in einem heruntergeladenen Plan,
  sodass ein geleakter Signaturschlüssel den Verifier oder den Schlüssel nicht austauschen
  und Root nicht persistieren kann.
- Ein gültig für ein anderes Modul signiertes Manifest kann nicht in das Verzeichnis eines
  anderen Moduls schreiben. Das signierte Feld `module` muss gleich der `MODID` des Geräts
  sein (modulübergreifende Bindungsprüfung), und jedes Schreiben und Löschen bleibt auf das
  Modulverzeichnis beschränkt.
- Die Engine läuft im eigenen Root-Kontext des Moduls und schwächt ihn nie. Sie fügt keine
  Privilegien hinzu und interpoliert kein Manifest-Feld in eine Shell, jeder Wert von
  `path`, `sha256`, `mode` und `delete[]` wird vor der Verwendung als feindliche Eingabe
  validiert.
- Die Haltung ist fail-closed. Ein beschädigter oder unbekannter `profile`-Wert fällt nie
  dazu durch, unsignierten Inhalt zu akzeptieren (alles, was nicht genau `trusted` ist, wird
  als `hardened` behandelt), und vor dem Überschreiben einer Datei wird ein Backup
  geschrieben, sodass ein fehlgeschlagenes Apply die installierte Version nie zerstört.
- Siehe [TRUST-MODEL.md](TRUST-MODEL.md) für das vollständige Vertrauensmodell, die
  fail-closed Garantien und die Hardening-Details.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen, siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
