> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · Türkçe · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU motoru (`update.sh`)

KSU/Magisk modülleri için flashless, artımlı güncelleme istemcisi.
`DIFF -> FETCH -> APPLY -> COMMIT` döngüsünü devam ettirilebilir bir işlem olarak uygular. `INTERFACES.md`'ye (yakınsama
yasası) uyar.

Saf POSIX sh (mksh/busybox/toybox). **SLIM:** yalnızca toybox'a (`sha256sum`/`gzip`/`base64`/`date`) +
gömülü `ed25519-mini`'ye (ed25519 verify; **cihazda openssl yok**) + ilk https güncellemesinde **getirilen** statik bir
`curl`'e bağımlıdır (WebUI `fetch()`'i yapar, onu Tier-2'de kalıcı kılar ve `install-tool` kullanmadan ÖNCE
imzasını+hash'ini doğrular). `file://` curl gerektirmez. `jq`'ya sıfır bağımlılık.

## Çağrı

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = tamam; `rc != 0` = hata (neden stderr'de). `vdlu-verify` başka bir bileşen tarafından teslim edilir
(imza `INTERFACES.md §6`'da); motor onu yalnızca çağırır.

| cmd | yaptığı |
|---|---|
| `check` | salt okunur DIFF; `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` yazdırır; hiçbir şeyi değiştirmez |
| `run` | tam LIVE döngüsü + REBOOT-hard'ı sahneler; `cancel`'ı dikkate alır; ilerleme `journal.json`'da |
| `resume` | bekleyen işlemi (`target.json`) geçerli aşamadan devam ettirir; idempotent; `.so`'yu swap **etmez** |
| `boot` | pre-zygote modu: resume **+** `staged/*.vdlu-new`'i swap eder → `PENDING_REBOOT`→`DONE`'ı kapatır. Bekleyen işlem yoksa, taze bir döngü çalıştırır ve tek bir boot'ta her şeyi (`.so` dahil) uygular |
| `status` | `journal.json`'u yazdırır (ya da `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` oluşturur; devam eden bir `run` bir sonraki güvenli noktada durur |

## Durum makinesi (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` yalnızca HER ŞEYİN yeniden hash'i eşleştiğinde. Herhangi bir REBOOT-hard sahnelenmişse ⇒ `PENDING_REBOOT` (asla
sahte bir `DONE` değil). Herhangi bir başarısızlıkta `ERROR`, modülü bozmadan (uygulanan LIVE dosyalar
`rollback/<v>/`'den geri alınır; hiçbir şey "yalan söyleyerek yarı uygulanmış" değildir). `fetch` aşamasının zararsız çıkışı: **`DEFERRED`** -
indirme `net_policy` tarafından ertelendi (ağa izin verilmedi); plan/target kalıcıdır ve sonraki
check/boot'ta devam eder (WebUI mavi bir bilgi toast'u "X ağı bekleniyor" gösterir, bir hata değil).

## Titizlik güvenceleri

- **FETCH:** `net_policy` tarafından geçitlenir (any/wifi/mobile; yalnızca http/https, `file://` asla) - izin verilmeyen bir ağ ⇒
  `DEFERRED` (devam ettirilebilir), veri harcamadan. Yalnızca eksik olanı `<sha>.part` içine indirir (curl ile
  `--connect-timeout` + `--speed-time`, asla takılmaz), `gz`'yi açar (toybox `gunzip`), `sha256sum` ==
  manifest'i kontrol eder, `blobs/<sha>`'ya atomik `mv`. Önbellekte+tamam olan bir blob atlanır. Blob'u değişmemiş bir
  yerel dosyadan tohumlayabilir (dedup/çevrimdışı). **Aynı blob'ta 3 başarısızlık = aşama hiçbir şey uygulamadan iptal olur.**
  Yalnızca planın TÜM blob'ları mevcut+doğrulanmış olduğunda `FETCHED` olur.
- **APPLY** (yalnızca `FETCHED`'den): `live`/`soft` → `rollback/<v>/`'ye yedek → `.vdlu-tmp` → `chmod` → doğrula →
  atomik `rename`. `reboot` → `staged/<path>.vdlu-new` içine materyalize eder (canlı inode'a DOKUNMAZ).
  `delete[]` → yedekle → kaldır. İdempotent (zaten hedef hash'inde olan bir dosya atlanır).
- **COMMIT:** her `live`/`soft`'un yeniden hash'i; ancak o zaman `current.json`'u yazar. Sahnelenmiş dosyalar varsa ⇒
  `PENDING_REBOOT`. `boot`, `mv -f staged/....vdlu-new $MODULE_DIR/<path>` yapar (pre-zygote) + yeniden doğrular +
  `DONE`.
- **cancel:** dosyalar arasında kontrol edilir (güvenli nokta); devam eden `.vdlu-tmp`/`.part`'ı kaldırır, `cancel`'ı
  siler, günlüğü devam ettirilebilir bırakır (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serileştirir (flock toybox'ta çalışmaz; PID ile eskimiş-kurtarma). SABIRLI
  boot-retry beklerken ne kilidi tutar (`acquire_lock_try`+denemeler arası release) ne de bir
  wakelock - pil dostu. Yol ortasında bir çökme/ağ/yeniden başlatma → `resume`/`boot` sürdürür.
- **profile=hardened** ⇒ kullanımdan ÖNCE manifest üzerinde `vdlu-verify` zorunlu; başarısızlık = iptal; sürüm düşürme engellendi
  (monoton sürüm). **trusted** ⇒ verify en iyi çabadır, ama her blob'un hash'i HER ZAMAN kontrol edilir.
- **module-update anahtar allowlist'i (her iki profiles):** `verify_manifest`, `key_id`'si yapılandırılmış `key_id` allowlist'inde (bkz. INTERFACES §5/§6) olmayan her manifesti, pubkey seçilmeden ÖNCE fail-closed reddeder, böylece yalnızca keyring'de duran daha düşük güvenli bir anahtar (ör. bir fingerprint-feed anahtarı) asla bir flashless root güncellemesi imzalayamaz. Ayarlanmamışken varsayılan-güvenli: tek anahtarlı keyring = yalnızca o tek anahtar; çok anahtarlı keyring = `key_id` sabitlenene kadar reddedilir.
- Zarifçe bozulur: eksik ikili / ağ kapalı / disk dolu → stderr'de açık bir hata + günlükte `state:ERROR`,
  modülü bozmadan.

## jq olmadan JSON ayrıştırma

`awk`'ta gron tarzı bir düzleştirici (saf POSIX: `substr`/`index`/`gsub`/`split`/`printf` + parametre olarak geçirilen
yerel değişkenler) manifesti karakter karakter tokenleştirir ve her skaler yaprak için bir `path<TAB>value` satırı yayar
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Kompakt YA DA güzel yazdırılmış
JSON'a karşı sağlam. `sh` onu `grep`/`cut` ile tüketir; dosya başına plan 2. bir `awk`'ta TSV'ye
(`class st mode enc sha size path`) yeniden birleştirilir, ki o da `$VDLU_DIR/plan.tsv` olur.

## Durum dosyaları (`$VDLU_DIR`'de, Tier-2)

| dosya | rol |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…; INTERFACES §5'e bakın) |
| `current.json` | AKTİF sürümün manifesti (diff tabanı); yok = hiç güncellenmedi |
| `target.json` | devam eden işlemin sabitlenmiş manifesti (varlığı = aktif işlem); `DONE`'da `current.json` olur |
| `plan.tsv` / `plan.del` | plan + dosya başına ilerleme (st) / silinecek yollar |
| `journal.json` | WebUI için ilerleme (her geçişte yeniden üretilir) |
| `blobs/<sha256>` | doğrulanmış orijinal içeriğin önbelleği |
| `rollback/<version>/<path>` | üzerine yazılan dosyaların yedeği (geri al; son 3'ü tutar) |
| `staged/<path>.vdlu-new` | boot'ta swap bekleyen REBOOT-hard |
| `lock.d/` | mkdir-lock (flock toybox'ta çalışmaz; PID ile eskimiş-kurtarma) |
| `tools/<abi>/curl` | getirilen statik curl (slim bootstrap); güncellemeler boyunca kalıcıdır |
| `cancel` | iptal isteği |

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır; bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
