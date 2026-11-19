> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · Türkçe · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI widget'ı (flashless güncelleme)

Bir KernelSU/APatch root yöneticisi WebUI'si için VDLU (VD Live Update) arayüzü. Vanilla JS, framework yok,
derleme yok, CDN yok. Drop-in: ana makinenin `index.html`'i 2 dosyayı yükler ve API'yi çağırır.

Yakınsama: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Dosyalar

| Dosya | Ne |
|---|---|
| `vdlu.js` | bileşen - `window.VDLU`'yu açığa çıkarır |
| `vdlu.css` | ilerleme toast'u, reboot afişi, "Updates" sekmesi (koyu tema, ana makinenin değişkenlerini devralır) |
| `demo.html` | sahte bir `ksu.exec` ile bağımsız sayfa - bir tarayıcıda açılır, cihaz yok |

## Ana makinenin `index.html`'ine entegrasyon

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### Ana makinenin tanımlaması gerekenler

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), motorun vendor edildiği yer
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), Tier-2 durumu (`journal.json`, `config`,
  `cancel`).
- **`modid`** = modül kimliği.

Widget, motor komutunu sözleşmenin env'ini (§1) zaten taşıyarak bir araya getirir:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume`
**arka plana** gider (`(… &)`) ve ilerleme, `cat $VDLU_DIR/journal.json`'un hafif bir yoklamasıyla (~1 sn) okunur.

### `exec`/`toast`/`confirm` (isteğe bağlı)

Atlanırsa, widget kendininkini kullanır:
- **`exec(cmd)`** stdout ile **çözülen** (rc 0) ve stderr ile **reddeden** (rc≠0) bir `Promise` döndürmelidir
  - tam olarak Demo `webroot/index.html`'inin `ex()`'inin imzası. Dahili geri çekilme, aynı sözleşmeyle
  `ksu.exec(cmd, '{}', cb)`'yi çağırır.
- **`toast(msg)`** = kısa bir geçici bildirim (geri çekilme kendi mini-toast'unu enjekte eder).
- **`confirm(title,msg,ok,danger,fn)`** = bir modal (bugün yalnızca ana makine tarafından kullanılıyor; widget
  hiçbir akışta onay gerektirmez).

Ana makinenin kendininkini geçmek, widget'ın WebUI'nin geri kalanıyla AYNI serileştirilmiş kuyruk ve görseller aracılığıyla
konuşmasını sağlar.

## Genel API (`window.VDLU`)

| İşlev | Yaptığı |
|---|---|
| `init(opts)` | yapılandırır (yukarıya bakın). `window.VDLU`'yu döndürür. |
| `onWebUIOpen()` | yüklemede çağırın: `reboot_pending` ise afişi gösterir; sonlandırıcı olmayan bir işlem varsa **Resume** sunar; `auto_on_webui_open=1` ile bir **SESSİZ otomatik güncelleme** çalıştırır (önce sessiz bir `check()`; yalnızca `update && fetch>0` ise `run`+kalıcı toast'u tetikler - güncel/ileride = panelde satır içi sonuç, sıfır toast). |
| `mountUpdatesPanel(el)` | "Updates" sekmesini `el`'in (string id ya da öğe) içine işler: **Check for update**, **Update now**, `auto_on_webui_open`/`auto_on_reboot` anahtarları, boot-retry alanları, **Network** seçimi (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) ve `source`/`channel`/`profile` alanları. |
| `check()` | `update.sh check`'i çalıştırır; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | arka planda `run` + **Cancel** içeren bir ilerleme toast'u tetikler. |
| `cancel()` | `$VDLU_DIR/cancel` oluşturur (motor güvenli noktada durur). |
| `resume()` | `update.sh resume` + toast (geçerli aşamadan devam ettirir). |
| `refreshBanner()` | kalıcı bekleyen-reboot afişini yeniden değerlendirir. |

Toast (köşe kaplaması, bloke etmeyen) ve afiş (üst, kalıcı), widget tarafından `document.body` içine enjekte edilir
- ana makinenin bunlar için HTML'ye ihtiyacı yoktur. "Updates" sekmesi, ana makinenin ayırdığı tek noktadır (boş
bir `<div>`).

### Toast'un yansıttığı durum akışı (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; her an `ERROR`. Toast
**bir çubuk + `phase done/total · current · bytes`** gösterir. Sonlandırıcılar:
- **`DONE`** → yeşil toast "v&lt;target&gt; uygulandı".
- **`PENDING_REBOOT`** (ya da `reboot_pending=true`) → yeşil toast + **kalıcı afiş** "⚠️ Yeni `.so`'yu (vX)
  etkinleştirmek için yeniden başlatın".
- **`ERROR`** → nedeni içeren kırmızı toast (`journal.error`/stderr). Asla başarıyı taklit etmez.
- **Cancelled** → "iptal edildi - N/M, devam ettirilebilir" + bir **Resume** düğmesi.

## Demoyu çalıştırma

`demo.html`'i bir tarayıcıda açın (`xdg-open webui/demo.html`). Sahte `ksu.exec`, `update.sh` ve
`journal.json`'un evrilmesini simüle eder; düğmeler **LIVE→DONE**, **reboot_pending**, **error mid-way**
ve **cancellable** senaryoları arasında geçiş yapar. Cihazdakiyle aynı `vdlu.js`/`vdlu.css`'tir.

## i18n (dil)

Widget dizeleri varsayılan olarak **İngilizce**'dir (public çok dilli modüller için nötr). Ana makine, `init`'te
bir eşleme geçirerek herhangi bir anahtarı geçersiz kılar:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Kısmi** bir birleştirme sorun değildir: eksik bir anahtar İngilizce varsayılana geri döner.
- Faz/durum anahtarları `ph_<phase>` / `st_<STATE>`'tir; geri kalan düzdür (`cancel`, `updateNow`, …).
- Tam anahtar eşlemesi = `vdlu.js`'teki `DEFAULT_I18N` nesnesidir (ayrıca `VDLU.i18n` olarak da açığa çıkarılır).
- İşlenmiş bir örnek olarak hazır bir çeviri sağlanır: `i18n/pt-BR.js`. Yeni diller = aynı kalıpta bir
  `i18n/<lang>.js` dosyası, ya da ana makine eşlemeyi kendi i18n sisteminden oluşturur.

## Tek kaynak (modüller arası parite)

Bu `vdlu.js`/`vdlu.css`, **kanonik kopyadır**. Widget'ı gömen her modül bu kopyayı
`webroot/`'una bayt bayt **yeniden-vendor eder** - kendininkini asla yerinde düzenlemez. Yeni bir widget özelliği
burada doğar ve yeniden-vendor ile aşağı akar; tersi sessiz sapma üretir (pratikte olmuştur: bir vendor edilmiş
kopya geride kaldı ve `net_policy`, `DEFERRED` toast'u ve `boot_retry` alanları eksikti).

Bekçi: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh), kaynak ağacındaki her kopyayı bulur ve
kanonik olandan sapanları işaretler (yalnızca `vdlu.js`/`vdlu.css`; keyring "kopyalamadan doğrula"dır).

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) ve motorun (`vdlu/update.sh`) kendi yeniden-vendor
> ritmi vardır; bu bekçi **yalnızca** WebUI widget'ını kapsar.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır; bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
