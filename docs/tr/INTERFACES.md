> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · Türkçe · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Arayüz sözleşmesi (bileşenler arasındaki ek yeri)

**Yakınsama yasası:** her bileşen bu dosyaya uyar. 4 ajandan gelen parçaların birbirine **uyması** gerekir -
aşağıdaki CLI imzaları, dosya adları ve JSON anahtarları **değişmezdir** (bir değişiklik önce burada hizalama anlamına
gelir).

Repolardan devralınan ilkeler: cihazda **saf POSIX sh** (bashism yok, toybox/busybox + toybox'ın
`sha256sum`/`gzip`/`base64` + getirilen `curl` + gömülü `ed25519-mini` ile çalışır - ince, bin paketi yok),
**sıfır gereksiz yorum**, **her zaman release**, **başarısızlıkta titizlik** (devam ettirilebilir işlem, hiçbir şey
sahte şekilde "tamamlandı" değil, hiçbir şey kaybolmaz), **hiçbir şey gevşetilmez**.

---

## 1. Durum düzeni (Tier-2, modül dizininin dışında)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
Günlükteki `cancelled:true` = motor bir iptalde durdu (terminal olmayan, devam ettirilebilir bir durum, `error`
null kalır).

Modülde vendor edilen motor: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Motor env aracılığıyla şunları alır: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. Motor CLI (ENGINE bileşeni)

`sh update.sh <cmd>` - rc 0 = tamam, !=0 = hata (stderr'de sebep bulunur):

| cmd | yapar |
|---|---|
| `check` | DIFF: manifesti indirir, karşılaştırır; 1 satırlık bir JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` yazdırır; hiçbir şeyi değiştirmez. Cihaz beslemenin İLERİSİNDE (indirgeme engellendi, hardened) = İYİ HUYLU bir durum: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (asla "check failed" değil). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | tam döngü: DIFF→FETCH→APPLY→COMMIT; `cancel`'ı dikkate alır; ilerlemeyi `journal.json`'a yazar; LIVE uygular, REBOOT-hard'ı hazırlar |
| `resume` | `journal.json` işlemini mevcut aşamadan devam ettirir (idempotent) |
| `boot` | pre-zygote modu: `resume` + `staged/*.vdlu-new`'in TAKASINI yapar (`.so`'yu uygular), `PENDING_REBOOT`→`DONE` kapatır |
| `status` | `journal.json` yazdırır (veya `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` oluşturur (devam eden bir `run` bir sonraki güvenli noktada durur) |

Blob/manifest kaynağı: yapılandırmadan `source`. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` `https://` ile başlar (statik curl getirilir, TLS) veya `file://` (yerel staging).

## 3. manifest.json (PRODUCER tarafından üretilir, ENGINE tarafından tüketilir)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = TAM hedef ağacı. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Yola göre varsayılan, asla `reboot`→`live` indirmez.
- `enc`: `gz` (gzip `-9 -n`, deterministik, cihazda toybox gunzip) yalnızca iyi sıkıştırdığında VE
  boyut önemli olduğunda, `sha256` HER ZAMAN orijinal içeriğindir.
- `sig`: `sig` alanı OLMADAN kanonik manifestin imzası (verify'nin §4'ü).
- **Güven çıpası hariç tutma (engine tarafı, VDLU#2):** engine, `vdlu/` altındaki her `files[]`/`delete[]`
  yolunu (kendi `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config'i) plandan DÜŞÜRÜR - asla getirilmez,
  uygulanmaz veya silinmez - imzalı bir besleme onları taşısa bile. Cihazdaki güven çıpası yalnızca tam imzalı
  bir yeniden-flaş ile değişir, ağ üzerinden değil, `vdlu-pack` ayrıca `vdlu/`'yu üretici tarafında hariç
  tutar, bu yüzden bu, sızmış bir imzalama anahtarına karşı ikinci, engine tarafı bir korumadır.

## 4. journal.json (ENGINE yazar, WEBUI okur - ilerleme sözleşmesi)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Durum makinesi (sabit sıra): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` yalnızca HER ŞEYİN yeniden hash'i eşleştiğinde. Hazırlanmış bir REBOOT-hard ⇒ `PENDING_REBOOT` (`DONE`
değil). `fetch` aşamasından çıkışlar: `ERROR` (sert başarısızlık) veya `DEFERRED` (net_policy indirmeyi engelledi -
iyi huylu/devam ettirilebilir, bir hata değil).

## 5. config (key=value, satır başına bir tane, WEBUI'de düzenlenebilir)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot yeniden deneme (çevrimdışı) - SABIRLI, pil dostu:** yalnızca `boot`'ta (asla check/auto-open'da değil).
Manifest getirme AĞ nedeniyle başarısız olursa (`fetch_offline` getiricinin çıkışına göre sınıflandırır) başarılı
olana VEYA `boot_retry_minutes`'luk UYANIK-zaman tükenene kadar bekler ve yeniden dener. **Hiçbir şey tutmayan ve
tüketmeyen** bir tasarım:
- **Sıfır wakelock:** denemeler arasında `sleep`'tir, derin uykuda donar → cihaz normal şekilde uyur
  (~sıfır pil), yeniden deneme duraklar ve cihaz zaten uyandığında devam eder.
- **Sıfır tutulan kilit:** denemeler ARASINDA `acquire_lock_try`+release (beklerken kilidi tutmaz) →
  `run`/manuel check asla engellemez, bu arada manuel bir run bir TARGET hazırlarsa, boot erteler.
- **Radyoyu boş yere uyandırmaz:** her denemeyi bir `net_allowed` sondası (via `net_type`/`ip route get`, Android'in
  politika-yönlendirmesine saygı duyan bir çekirdek rota araması, paket yok) geçitler - yalnızca ağ ortaya çıktığında
  bir getirme harcar.
- Deterministik bir başarısızlığı (manifest/sig/indirgeme) ASLA yeniden denemez. Getirmede `--connect-timeout 15`
  (bir captive portal'da takılmaz). `service.sh` onu arka plana alır (boot asla takılmaz).
- ⛔ **SERT: `boot_retry_minutes>0` açmak SABIRLI motoru gerektirir** (`net_allowed`+`acquire_lock_try` olan,
  kanonik `da7115f4`+). ÖNCEKİ boot-yeniden-deneme (tüm pencere boyunca kilidi tutar + çevrimdışı kör curl'u yeniden
  dener) **pili TÜKETİR/radyoyu uyandırır** - yeniden denemeyi eski bir motorda açmak bir ayak kurşunudur.
  Etkinleştirirken mevcut motoru vendor et.

**`net_policy` (any|wifi|mobile):** **İNDİRMEYİ** ağ türüne göre geçitler. `net_type()` `ip route get`'in çıkışını
sınıflandırır (hücresel arayüz `rmnet/ccmni/v4-*/clat` = mobile, diğer her şey = wifi, çekirdek araması, paket yok).
`net_allowed()` `net_policy`'ye karşı karşılaştırır ve `do_fetch`'i (bloblar) + sabırlı boot-yeniden-deneme sondasını
geçitler. **Manifest kontrolü ücretsiz kalır** (küçük → arayüz herhangi bir ağda bir güncelleme bildirir), yalnızca
indirme izin verilen ağı bekler. İzin verilmeyen bir ağda bir indirme = günlükteki **`DEFERRED`** durumu (ERROR
DEĞİL, nazik mavi bir INFO toast "waiting for X network", plan/target kalıcıdır, doğru ağda bir sonraki check/boot'ta
devam eder). `net_policy` `allow_metered`'ı **geçersiz kılar** (ki asla tüketilmedi). Motor `97baf887`+ (`file://`
asla geçitlenmez).

## 6. İmza (PRODUCER PC'de openssl aracılığıyla imzalar, ENGINE cihazda ed25519-mini aracılığıyla doğrular)

- Kanonikleştirme: `sig` OLMADAN manifest, anahtarlar sıralı, kompakt JSON (gereksiz boşluk yok), UTF-8.
  İmzalanan/doğrulanan = o kanonik formun `sha256` hex'i (araçlar arası determinizm sağlar).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → `key_id` + `sig`'i (kanonik sha256'nın ed25519 imzasının base64'ü) manifeste yerinde enjekte eder.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → `sig` keyring'deki `<key_id>.pub` pubkey ile eşleşiyorsa rc 0
  (SLIM: pubkey **HAM 32 bayt**). Dahili olarak, openssl yok: toybox `sha256sum`/`base64 -d` + gömülü
  `ed25519-mini` ikilisi (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=geçerli/1=geçersiz/2=kullanım).
  rc!=0 = reddet. **`profile=hardened` ⇒ verify zorunlu, başarısızlık = iptal.**
  `profile=trusted` ⇒ verify en-iyi-çaba (kaynak SSH aracılığıyla zaten güvenilir), ancak her blob'un hash'i HER ZAMAN kontrol edilir.
- **module-update anahtar allowlist'i (fail-closed, pubkey seçiminden önce):** manifestin `key_id`'si, `<key_id>.pub` seçilmeden önce kabul edilmiş bir MODULE-UPDATE anahtarı olmalıdır - config'in `key_id`'si (§5) bu allowlist'tir. Bir keyring, daha düşük güvenli bir anahtarı DA taşıyabilir (ör. bir fingerprint-feed anahtarı, otomatik, farklı hesap), allowlist olmadan, o anahtarla imzalanmış bir manifest sızarsa doğrulanır ve tam bir flashless root güncellemesi uygular. `verify_manifest` bunu HER İKİ profiles'ta da uygular ve çözümlenen kümeyi `VDLU_KEYID_ALLOW` env'i aracılığıyla `vdlu-verify`'a geçirir (böylece bağımsız doğrulayıcı da uyumludur). Ayarlanmamış hali varsayılan-güvenlidir (tek anahtarlı keyring: yalnızca o anahtar, çok anahtarlı keyring: `key_id` sabitlenene kadar reddedilir). Fingerprint-feed güven kökü, kendi sabitlenmiş anahtarıyla AYRI bir yoldur ve etkilenmez.
- `producer/vdlu-keygen <id> <out>` → `<id>.pem` (priv) + `<id>.pub` (PEM, PC'deki araçlar için) +
  `<id>.pub.raw` (**HAM 32B** = cihazdaki ince keyring'in `<id>.pub`'u) üretir. openssl `genpkey -algorithm ed25519`.

## 7. Blob - doğrulama (ENGINE)

`<source>/blobs/<sha>` indirir (veya `enc=gz` ise `.gz`), `.part` yazar, `gz` ise açar (`gunzip`),
`sha256sum` == manifestin `sha256`'sı mı diye kontrol eder, eşleşme → `$VDLU_DIR/blobs/<sha>`'ya atomik `mv`. Aynı
blob'da 3 başarısızlık = aşamayı iptal eder (hiçbir şey uygulanmaz). `$VDLU_DIR/blobs/<sha>`'da ok bir hash ile zaten
bulunan bir blob = indirmeyi atlar.

## 8. Sınıfa göre APPLY (ENGINE)

- `live`/`soft`: `rollback/<v>/<path>` yedekle → blob'tan `$MODULE_DIR/<path>.vdlu-tmp` yaz → `chmod mode` →
  hedefin üzerine atomik `rename`. Hedef hash'inde zaten = atla. (Zygisk varyantında yazma monte edilmiş dizine gider
  = dosya başına birleştirme, asla dizinin `rm -rf`'i değil.)
- `reboot`: `$VDLU_DIR/staged/<path>.vdlu-new`'e maddeleştirir (canlı olana DOKUNMAZ). Takas `boot`'tadır.
- `delete[]`: yedekle → kaldır.

## 9. WEBUI ↔ ENGINE (WEBUI bileşeni)

- Ateşler: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (arka plan).
- İlerleme: her ~1s'de hafif bir yoklama `ksu.exec("cat $VDLU_DIR/journal.json")`, `{phase,state,total,done,current,bytes}` oluşturur.
- Canlılık: günlük 8 tik boyunca yok ⇒ "no response". Günlük 20 tik boyunca DONMUŞ (aynı değerler) ⇒ `lock.d`'yi kontrol eder: canlı = devam eder (1 blob'un yavaş getirilmesi), ölü = hata + Resume. Bu olmadan, getirmenin ortasında ölen bir run toast'ı "updating"de dondururdu.
- İptal: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: bir "Updates" sekmesinde `$VDLU_DIR/config`'i (key=value) okur/yazar.
- Toast: çubuk + `phase done/total · current`, `reboot_pending` ile bitişte ⇒ kalıcı bir afiş "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): önce SESSİZ bir `check()` yapar (ilerleme toast'ı yok), yalnızca `update && fetch>0` ise `run`+kalıcı toast'ı ateşler. Güncel/ileri/yeni-bir-şey-yok = panelde satır içi bir sonuç, sıfır artık toast. Manuel düğme gibi müdahaleci değil (toast yalnızca gerçek bir indirme olduğunda görünür). curl bootstrap tek seferliktir.

## 10. Demoya entegrasyon (INTEGRATION bileşeni) - PARÇACIKLAR, canlı dosyaları düzenlemeyin

`integration/demo/` içinde, parçacıklar + her birinin nereye gittiğini söyleyen bir `INTEGRATION.md` üretir (uygulamadan):
- `post-fs-data`/`service.sh`'teki `auto_on_reboot` kancası (pre-zygote → `update.sh boot`) ve `auto_on_webui_open`.
- `config` varsayılanları + gömülü keyring + vendor etme (`modules/<mod>/vdlu/`).
- KISMİ varyant (monte edilmiş dizine birleştir).

## 11. Getirilen araç zinciri + baseline (SLIM, Approach B)

**Modüldeki düzen (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **HAYIR** `bin/` (openssl/curl/zstd). `customize.sh` `verify/`'yi cihazın
ABI'sine kadar budayabilir (`vdlu-verify` mini'yi `<dir>/ed25519-mini` VEYA `<dir>/verify/<abi>/ed25519-mini`'de bulur).

**ed25519-mini** (gömülü ikili, yalnızca doğrulama): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=geçerli,
1=geçersiz, 2=kullanım/IO. msg = tam imzalanan baytlar (yeniden hash'LEMEZ). TweetNaCl PD, ABI başına statik, PROVENANCE.

**tools-feed** (yalnızca public/https profili): `<tools_source>`'ta sunulur (varsayılan türetilir: `source`'un son
segmentini `vdlu-tools` ile değiştirir, ör. `https://<user>.github.io/<repo>/vdlu-tools`). İçerir:
- `tools-manifest.json` - `<abi>/curl` ağacı üzerinde İMZALI bir `vdlu-pack` manifesti, her curl'un `sha256`'sını
  sabitler (aynı `release-2026` anahtarı).
- `<abi>/curl` - HAM **statik** curl (kendi kendine yeten, ~1MB, curl 8.11.1 + mbedTLS). 🪤 mbedTLS bir CA paketi
  TAŞIMAZ: `fetch_url` `--capath` geçirir (Android güven deposunun otomatik algılanması: `/system/etc/security/cacerts`
  → APEX conscrypt, `ca_path` geçersiz kılar). capath yok = hata 60. Bütünlük ed25519'dur, sertifika kontrolü derinlemesine savunmadır.

**install-tool** (ENGINE): `update.sh install-tool <abi>` `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`'i okur
(WEBUI bunu `fetch()` aracılığıyla indirir ve oraya yazar), **tools-manifest imzasını doğrular (ed25519-mini,
herhangi bir profilde ZORUNLU)** + curl'un hash'i == manifest, ve yalnızca o zaman onu `$VDLU_DIR/tools/<abi>/curl`'a (0755) kurar.
curl root olarak çalışır → exec'ten önce sig+hash RCE'yi kapatır. Tier-2'de kalıcıdır: asla yeniden indirilmez (kaldırma hariç).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): check/run/resume'den önce çalışır. `file://` = işlem yok, curl ZATEN
mevcut (Tier-2, VEYA **kendi kendine paketlenmiş** bir modülden `module/bin/<abi>/curl`, VEYA sistem) = işlem yok
(VDLU mevcut curl'u yeniden kullanır), yalnızca `https` **hiç curl olmadan** curl + tools-manifest'i webview aracılığıyla indirir, bunları
`.work`'e yazar (`ksu.exec` aracılığıyla parçalı base64), `install-tool`'u çağırır. Güven = cihaz üzerindeki kontrol, indirme değil.

> 🪤 **Slim (fetch-bootstrap) ≠ zorunlu.** `bin/`'i KENDİ ÖZELLİKLERİ için var olan bir modül (ör. restic/rclone/age/tar/curl...
> paketler) ~2MB'a **inmez** ve curl indirmez - VDLU ince motoru benimser (gz, mini, baseline, düzeltmeler) ve gömülü
> araç zincirini **yeniden kullanır**. Yalnızca kendi araç zinciri olmayan modüller ~2MB kazanır.

**baseline.json** (from:0 düzeltmesi): release gönderilen sürümün İMZALI `manifest.json`'ını `vdlu/baseline.json`'a
kopyalar, yeni bir kurulumda motor `current.json`'ı ondan tohumlar (`init_paths`, yalnızca yoksa) → cihaz "güncel"
doğar, kendisinin otomatik güncellemesi olmadan ve yeniden getirme olmadan.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
