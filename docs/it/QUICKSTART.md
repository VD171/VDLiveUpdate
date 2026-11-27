> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · Italiano · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart di adozione VDLU

Una checklist copia-incolla per vendorizzare **VDLiveUpdate** in un modulo. VDLU non è un
modulo esso stesso: viene inserito in `<module>/vdlu/` e spedito dentro lo zip del tuo
modulo. Per il rationale completo vedi [`INTERFACES.md`](INTERFACES.md) (il contratto di
costura), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) e [`WEBUI.md`](WEBUI.md).

Sostituisci `<id>` con l'id della tua chiave di firma, `<abi>` con l'/le ABI del
dispositivo che spedisci (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), e `<module>` con
l'albero del tuo modulo.

## Layout di destinazione

Questo è l'esatto albero `vdlu/` che il modulo porta dopo l'adozione:

```
<module>/
├── module.prop
├── post-fs-data.sh            # trigger pre-zygote: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # la tua WebUI, che collega il pannello Updates (passo 5)
└── vdlu/
    ├── update.sh              # l'engine (vendorizzato byte per byte)
    ├── vdlu-verify            # shim di verifica ed25519 (device-side, niente openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # binario verificatore per-ABI
    ├── keyring/
    │   └── <id>.pub           # chiave pubblica RAW da 32 byte (MAI il PEM)
    ├── config.default         # profile + source + default di automazione
    └── baseline.json          # seme di installazione (non firmato, senza chiave)
```

Lo stato mutabile dell'engine (`config`, `current.json`, journal, lock) risiede in
Tier-2, `/data/adb/<modid>/vdlu/`, fuori dalla directory del modulo, `config.default` lo
semina alla prima esecuzione.

## 1. Vendorizza l'engine

Copia l'engine, lo shim di verifica e il verificatore per-ABI in `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Spedisci solo le ABI che supporti, `customize.sh` può potare `verify/` all'ABI del
dispositivo al momento dell'installazione.

## 2. Genera una chiave di firma (una tantum)

```sh
producer/vdlu-keygen <id> ./keys
```

Questo emette `<id>.pem` (privata, tienila fuori da ogni dispositivo e da ogni push su
repo), `<id>.pub` (PEM, solo PC-side) e `<id>.pub.raw` (RAW 32 byte, per il keyring del
dispositivo).

## 3. Incorpora la chiave pubblica grezza

Il keyring del dispositivo contiene la chiave **RAW da 32 byte**, mai il PEM
(`ed25519-mini` non può leggere un PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Il keyring è stabile tra le release (cambia solo in caso di rotazione delle chiavi): su un
re-vendor, **verificalo, non sovrascriverlo**.

## 4. Scrivi la config

Spedisci `config.default` in `<module>/vdlu/` (semina la `config` in Tier-2 alla prima
esecuzione):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # feed pubblico: firma obbligatoria, downgrade bloccato
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

Usa `profile=trusted` solo per una sorgente privata `file://`/SSH (verify best-effort, lo
sha256 di ogni blob viene comunque controllato). Qualsiasi valore diverso dal letterale
`trusted` viene trattato come `hardened` (fail-closed).

## 5. Collega i trigger

**Al reboot** (`auto_on_reboot`): chiama l'engine pre-zygote da `post-fs-data.sh` così i
file in stage (una `.so`, un overlay `/system`, una `sepolicy.rule`) entrano con lo swap
senza un reboot in più:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**All'apertura della WebUI** (`auto_on_webui_open`): collega il pannello Updates drop-in
nel tuo `webroot/index.html`:

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
  VDLU.onWebUIOpen();                                             // valuta journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // la scheda "Updates"
</script>
```

(`vdlu.js` / `vdlu.css` sono vendorizzati da `webui/`, una traduzione può essere aggiunta
con `i18n: window.VDLU_I18N_<LANG>`.)

## 6. Firma il feed nel tuo workflow di release

Ad ogni release, pacchettizza l'albero finale del modulo e firma il manifest. Tieni la
chiave privata sulla macchina dell'operatore, mai in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = path spariti da prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# pubblica ./out/{manifest.json,blobs/} su <source>
```

## 7. Spedisci la baseline

Genera `baseline.json` sull'albero spedito e posizionala in
`<module>/vdlu/baseline.json`. Semina `current.json` su un'installazione pulita così il
dispositivo nasce "corrente" (niente re-fetch). È un **seme locale fidato**: non firmata e
senza chiave, così la CI può costruirla senza mai toccare la chiave di firma:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Non è fatale se assente (il dispositivo parte semplicemente da `0` al primo aggiornamento).

---

Questa è l'intera adozione. `sh -n <module>/vdlu/update.sh` deve passare, testa il
producer e l'engine end-to-end come mostrato in [`PRODUCER.md`](PRODUCER.md) e nel README
di root prima di spedire.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti, vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
