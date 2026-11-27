> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · Türkçe · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Güvenlik politikası ve güven modeli

VDLiveUpdate (VDLU), çalışan bir modüle **flashless root güncellemeleri** uygular: `/data/adb/modules/<mod>`
içine yazar ve boot'ta bir Zygisk `.so`'sunu swap eder. Getirilen bir manifestin her alanı (`path`,
`sha256`, `delete[]`, `mode`, ...) **düşmanca girdidir** - zehirlenmiş bir besleme ya da bir MITM onu
teslim eder. Bu sayfa güven modeli ve sorumlu açıklama politikasıdır. Tam seam sözleşmesi için
[`INTERFACES.md`](INTERFACES.md)'ye, engine/üretici iç yapıları için [`ENGINE.md`](ENGINE.md) ve
[`PRODUCER.md`](PRODUCER.md)'ye bakın, wiki sayfası **Security-and-Trust-Model**, repo dışındaki okurlar
için aynı modeli taşır.

## Desteklenen sürümler

Güvenlik düzeltmeleri en son `ENGINE_VERSION`'a iner, imzalı bir manifest, ihtiyaç duyduğu minimum
engine'i `engine_min` ile bildirir ve cihazdaki engine, uyguladığından fazlasını isteyen bir manifesti
reddeder. Daha eski vendor edilmiş engine'lerin bir düzeltmeyi almak için yerinde back-patch edilmesi
değil, **yeniden-vendor** edilmesi beklenir.

| ENGINE_VERSION | durum |
|---|---|
| 7 (güncel) | destekleniyor - beslemenin önündeki bir modülü asla geri almama (canlı kurulu `versionCode`, "from" sürümüne taban oluşturur), eski bir downgrade planının önyüklemede kendini onarması |
| 6 | yerini aldı - önyüklemede eski bir `target <= 0` journal'ının kendini onarması (kaldırılmış bir stub'ın bıraktığı baseline 0 artık hiçbir UI veya önyükleme eylemini tetiklemez) |
| 5 | yerini aldı - engine tarafı güven çıpası hariç tutma (`vdlu/` dizini bir besleme onu taşısa bile yok sayılır), dosya başına 128 MiB / manifest başına 2 MiB tavanları |
| 4 | yerini aldı - `key_id` allowlist'i, dot-segment/trailing-slash path reddi, boyut sınırları, check-time kilidi |
| <= 3 | desteklenmiyor - güncel engine'i yeniden-vendor edin |

Engine doğrulamasında veya apply mantığında herhangi bir değişiklik `ENGINE_VERSION`'ı artırır.

## Bir açığı bildirme

Özel olarak bildirin. Bir güvenlik hatası için herkese açık bir issue, PR ya da forum gönderisi
**AÇMAYIN**. Proje iletişimlerini kullanın (bkz. [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-posta: **vd.priv8@pm.me**

Lütfen engine sürümünü, kullanımdaki `profile`'ı ve sorunu yeniden üreten bir manifest ya da besleme
ekleyin. Düzeltmeler, bir `CHANGELOG.md` girdisiyle yeni bir `ENGINE_VERSION` olarak gelir, açıklama
zamanlamasını rapor başlığında koordine edin.

## Güven modeli

- **Ayrık ed25519 imzaları.** Üretici, kanonik manifesti PC'de imzalar (openssl), cihaz, gömülü
  `ed25519-mini` ile doğrular - **cihazda openssl yok**. İmzalanan mesaj, manifestin `sig` alanı olmadan
  (anahtarlar sıralı, kompakt, UTF-8) sha256 hex'idir, böylece imzalama ve doğrulama, cihazda bir JSON
  kütüphanesi olmadan iki çalışma zamanında aynı baytları türetir.
- **Keyring = RAW 32 baytlık pubkey'ler**, yalnızca flash. Cihaz keyring'i `<key_id>.pub`'u ham 32 baytlık
  anahtar olarak gönderir (asla PEM'i değil), `vdlu-pack`, keyring'i ve `verify/` ikililerini beslemeden
  **hariç tutar**, böylece bir manifest cihazdaki güven çıpasını asla ağ üzerinden yeniden yazamaz.
- **Engine tarafı güven çıpası hariç tutma (VDLU#2).** Yukarıdaki üretici tarafı hariç tutmadan bağımsız
  olarak, cihazdaki engine getirilen bir plandaki her `vdlu/` yolunu (`update.sh`, `vdlu-verify`,
  `verify/*`, `keyring/*`, config) **yok sayar** - bir besleme onları taşısa bile onları asla getirmez,
  uygulamaz veya silmez. Yayınlanan bir besleme, `vdlu/` dahil tüm modül ağacını gönderir, bu yüzden engine
  manifesti reddetmek yerine o yolları sessizce düşürür: modül yine de güncellenir ve güven çıpası yalnızca
  tam imzalı bir yeniden-flaş yoluyla değişir. Sızmış tek bir imzalama anahtarı artık doğrulayıcıyı veya
  imzalama anahtarını ağ üzerinden değiştirip root'u kalıcı kılamaz.
- **Modül-güncelleme `key_id` allowlist'i (fail-closed, pubkey seçiminden önce).** Bir keyring meşru olarak
  birden fazla anahtar taşıyabilir (örneğin release anahtarının yanında daha düşük güvenli bir
  fingerprint-feed anahtarı). `<key_id>.pub` seçilmeden önce, `verify_manifest`, `key_id`'si yapılandırılmış
  allowlist'te olmayan her manifesti **her iki** profiles'ta reddeder ve çözümlenmiş kümeyi
  `VDLU_KEYID_ALLOW` aracılığıyla `vdlu-verify`'a yansıtır. Bu, sızmış daha düşük güvenli bir anahtarın aksi
  takdirde tam bir flashless root güncellemesi imzalayabileceği bir bypass'ı kapatır. `key_id` ayarlanmamışken
  varsayılan-güvenli: **tek anahtarlı** bir keyring o tek anahtara otomatik sabitlenir, **çok anahtarlı** bir
  keyring, `key_id` sabitlenene kadar reddedilir (rotasyon için virgülle ayrılmış).
- **Fingerprint-feed güven kökü, kendi anahtarıyla ayrı, sabitlenmiş bir yoldur**, yukarıdaki
  modül-güncelleme yolu üzerinden asla erişilemez.
- **Baseline, yerel güvenilir bir tohumdur.** `baseline.json`, flaşlanan zip'in içinde gelir - kurulum güven
  sınırı - bu yüzden imzasız ve anahtarsızdır ve `vdlu-verify`'dan geçirilMEZ, yalnızca beslemeden **getirilen**
  bir manifest doğrulanır. Bu, imzalama anahtarını CI'dan uzak tutar.

## Fail-closed güvenceleri

- **`validate_plan`, herhangi bir fetch ya da apply'dan önce çalışır.** `do_diff` içinde, fail-closed olarak,
  herhangi bir `path` mutlaksa, bir `..` ya da `.` segmenti içeriyorsa, `/` ile bitiyorsa ya da bir kontrol
  karakteri taşıyorsa, herhangi bir `sha256`, `^[0-9a-f]{64}$` değilse, ya da herhangi bir `mode`/`class`/`enc`
  geçersizse manifestin **tamamını** reddeder. Hiçbir düşmanca alan bir shell'e ulaşmaz ve `cmd_check` hiçbir
  `system()` interpolasyonu taşımaz.
- **Path içermesi.** Her yazma ve silme, `contained()` aracılığıyla `MODULE_DIR` içine sınırlanır - apply,
  delete ve reboot `stage_file`'ın hepsi aynı korumadan geçer. Ağaçtaki sembolik bağlantılar üretici
  tarafından atlanır (asla dışarıdan içerik sızdırmaz).
- **İki profil, inversiyonla fail-closed.** `trusted` (özel, SSH-sahnelenmiş kaynak), best-effort doğrulamaya
  **tek** opt-in'dir, **diğer herhangi** bir değer - bir yazım hatası, bir trailing boşluk/CR ya da farklı bir
  büyük/küçük harf dahil - `hardened` olarak ele alınır, burada geçerli bir imza **zorunludur** ve bir
  başarısızlık iptal eder. Her blob'un `sha256`'sı her iki profilde de kontrol edilir.
- **Herhangi bir tool exec'inden önce imza + hash.** Getirilen statik `curl` root olarak çalışır, bu yüzden
  `install-tool`, tools-manifest imzasını (ed25519-mini, **herhangi** bir profilde zorunlu) ve curl'ün hash'ini
  kurulup exec edilmeden **ÖNCE** doğrular - exec'ten önce sig+hash, RCE'yi kapatır.
- **Devam ettirilebilir, pin-güvenli işlem.** Uçuştaki manifest `target.json`'da sabitlenir, bir çökme, ağ
  kaybı ya da yeniden başlatma, planı yeniden kararlaştırmadan günlükten devam eder. Downgrade engellenir
  (monoton `version`), imzalı `module` alanı `MODID`'ye eşit olmalıdır ve `delete[]` yalnızca `finalize_done`'da
  çalışır (bir `PENDING_REBOOT` hiçbir şeyi silmez). Tam bir yeniden-hash olmadan hiçbir şey asla "bitmiş"
  olmaz, önce bir `rollback/<v>/` yedeği olmadan hiçbir şey üzerine yazılmaz.

## Sertleştirme (derinlemesine savunma)

- **Boyut sınırları.** Manifest, tools-manifest ve curl'süz `wget`/`head -c` indirme yolu, okunmadan önce
  sınırlanır (anti-OOM / anti-flood). Bir blob, 3 denemeden sonra aşamasında başarısız olur. Tavanlar **dosya
  başına 128 MiB** (`MAX_FILE_BYTES`) ve **manifest için 2 MiB**'dir (`MAX_MANIFEST_BYTES`), `update.sh`'te
  uygulanır ve `vdlu-verify`'da yansıtılır.
- **Check-time kilidi.** `check`, çalışma dizinini yeniden kurmadan önce mkdir-kilidini alır, böylece eşzamanlı
  bir çalışma onunla yarışamaz.
- **Staging içermesi.** `stage_file`, canlı apply ilkelleriyle aynı `contained()` korumasına sahiptir, böylece
  sahnelenmiş bir reboot-hard yol da `MODULE_DIR`'den kaçamaz.
- **TLS, güven kökü değil, derinlemesine savunmadır.** Statik curl, Android güven deposuyla mbedTLS kullanır
  (`--capath`, `ca_path` geçersiz kılma), bütünlük güvencesi ed25519 imzasıdır, sertifika kontrolü ikinci bir
  katmandır.

## Ayrıca bakın

- [`INTERFACES.md`](INTERFACES.md) - değişmez seam sözleşmesi (§5 config, §6 imza, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - cihaz tarafı engine ve durum makinesi.
- [`PRODUCER.md`](PRODUCER.md) - paketleme, imzalama, kanonikleştirme ve anahtar rotasyonu.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
