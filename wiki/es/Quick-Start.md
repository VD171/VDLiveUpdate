# Quick Start

Esta es la lista de verificación de adopción: cómo incorporar **VDLiveUpdate (VDLU)** en un
módulo de KernelSU / APatch / Magisk. VDLU no es un módulo en sí mismo. Se coloca en
`<module>/vdlu/` y se envía dentro del zip de tu módulo, de modo que un módulo instalado pueda
actualizarse sin flasheo desde un feed firmado que tú publicas.

A lo largo de todo, reemplaza `<id>` con el id de tu clave de firma, `<abi>` con la
ABI(s) del dispositivo que envías (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), y `<module>`
con el árbol de tu módulo.

Para el razonamiento detrás de cada pieza, ver [[Engine]], [[Producer]], [[WebUI]] y
[[Security and Trust Model]].

## La disposición `vdlu/` dentro del módulo

Este es el árbol exacto que tu módulo lleva después de la adopción:

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

El estado mutable del motor (`config`, `current.json`, journal, lock, cache de blobs)
vive en Tier-2 en `/data/adb/<modid>/vdlu/`, fuera del directorio del módulo.
`config.default` siembra ese `config` Tier-2 en la primera ejecución. Ver [[Engine]] para la
disposición de estado completa.

## 1. Incorporar el motor

Copia el motor, el shim de verificación y el binario verificador por ABI en
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Envía solo las ABIs que soportas. Tu `customize.sh` puede podar `verify/` hasta
la ABI del dispositivo en el momento de la instalación.

## 2. Generar una clave de firma (una sola vez)

```sh
producer/vdlu-keygen <id> ./keys
```

Esto emite tres archivos:

- `<id>.pem` - la clave privada. Mantenla fuera de todo dispositivo y fuera de cualquier push a repo
  o secreto de CI.
- `<id>.pub` - la clave pública PEM. Solo del lado PC (usada por `vdlu-sign`).
- `<id>.pub.raw` - la clave pública de 32 bytes EN CRUDO, para el keyring del dispositivo.

Ver [[Security and Trust Model]] para por qué importa la división.

## 3. Embeber la clave pública en crudo

El keyring del dispositivo contiene la clave de **32 bytes EN CRUDO**, nunca el PEM. `ed25519-mini`
no puede leer un PEM, de modo que copiar el PEM aquí rompe la verificación en el dispositivo:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

El keyring es estable a través de las releases: solo cambia en una rotación de clave. En una
re-incorporación, **verifícalo, no lo sobrescribas**.

## 4. Escribir la config

Envía `config.default` en `<module>/vdlu/`. Siembra el `config` Tier-2 en la primera
ejecución:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Usa `profile=trusted` solo para una fuente privada `file://` o SSH (la verificación es
de mejor esfuerzo allí, pero el sha256 de cada blob aún se comprueba). Cualquier valor distinto
del literal `trusted` se trata como `hardened`, a prueba de fallos. Ver
[[Security and Trust Model]] para la semántica completa de perfiles.

## 5. Conectar los disparadores

**En el reinicio** (`auto_on_reboot`): llama al motor pre-zygote desde
`post-fs-data.sh`, de modo que los archivos de clase reboot por etapas (un `.so`, un overlay de `/system`,
un `sepolicy.rule`) se intercambien sin un reinicio extra:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**En la apertura de la WebUI** (`auto_on_webui_open`): conecta el panel de Updates de inserción directa en tu
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

`vdlu.js` y `vdlu.css` se incorporan desde `webui/`. Una traducción se puede agregar
con `i18n: window.VDLU_I18N_<LANG>`. Ver [[WebUI]] para el contrato del panel.

## 6. Firmar el feed en tu flujo de publicación

En cada release, empaqueta el árbol final del módulo y firma el manifiesto. Mantén la clave privada
en la máquina del operador, nunca en CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` es direccionado por contenido y deduplicante, de modo que publicar es incremental:
los blobs sin cambios nunca se vuelven a subir. Ver [[Producer]] y [[Feed Format]].

## 7. Enviar la baseline

Genera `baseline.json` sobre el árbol enviado y colócalo en
`<module>/vdlu/baseline.json`. Siembra `current.json` en una instalación nueva, de modo que el
dispositivo nace "al día" y no vuelve a descargar su propia versión enviada. Es una
**semilla local confiable**: sin firma y sin clave, de modo que CI puede construirla sin nunca
tocar la clave de firma:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Es no fatal si está ausente: el dispositivo simplemente parte de la versión `0` en la
primera actualización.

---

Esa es toda la adopción. Antes de enviar, `sh -n <module>/vdlu/update.sh`
debe pasar, y deberías probar el productor y el motor de principio a fin como se muestra en
[[Contributing]] y [[Producer]].
