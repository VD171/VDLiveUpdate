> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · Deutsch · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU-Adoptions-Quickstart

Eine Copy-paste-Checkliste, um **VDLiveUpdate** in ein Modul zu vendorisieren. VDLU ist selbst
kein Modul: es wird in `<module>/vdlu/` abgelegt und innerhalb des Zips deines Moduls
ausgeliefert. Für das vollständige Rationale siehe [`INTERFACES.md`](INTERFACES.md) (den
Nahtvertrag), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) und [`WEBUI.md`](WEBUI.md).

Ersetze `<id>` durch deine Signierschlüssel-id, `<abi>` durch die Geräte-ABI(s), die du
auslieferst (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), und `<module>` durch deinen
Modulbaum.

## Ziellayout

Dies ist der exakte `vdlu/`-Baum, den das Modul nach der Adoption trägt:

```
<module>/
├── module.prop
├── post-fs-data.sh            # Pre-Zygote-Trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # deine WebUI, verdrahtet das Updates-Panel (Schritt 5)
└── vdlu/
    ├── update.sh              # die Engine (byte-für-byte vendorisiert)
    ├── vdlu-verify            # ed25519-Verify-Shim (device-seitig, kein openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # Verifier-Binary pro ABI
    ├── keyring/
    │   └── <id>.pub           # RAW 32-Byte-Public-Key (NIEMALS der PEM)
    ├── config.default         # profile + source + Automatisierungs-Standardwerte
    └── baseline.json          # Installations-Seed (unsigniert, schlüssellos)
```

Der veränderliche Zustand der Engine (`config`, `current.json`, Journal, Lock) lebt in
Tier-2, `/data/adb/<modid>/vdlu/`, außerhalb des Modulverzeichnisses, `config.default` seedet
ihn beim ersten Lauf.

## 1. Die Engine vendorisieren

Kopiere die Engine, das Verify-Shim und den Verifier pro ABI nach `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini pro ABI
```

Liefere nur die ABIs aus, die du unterstützt, `customize.sh` kann `verify/` zur
Installationszeit auf die ABI des Geräts reduzieren.

## 2. Einen Signierschlüssel generieren (einmalig)

```sh
producer/vdlu-keygen <id> ./keys
```

Das emittiert `<id>.pem` (privat, halte es von jedem Gerät und von jedem Repo-Push fern),
`<id>.pub` (PEM, nur PC-seitig) und `<id>.pub.raw` (RAW 32 Byte, für das Geräte-Keyring).

## 3. Den rohen Public-Key einbetten

Das Geräte-Keyring hält den **RAW 32-Byte**-Schlüssel, niemals den PEM (`ed25519-mini`
kann keinen PEM lesen):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Das Keyring ist über Releases hinweg stabil (es ändert sich nur bei einer Schlüsselrotation):
bei einem Re-Vendor **verifizieren, nicht überschreiben**.

## 4. Die config schreiben

Liefere `config.default` in `<module>/vdlu/` aus (seedet die Tier-2-`config` beim ersten Lauf):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # öffentlicher Feed: Signatur obligatorisch, Downgrade blockiert
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: APPLY verschieben, solange dieser Pfad existiert (z. B. ein laufendes Backup)
```

Nutze `profile=trusted` nur für eine private `file://`/SSH-Quelle (verify best-effort, der
sha256 jedes Blobs wird trotzdem geprüft). Jeder andere Wert als das wörtliche `trusted` wird
als `hardened` behandelt (fail-closed).

## 5. Die Trigger verdrahten

**Beim Reboot** (`auto_on_reboot`): rufe die Engine pre-zygote aus `post-fs-data.sh` auf,
damit gestagete Dateien (eine `.so`, ein `/system`-Overlay, eine `sepolicy.rule`) ohne
zusätzlichen Reboot eingewechselt werden:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Beim WebUI-Öffnen** (`auto_on_webui_open`): verdrahte das Drop-in-Updates-Panel in deiner
`webroot/index.html`:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                             // wertet Journal + Banner + auto_on_webui_open aus
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // der "Updates"-Tab
</script>
```

(`vdlu.js` / `vdlu.css` werden aus `webui/` vendorisiert, eine Übersetzung kann mit
`i18n: window.VDLU_I18N_<LANG>` hinzugefügt werden.)

## 6. Den Feed in deinem Release-Workflow signieren

Packe bei jedem Release den finalen Modulbaum und signiere das Manifest. Halte den privaten
Schlüssel auf der Operator-Maschine, niemals in der CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = seit prev verschwundene Pfade
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publiziere ./out/{manifest.json,blobs/} nach <source>
```

## 7. Die Baseline ausliefern

Generiere `baseline.json` über den ausgelieferten Baum und platziere sie unter
`<module>/vdlu/baseline.json`. Sie seedet `current.json` bei einer frischen Installation,
sodass das Gerät "current" geboren wird (kein Re-Fetch). Sie ist ein **lokaler
vertrauenswürdiger Seed**: unsigniert und schlüssellos, sodass die CI sie bauen kann, ohne je
den Signierschlüssel zu berühren:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Es ist nicht fatal, wenn sie fehlt (das Gerät startet dann einfach bei der ersten
Aktualisierung von `0`).

---

Das ist die gesamte Adoption. `sh -n <module>/vdlu/update.sh` muss durchgehen, teste den
Producer und die Engine Ende-zu-Ende wie in [`PRODUCER.md`](PRODUCER.md) und dem Root-README
gezeigt, bevor du auslieferst.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen, siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
