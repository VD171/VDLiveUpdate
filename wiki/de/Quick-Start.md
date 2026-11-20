# Quick Start

Dies ist die Übernahme-Checkliste: wie du **VDLiveUpdate (VDLU)** in ein
KernelSU- / APatch- / Magisk-Modul einbettest. VDLU ist selbst kein Modul. Es wird in
`<module>/vdlu/` abgelegt und innerhalb des Zips deines Moduls ausgeliefert, sodass ein installiertes Modul
sich flashlos von einem signierten Feed aktualisieren kann, den du veröffentlichst.

Durchgehend ersetze `<id>` durch deine Signaturschlüssel-Id, `<abi>` durch die Geräte-
ABI(s), die du auslieferst (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), und `<module>`
durch deinen Modulbaum.

Für die Begründung hinter jedem Teil siehe [[Engine]], [[Producer]], [[WebUI]] und
[[Security and Trust Model]].

## Das modulinterne `vdlu/`-Layout

Dies ist der exakte Baum, den dein Modul nach der Übernahme trägt:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

Der veränderliche Zustand der Engine (`config`, `current.json`, Journal, Lock, Blob-Cache)
lebt in Tier-2 unter `/data/adb/<modid>/vdlu/`, außerhalb des Modulverzeichnisses.
`config.default` seedet jene Tier-2-`config` beim ersten Lauf. Siehe [[Engine]] für das
vollständige Zustandslayout.

## 1. Die Engine einbetten

Kopiere die Engine, das Verify-Shim und das Per-ABI-Verifizierer-Binary in
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Liefere nur die ABIs aus, die du unterstützt. Dein `customize.sh` kann `verify/` auf
die ABI des Geräts zur Install-Zeit beschneiden.

## 2. Einen Signaturschlüssel erzeugen (einmalig)

```sh
producer/vdlu-keygen <id> ./keys
```

Dies gibt drei Dateien aus:

- `<id>.pem` - der private Schlüssel. Halte ihn von jedem Gerät und aus jedem Repo-
  Push oder CI-Secret fern.
- `<id>.pub` - der PEM-öffentliche-Schlüssel. Nur PC-seitig (von `vdlu-sign` verwendet).
- `<id>.pub.raw` - der ROHE 32-Byte-öffentliche-Schlüssel, für den Geräte-Keyring.

Siehe [[Security and Trust Model]] für den Grund, warum die Trennung wichtig ist.

## 3. Den rohen öffentlichen Schlüssel einbetten

Der Geräte-Keyring hält den **ROHEN 32-Byte**-Schlüssel, nie die PEM. `ed25519-mini`
kann keine PEM lesen, sodass das Kopieren der PEM hierher die geräteseitige Prüfung bricht:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Der Keyring ist über Releases hinweg stabil: er ändert sich nur bei einer Schlüsselrotation. Bei einem
erneuten Einbetten, **verifiziere ihn, überschreibe ihn nicht**.

## 4. Die Konfig schreiben

Liefere `config.default` in `<module>/vdlu/` aus. Es seedet die Tier-2-`config` beim ersten
Lauf:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Verwende `profile=trusted` nur für eine private `file://`- oder SSH-Quelle (Verify ist
dort Best-Effort, aber der sha256 jedes Blobs wird dennoch geprüft). Jeder Wert außer
dem wörtlichen `trusted` wird als `hardened` behandelt, fail-closed. Siehe
[[Security and Trust Model]] für die vollständige Profil-Semantik.

## 5. Die Trigger verdrahten

**Beim Neustart** (`auto_on_reboot`): rufe die Engine pre-zygote aus
`post-fs-data.sh` auf, sodass inszenierte Dateien der Reboot-Klasse (eine `.so`, ein `/system`-Overlay,
eine `sepolicy.rule`) ohne zusätzlichen Neustart eingetauscht werden:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Beim Öffnen der WebUI** (`auto_on_webui_open`): verdrahte das Drop-in-Updates-Panel in deiner
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
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` und `vdlu.css` werden aus `webui/` eingebettet. Eine Übersetzung kann
mit `i18n: window.VDLU_I18N_<LANG>` hinzugefügt werden. Siehe [[WebUI]] für den Panel-Vertrag.

## 6. Den Feed in deinem Release-Workflow signieren

Packe bei jedem Release den finalen Modulbaum und signiere das Manifest. Halte den privaten
Schlüssel auf der Operator-Maschine, nie in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` ist inhaltsadressiert und deduplizierend, sodass die Veröffentlichung inkrementell ist:
unveränderte Blobs werden nie erneut gepusht. Siehe [[Producer]] und [[Feed Format]].

## 7. Die Baseline ausliefern

Erzeuge `baseline.json` über den ausgelieferten Baum und platziere sie unter
`<module>/vdlu/baseline.json`. Sie seedet `current.json` bei einer frischen Installation, sodass das
Gerät "aktuell" geboren wird und seine eigene ausgelieferte Version nicht erneut lädt. Sie ist ein
**lokaler vertrauenswürdiger Seed**: unsigniert und schlüssellos, sodass CI sie bauen kann, ohne je
den Signaturschlüssel zu berühren:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Sie ist nicht fatal, wenn abwesend: das Gerät startet beim ersten Update einfach von Version `0`.

---

Das ist die gesamte Übernahme. Bevor du ausliefern, muss `sh -n <module>/vdlu/update.sh`
bestehen, und du solltest den Producer und die Engine end-to-end testen, wie gezeigt in
[[Contributing]] und [[Producer]].
