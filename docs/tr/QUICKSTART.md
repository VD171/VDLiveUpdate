> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · Türkçe · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU benimseme hızlı başlangıcı

**VDLiveUpdate**'i bir modüle vendor etmek için kopyala-yapıştır bir kontrol listesi. VDLU başlı başına bir
modül değildir: `<module>/vdlu/` içine bırakılır ve modülünüzün zip'inin içinde gönderilir. Tam gerekçe için
[`INTERFACES.md`](INTERFACES.md) (seam sözleşmesi), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) ve
[`WEBUI.md`](WEBUI.md)'ye bakın.

`<id>`'yi imzalama anahtarı id'nizle, `<abi>`'yi gönderdiğiniz cihaz ABI'leriyle (`arm64-v8a`,
`armeabi-v7a`, `x86_64`, `x86`) ve `<module>`'ü modül ağacınızla değiştirin.

## Hedef düzen

Benimsemeden sonra modülün taşıdığı tam `vdlu/` ağacı budur:

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

Engine'in değişken durumu (`config`, `current.json`, günlük, kilit), modül dizininin dışında, Tier-2'de,
`/data/adb/<modid>/vdlu/`'da bulunur, `config.default` onu ilk çalıştırmada tohumlar.

## 1. Engine'i vendor edin

Engine'i, verify shim'ini ve ABI başına verifier'ı `<module>/vdlu/` içine kopyalayın:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Yalnızca desteklediğiniz ABI'leri gönderin, `customize.sh`, kurulum sırasında `verify/`'ı cihazın ABI'sine
budayabilir.

## 2. Bir imzalama anahtarı üretin (tek seferlik)

```sh
producer/vdlu-keygen <id> ./keys
```

Bu, `<id>.pem` (priv, her cihazdan ve her repo push'undan uzak tutun), `<id>.pub` (PEM, yalnızca PC tarafı)
ve `<id>.pub.raw` (RAW 32 bayt, cihaz keyring'i için) yayar.

## 3. Ham public anahtarı gömün

Cihaz keyring'i **RAW 32 baytlık** anahtarı tutar, asla PEM'i değil (`ed25519-mini` bir PEM okuyamaz):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring, sürümler boyunca kararlıdır (yalnızca anahtar rotasyonunda değişir): bir yeniden-vendor'da onu
**doğrulayın, üzerine yazmayın**.

## 4. Config'i yazın

`config.default`'u `<module>/vdlu/` içinde gönderin (ilk çalıştırmada Tier-2 `config`'ini tohumlar):

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

`profile=trusted`'ı yalnızca özel bir `file://`/SSH kaynağı için kullanın (verify best-effort, her blob'un
sha256'sı yine de kontrol edilir). Tam `trusted` dışındaki herhangi bir değer `hardened` olarak ele alınır
(fail-closed).

## 5. Tetikleyicileri bağlayın

**Yeniden başlatmada** (`auto_on_reboot`): sahnelenmiş dosyaların (bir `.so`, bir `/system` overlay'i, bir
`sepolicy.rule`) fazladan bir yeniden başlatma olmadan swap olması için engine'i `post-fs-data.sh`'den
pre-zygote çağırın:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI açılışında** (`auto_on_webui_open`): drop-in Updates panelini `webroot/index.html`'inizde bağlayın:

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

(`vdlu.js` / `vdlu.css`, `webui/`'dan vendor edilir, bir çeviri `i18n: window.VDLU_I18N_<LANG>` ile
eklenebilir.)

## 6. Beslemeyi release iş akışınızda imzalayın

Her release'te, nihai modül ağacını paketleyin ve manifesti imzalayın. Özel anahtarı operatör makinesinde
tutun, asla CI'da değil:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Baseline'ı gönderin

Gönderilen ağaç üzerinde `baseline.json` üretin ve onu `<module>/vdlu/baseline.json`'a yerleştirin. Taze bir
kurulumda `current.json`'u tohumlar, böylece cihaz "güncel" doğar (yeniden getirme yok). Bu bir **yerel
güvenilir tohumdur**: imzasız ve anahtarsız, bu yüzden CI onu imzalama anahtarına hiç dokunmadan
oluşturabilir:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Yoksa ölümcül değildir (cihaz ilk güncellemede sadece `0`'dan başlar).

---

Benimseme bundan ibaret. `sh -n <module>/vdlu/update.sh` geçmelidir, göndermeden önce üreticiyi ve engine'i
[`PRODUCER.md`](PRODUCER.md) ve kök README'de gösterildiği gibi uçtan uca test edin.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
