> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · Español · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart de adopción de VDLU

Una checklist de copiar y pegar para vendorizar **VDLiveUpdate** en un módulo. VDLU no es un
módulo en sí: se deja en `<module>/vdlu/` y viaja dentro del zip de tu módulo.
Para el rationale completo ver [`INTERFACES.md`](INTERFACES.md) (el contrato de costura),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) y [`WEBUI.md`](WEBUI.md).

Reemplaza `<id>` por el id de tu clave de firma, `<abi>` por la(s) ABI(s) de dispositivo que entregas
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), y `<module>` por tu árbol de módulo.

## Layout objetivo

Este es el árbol `vdlu/` exacto que el módulo lleva tras la adopción:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

El estado mutable del engine (`config`, `current.json`, journal, lock) vive en
Tier-2, `/data/adb/<modid>/vdlu/`, fuera del dir del módulo, `config.default` lo siembra
en el primer run.

## 1. Vendorizar el engine

Copia el engine, el verify shim y el verificador por-ABI dentro de `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Entrega solo las ABIs que soportas, `customize.sh` puede podar `verify/` a la ABI del
dispositivo en el momento de la instalación.

## 2. Generar una clave de firma (una sola vez)

```sh
producer/vdlu-keygen <id> ./keys
```

Esto emite `<id>.pem` (privada, mantenla fuera de todo dispositivo y de cualquier push a repo),
`<id>.pub` (PEM, solo del lado PC) y `<id>.pub.raw` (RAW de 32 bytes, para el keyring del dispositivo).

## 3. Embeber la clave pública raw

El keyring del dispositivo guarda la clave **RAW de 32 bytes**, nunca el PEM (`ed25519-mini`
no puede leer un PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

El keyring es estable entre releases (solo cambia en la rotación de clave): en un
re-vendor, **verifica, no sobrescribas**.

## 4. Escribir la config

Entrega `config.default` en `<module>/vdlu/` (siembra el `config` de Tier-2 en el primer run):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

Usa `profile=trusted` solo para una fuente privada `file://`/SSH (verify best-effort;
el sha256 de cada blob se sigue verificando). Cualquier valor que no sea el literal `trusted`
se trata como `hardened` (fail-closed).

## 5. Cablear los triggers

**En reboot** (`auto_on_reboot`): llama al engine pre-zygote desde `post-fs-data.sh`
para que los archivos staged (un `.so`, un overlay de `/system`, un `sepolicy.rule`) entren con
cero reboots extra:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Al abrir la WebUI** (`auto_on_webui_open`): cablea el panel Updates drop-in en tu
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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` se vendorizan desde `webui/`, se puede agregar una traducción con
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Firmar el feed en tu workflow de release

En cada release, empaqueta el árbol final del módulo y firma el manifiesto. Mantén la clave privada
en la máquina del operador, nunca en la CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Entregar el baseline

Genera `baseline.json` sobre el árbol entregado y colócalo en `<module>/vdlu/baseline.json`.
Siembra `current.json` en una instalación fresca para que el dispositivo nazca "al día" (sin
re-fetch). Es una **semilla local confiable**: sin firma y sin clave, así que la CI puede construirlo
sin tocar jamás la clave de firma:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

No es fatal si está ausente (el dispositivo simplemente parte de `0` en la primera actualización).

---

Esa es toda la adopción. `sh -n <module>/vdlu/update.sh` debe pasar, prueba el
producer y el engine de punta a punta como se muestra en [`PRODUCER.md`](PRODUCER.md) y el
README raíz antes de entregar.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas, consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
