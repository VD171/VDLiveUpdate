# WebUI

VDLU, isteğe bağlı bir yerleştirilebilir (drop-in) WebUI widget'ı ile gelir: bir KernelSU veya APatch kök yöneticisi WebUI'si için küçük bir "Updates" paneli. Kullanıcıya bir Check düğmesi, bir Update now düğmesi, iptalli canlı bir ilerleme bildirimi (toast), bir yeniden başlatma afişi ve bir ayarlar paneli verir, hepsi kullanıcı asla bir terminale dokunmadan.

Bu **vanilla JavaScript**'tir: çerçeve yok, yapı adımı yok, CDN yok. Üç dosya:

| Dosya | Nedir |
|---|---|
| `vdlu.js` | widget; `window.VDLU`'yu açığa çıkarır |
| `vdlu.css` | bildirim, afiş ve panel için stiller (koyu tema, ana bilgisayarın CSS değişkenlerini miras alır) |
| `demo.html` | tüm arayüzün düz bir tarayıcıda çalışması için cihaz köprüsünü taklit eden bağımsız bir sayfa |

Widget tamamen isteğe bağlıdır. [[Engine]] önyükleme tetikleyicilerinden kendi başına gayet iyi çalışır; WebUI sadece üzerine dostça bir yüzdür. Bir modüle bağlama için bkz. [[Quick Start]].

---

## Arayüz motorla nasıl konuşur: `ksu.exec` köprüsü

Widget asla kendisi ayrıcalıklı bir şey yapmaz. Bir kabuk komutu oluşturur ve onu kök yöneticisinin `ksu.exec` köprüsüne teslim eder; bu köprü onu kök olarak çalıştırır ve stdout / stderr / çıkış kodunu döndürür. Panelin gösterdiği her şey motorun yazdığı dosyalardan geri okunur.

Widget o köprüyü bir `Promise` döndüren tek bir `exec(cmd)` fonksiyonuna sarar:

- komut 0 ile çıktığında stdout ile **çözümlenir (resolve)**
- aksi halde stderr (veya `rc=N`) ile **reddedilir (reject)**

Her komut, widget tarafından birleştirilen sözleşmenin ortamını taşır:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Birkaç somut çağrı:

- **Bir güncelleme başlat:** `update.sh run`, **arka planda** (`(... &)`) başlatılır, böylece arayüz asla uzun bir indirme ile engellenmez.
- **İlerlemeyi oku:** `cat $VDLU_DIR/journal.json`'un hafif bir yoklaması (saniyede bir kez civarı).
- **İptal:** `touch $VDLU_DIR/cancel` (motor bir sonraki güvenli noktada durur).
- **Yapılandırma:** `$VDLU_DIR/config`'i (key=value) oku ve yaz, sırayı ve bilinmeyen anahtarları koruyarak ve yalnızca kullanıcının değiştirdiği anahtarlara dokunarak.

Ana bilgisayar kendi `exec`, `toast` ve `confirm` yardımcılarını `init()`'e geçerse, widget ana bilgisayarın kendi serileştirilmiş komut kuyruğu ve görsellerinden geçer, böylece o WebUI'nin geri kalanı gibi görünür ve davranır. Atlanırlarsa, widget doğrudan `ksu.exec`'i çağırmaya geri döner ve kendi mini bildirimini enjekte eder.

---

## İlerleme bildirimi (iptal ile)

Bir güncelleme çalıştığında, widget engellemeyen bir köşe bildirimi gösterir ve `journal.json`'u yoklar. Bildirim, motorun durum makinesini yansıtır:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Bir ilerleme çubuğu artı bir `phase done/total - current file - bytes` satırı işler ve boyunca bir **Cancel** düğmesi taşır. Son durumların her biri kendi işlemini alır:

- **DONE** -> yeşil bir bildirim, "vX applied - all verified".
- **PENDING_REBOOT** -> yeşil bir bildirim artı kalıcı bir yeniden başlatma afişi (aşağıda).
- **ERROR** -> `journal.error` veya stderr'den gelen nedenle kırmızı bir bildirim, Retry sunar. Asla başarıyı taklit etmez.
- **Cancelled** -> kehribar bir bildirim, "cancelled - N/M applied, resumable", **Resume** sunar.
- **DEFERRED** -> yumuşak mavi bir bilgi bildirimi, "download deferred, waiting for the allowed network". Bu zararsız bir ağ politikası beklemesidir, bir hata değil; doğru ağda bir sonraki kontrol veya önyüklemede devam eder.

Yoklama savunmacıdır. Yarı yazılmış bir günlük (motor eşzamanlı yazar), yanlış ayrıştırılmak yerine o tik için göz ardı edilir. İlerleme görüldükten sonra günlük yok olursa, bu commit'in onu temizlediği anlamına gelir: widget DONE bildirir. Günlük baştan 8 tik boyunca yoksa, "no response" bildirir. Ve günlük 20 tik boyunca aynı değerlerde donarsa, widget motorun `lock.d`'sini kontrol eder: kilit canlıysa bu sadece yavaş bir tek blob alışıdır ve bildirim beklemeye devam eder; kilit ölüyse çalıştırma ortada ölmüştür, bu yüzden widget "updating"de sonsuza dek dönmek yerine bir Resume düğmesiyle bir hata yüzeye çıkarır.

---

## Yeniden başlatma afişi

Bazı dosyalar canlı bir sistemde değiştirilemez: bir `.so`, bir `/system` katmanı, bir `sepolicy.rule`. Motor bunları aşamalar ve işlemi `PENDING_REBOOT` olarak işaretler. Widget ardından **kalıcı bir üst afiş** gösterir: "Reboot to activate the new `.so` (vX)". Aşamalanmış dosyalar bir sonraki önyüklemede değiştirilene kadar kalır. WebUI açılışında afiş günlükten yeniden değerlendirilir, böylece arayüzü kapatıp yeniden açan bir kullanıcı onu yine de görür. Önyüklemede ne olacağı için bkz. [[Reboot Handling]].

Afişin, (bir `.so` plana girer girmez doğru olan) `reboot_pending` bayrağından değil, son durum `PENDING_REBOOT`'tan tetiklendiğine dikkat edin. Bu, afişin herhangi bir şey gerçekten aşamalanmadan önce çalıştırma ortasında belirmesini önler.

---

## "Updates" paneli: kategori başına bağımsız anahtarlar

`mountUpdatesPanel(el)`, ana bilgisayarın sağladığı boş bir `<div>`'e ayarlar panelini işler. Üç bölümü vardır ve her denetim bağımsızdır ve kendi başına kaydeder:

**Eylemler**
- **Check for updates** -> `check` çalıştırır, sonucu satır içinde gösterir (güncel / feed'den daha yeni / dosya sayısı ve bir yeniden başlatma etiketi ile güncelleme mevcut).
- **Update now** -> `run` artı ilerleme bildirimini ateşler.

**Otomasyon** (bağımsız anahtarlar, her biri çevrildiği anda `config`'e yazılır)
- **On WebUI open** (`auto_on_webui_open`) -> arayüz açıldığında sessiz bir güncelleme çalıştır.
- **On reboot** (`auto_on_reboot`) -> önyüklemede zygote öncesinde uygula.
- **Boot retry every (s)** ve **Boot retry up to (min)** -> cihaz çevrimdışı önyüklendiğinde bir manifesto alışını yeniden denemek için sayısal alanlar.

**Kaynak**
- `source` (feed URL'si), `channel` (stable / canary), `profile` (trusted / hardened) ve `net_policy`'ye eşlenen bir **Network** seçimi (Wi-Fi + mobil / yalnızca Wi-Fi / yalnızca mobil).

Anahtarlar ve sayısal alanlar hemen kaydeder ve yazma başarısız olursa görsel olarak geri döner. Kaynak bölümündeki metin ve seçim alanları kendilerini kirli (dirty) olarak işaretler ve açık bir Save düğmesinde birlikte kaydeder. Panel yalnızca kullanıcının dokunduğu anahtarları yeniden yazar, böylece bilinmeyen veya gelecekteki yapılandırma anahtarları korunur.

### Otomatik açılış davranışı

`onWebUIOpen()`, ana bilgisayar yüklenirken çağrılır. Günlüğü değerlendirir (yeniden başlatma afişini gösterir veya önceki bir oturum tarafından bırakılan son durum olmayan bir işlem için Resume sunar), ardından `auto_on_webui_open=1` ise önce **sessiz** bir `check()` çalıştırır. Kalıcı ilerleme bildirimi ve asıl `run` yalnızca yapılacak gerçek bir indirme olduğunda (`update && fetch > 0`) ateşlenir. Cihaz güncelse veya feed'in ilerisindeyse, sonuç panelde satır içinde gösterilir ve ekranda hiçbir bildirim bırakılmaz, böylece otomatik güncelleme manuel düğme kadar müdahaleci olmayan olur.

---

## i18n (dil başına dizeler)

Her arayüz dizesi varsayılan olarak **İngilizce**'dir, bu da herkese açık çok dilli modüller için nötr seçimdir. Tam anahtar haritası `vdlu.js`'deki `DEFAULT_I18N` nesnesinde yaşar (ayrıca `VDLU.i18n` olarak açığa çıkar). Bir ana bilgisayar, `init({ i18n: ... })`'e bir harita geçerek herhangi bir anahtar alt kümesini geçersiz kılar:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- **Kısmi** bir harita uygundur: eksik herhangi bir anahtar İngilizce varsayılana geri döner.
- Aşama ve durum etiketleri `ph_<phase>` ve `st_<STATE>` anahtarlarını kullanır; geri kalanlar `cancel`, `updateNow` gibi düz anahtarlardır.
- İşlenmiş bir çeviri (`i18n/pt-BR.js`) bir şablon olarak gönderilir; yeni bir dil sadece aynı şekilde bir `i18n/<lang>.js` dosyasıdır veya ana bilgisayar haritayı kendi i18n sisteminden oluşturur.

---

## demo.html: arayüzü cihaz olmadan çalıştır

`demo.html`, `ksu.exec` köprüsünü taklit eder, böylece tam olarak aynı `vdlu.js` ve `vdlu.css` düz bir tarayıcıda, kök ve telefon olmadan çalışır:

```sh
xdg-open webui/demo.html
```

Taklit, `update.sh`'yi ve gelişen bir `journal.json`'u simüle eder ve düğmeleri senaryolar arasında geçiş yapar: DONE'a kadar canlı bir güncelleme, bir `reboot_pending` bitişi, ortada bir hata ve iptal edilebilir bir çalıştırma. Arayüzü görmenin ve üzerinde yinelemenin en hızlı yoludur ve widget'ı bir modüle gömmeden önce kontrol ettiğiniz şeydir.

---

## Bir modüle bağlama (WebUI açılış tetikleyicisi)

Ana bilgisayarın `index.html`'si iki dosyayı yükler ve üç fonksiyon çağırır:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

Ana bilgisayarın yalnızca Tier-2 yollarını sağlaması ve panel için bir boş `<div>` ayırması gerekir; bildirim ve afiş widget tarafından `document.body`'ye enjekte edilir. `onWebUIOpen()` WebUI açılış tetikleyicisidir: yeniden başlatma afişini değerlendiren, kesintiye uğramış bir işlemde Resume sunan ve `auto_on_webui_open` ayarlandığında sessiz otomatik güncellemeyi çalıştıran şeydir.

### Tek kaynak, bayt bayt yeniden gömülmüş

`vdlu.js` ve `vdlu.css`, **kanonik kopyadır**. Widget'ı gömen bir modül, bu dosyaları değiştirilmeden kendi `webroot/`'una yeniden gömer; kendi kopyasını asla yerinde düzenlemez. Yeni bir özellik kanonik dosyalarda doğar ve yeniden gömme ile aşağı akar. Gömülü bir kopyayı düzenlemek sessiz kayma (drift) üretir (bu oldu: bayat bir kopyada `net_policy`, DEFERRED bildirimi ve önyükleme yeniden deneme alanları eksikti). Kaynak ağacındaki bir eşlik gardiyanı her kopyayı bulur ve sapanları işaretler veya yeniden gömer, yalnızca widget'ı kapsar; keyring'in kendi doğrula-kopyalama cadansı vardır.

---

### Herkese açık API (`window.VDLU`)

| Fonksiyon | Yapar |
|---|---|
| `init(opts)` | widget'ı yapılandır; `window.VDLU` döndürür |
| `onWebUIOpen()` | yüklemede çağır: afiş, Resume teklifi ve sessiz otomatik güncelleme |
| `mountUpdatesPanel(el)` | Updates panelini `el`'e işle (id dizesi veya eleman) |
| `check()` | `update.sh check` çalıştır; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | arka planda `run` artı Cancel'li ilerleme bildirimini ateşle |
| `cancel()` | `$VDLU_DIR/cancel` oluştur (motor bir güvenli noktada durur) |
| `resume()` | mevcut işlemi devam ettir artı bir bildirim |
| `refreshBanner()` | kalıcı bekleyen-yeniden-başlatma afişini yeniden değerlendir |

---

Ayrıca bakınız: widget'ın çalıştırdığı komutlar için [[Engine]], tam benimseme adımları için [[Quick Start]] ve afişin neyi beklediği için [[Reboot Handling]].
