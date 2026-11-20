# Hızlı Başlangıç

Bu benimseme kontrol listesidir: **VDLiveUpdate (VDLU)**'yu bir
KernelSU / APatch / Magisk modülüne nasıl gömeceğiniz. VDLU kendi başına bir modül
değildir. `<module>/vdlu/` içine yerleştirilir ve modülünüzün zip'inin içinde gönderilir,
böylece kurulu bir modül, yayınladığınız imzalı bir feed'den kendini flash gerektirmeden
güncelleyebilir.

Baştan sona, `<id>`'yi imzalama anahtarı id'nizle, `<abi>`'yi gönderdiğiniz cihaz
ABI'leri ile (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`) ve `<module>`'ü
modül ağacınızla değiştirin.

Her parçanın arkasındaki mantık için bkz. [[Engine]], [[Producer]], [[WebUI]] ve
[[Security and Trust Model]].

## Modül içi `vdlu/` düzeni

Bu, modülünüzün benimsemeden sonra taşıdığı tam ağaçtır:

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

Motorun değişebilir durumu (`config`, `current.json`, günlük, kilit, blob önbelleği)
modül dizininin dışında, `/data/adb/<modid>/vdlu/`'da Tier-2'de yaşar.
`config.default`, ilk çalıştırmada o Tier-2 `config`'ini tohumlar. Tam durum düzeni
için bkz. [[Engine]].

## 1. Motoru göm

Motoru, verify shim'ini ve ABI başına doğrulayıcı ikilisini
`<module>/vdlu/` içine kopyala:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Yalnızca desteklediğiniz ABI'leri gönderin. `customize.sh`'niz kurulum zamanında
`verify/`'ı cihazın ABI'sine budayabilir.

## 2. Bir imzalama anahtarı üret (tek seferlik)

```sh
producer/vdlu-keygen <id> ./keys
```

Bu üç dosya yayar:

- `<id>.pem` - özel anahtar. Onu her cihazdan uzak ve herhangi bir repo
  gönderimi veya CI gizli bilgisinin dışında tutun.
- `<id>.pub` - PEM açık anahtar. Yalnızca PC tarafı (`vdlu-sign` tarafından kullanılır).
- `<id>.pub.raw` - cihaz keyring'i için HAM 32 baytlık açık anahtar.

Ayrımın neden önemli olduğu için bkz. [[Security and Trust Model]].

## 3. Ham açık anahtarı göm

Cihaz keyring'i **HAM 32 baytlık** anahtarı tutar, asla PEM'i değil. `ed25519-mini`
bir PEM okuyamaz, bu yüzden PEM'i buraya kopyalamak cihaz üstü doğrulamayı bozar:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring yayınlar arasında kararlıdır: yalnızca anahtar döndürmede değişir. Bir
yeniden gömmede, **onu doğrula, üzerine yazma**.

## 4. Yapılandırmayı yaz

`config.default`'u `<module>/vdlu/` içinde gönder. İlk çalıştırmada Tier-2 `config`'ini
tohumlar:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

`profile=trusted`'ı yalnızca özel bir `file://` veya SSH kaynağı için kullanın (doğrulama
orada elden geldiğincedir, ancak her blob'un sha256'sı yine de kontrol edilir). Sözlük
anlamıyla `trusted` dışındaki herhangi bir değer, hata durumunda kapalı olacak şekilde
`hardened` olarak ele alınır. Tam profil semantiği için bkz.
[[Security and Trust Model]].

## 5. Tetikleyicileri bağla

**Yeniden başlatmada** (`auto_on_reboot`): motoru `post-fs-data.sh`'den zygote öncesi
çağır, böylece aşamalanmış yeniden başlatma sınıfı dosyalar (bir `.so`, bir `/system`
katmanı, bir `sepolicy.rule`) ekstra bir yeniden başlatma olmadan değiştirilir:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI açılışında** (`auto_on_webui_open`): yerleştirilebilir Updates panelini
`webroot/index.html`'nizde bağlayın:

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

`vdlu.js` ve `vdlu.css`, `webui/`'den gömülür. Bir çeviri
`i18n: window.VDLU_I18N_<LANG>` ile eklenebilir. Panel sözleşmesi için bkz. [[WebUI]].

## 6. Feed'i yayın iş akışınızda imzala

Her yayında, son modül ağacını paketleyin ve manifestoyu imzalayın. Özel anahtarı
operatör makinesinde tutun, asla CI'da değil:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` içerik adresli ve tekilleştiricidir, bu yüzden yayınlama artımlıdır:
değişmemiş blob'lar asla yeniden gönderilmez. Bkz. [[Producer]] ve [[Feed Format]].

## 7. Temel çizgiyi gönder

Gönderilen ağaç üzerinde `baseline.json` oluşturun ve onu
`<module>/vdlu/baseline.json`'a yerleştirin. Yeni bir kurulumda `current.json`'u
tohumlar, böylece cihaz "güncel" doğar ve kendi gönderilen sürümünü yeniden almaz. Bu bir
**yerel güvenilir tohumdur**: imzasız ve anahtarsız, böylece CI onu imzalama anahtarına
asla dokunmadan oluşturabilir:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Yoksa ölümcül değildir: cihaz ilk güncellemede basitçe `0` sürümünden
başlar.

---

Tüm benimseme bu kadar. Göndermeden önce `sh -n <module>/vdlu/update.sh`
geçmelidir ve [[Contributing]] ve [[Producer]]'da gösterildiği gibi üreticiyi ve motoru
baştan sona test etmelisiniz.
