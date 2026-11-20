# Quick Start

Questa è la checklist di adozione: come vendorizzare **VDLiveUpdate (VDLU)** in un
modulo KernelSU / APatch / Magisk. VDLU non è un modulo esso stesso. Viene inserito in
`<module>/vdlu/` e viene spedito dentro lo zip del tuo modulo, così un modulo installato può
aggiornarsi flashlessly da un feed firmato che pubblichi.

Ovunque, sostituisci `<id>` con l'id della tua chiave di firma, `<abi>` con l'/gli ABI del
dispositivo che spedisci (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), e `<module>`
con l'albero del tuo modulo.

Per il razionale dietro ogni pezzo, vedi [[Engine]], [[Producer]], [[WebUI]] e
[[Security and Trust Model]].

## Il layout `vdlu/` dentro il modulo

Questo è l'albero esatto che il tuo modulo porta dopo l'adozione:

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

Lo stato mutabile dell'engine (`config`, `current.json`, journal, lock, cache dei blob)
vive in Tier-2 in `/data/adb/<modid>/vdlu/`, fuori dalla directory del modulo.
`config.default` semina quel `config` Tier-2 alla prima esecuzione. Vedi [[Engine]] per il
layout di stato completo.

## 1. Vendorizza l'engine

Copia l'engine, lo shim di verifica e il binario verificatore per-ABI in
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Spedisci solo gli ABI che supporti. Il tuo `customize.sh` può potare `verify/` fino
all'ABI del dispositivo in fase di installazione.

## 2. Genera una chiave di firma (una tantum)

```sh
producer/vdlu-keygen <id> ./keys
```

Questo emette tre file:

- `<id>.pem` - la chiave privata. Tienila fuori da ogni dispositivo e fuori da qualsiasi push di repo
  o secret di CI.
- `<id>.pub` - la chiave pubblica PEM. Solo lato PC (usata da `vdlu-sign`).
- `<id>.pub.raw` - la chiave pubblica RAW di 32 byte, per il keyring del dispositivo.

Vedi [[Security and Trust Model]] per perché la separazione conta.

## 3. Incorpora la chiave pubblica raw

Il keyring del dispositivo contiene la chiave **RAW di 32 byte**, mai il PEM. `ed25519-mini`
non può leggere un PEM, quindi copiare qui il PEM rompe la verifica sul dispositivo:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Il keyring è stabile fra le release: cambia solo su rotazione di chiave. In una
ri-vendorizzazione, **verificalo, non sovrascriverlo**.

## 4. Scrivi la config

Spedisci `config.default` in `<module>/vdlu/`. Semina il `config` Tier-2 alla prima
esecuzione:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Usa `profile=trusted` solo per una sorgente privata `file://` o SSH (la verifica è
best-effort li, ma lo sha256 di ogni blob viene comunque controllato). Qualsiasi valore diverso
dal letterale `trusted` viene trattato come `hardened`, fail-closed. Vedi
[[Security and Trust Model]] per la semantica completa dei profili.

## 5. Collega i trigger

**Al riavvio** (`auto_on_reboot`): chiama l'engine pre-zygote da
`post-fs-data.sh`, così i file di classe reboot in staging (un `.so`, un overlay `/system`,
una `sepolicy.rule`) vengono scambiati senza un riavvio extra:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**All'apertura della WebUI** (`auto_on_webui_open`): collega il pannello Updates drop-in nel tuo
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

`vdlu.js` e `vdlu.css` sono vendorizzati da `webui/`. Una traduzione può essere aggiunta
con `i18n: window.VDLU_I18N_<LANG>`. Vedi [[WebUI]] per il contratto del pannello.

## 6. Firma il feed nel tuo workflow di release

A ogni release, impacchetta l'albero finale del modulo e firma il manifest. Tieni la chiave
privata sulla macchina dell'operatore, mai in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` è content-addressed e deduplicante, quindi la pubblicazione è incrementale:
i blob invariati non vengono mai ri-pushati. Vedi [[Producer]] e [[Feed Format]].

## 7. Spedisci la baseline

Genera `baseline.json` sull'albero spedito e posizionalo in
`<module>/vdlu/baseline.json`. Semina `current.json` su un'installazione fresca, così il
dispositivo nasce "aggiornato" e non riscarica la propria versione spedita. È un
**seme locale fidato**: non firmato e keyless, così la CI può costruirlo senza mai
toccare la chiave di firma:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

È non fatale se assente: il dispositivo semplicemente parte dalla versione `0` al
primo aggiornamento.

---

Questa è tutta l'adozione. Prima di spedire, `sh -n <module>/vdlu/update.sh`
deve passare, e dovresti testare il producer e l'engine end-to-end come mostrato in
[[Contributing]] e [[Producer]].
