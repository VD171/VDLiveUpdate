# SSS

En sık ortaya çıkan soruların kısa yanıtları. Her biri tam hikayenin olduğu
sayfaya bağlanır.

## "Flash gerektirmeyen" ne demek? İlk seferinde yine de flash yapar mıyım?

Evet, bir kez flash yaparsınız. Modül normal yolla kurulur (zip'i
kök yöneticinizde flash edin). "Flash gerektirmeyen", bundan sonraki her güncellemeyi
tanımlar: VDLU yalnızca değişen dosyaları alır ve bunları yerinde uygular, böylece
birkaç değişen satırı göndermek için asla tam bir zip'i yeniden flash etmezsiniz. Bkz.
[[Architecture]].

## Bir güncelleme yeniden başlatma gerektirir mi?

Genellikle hayır. Çoğu dosya (WebUI'niz, ikililer, kütüphaneler, yapılandırmalar, `module.prop`)
**live** sınıfıdır ve yeniden başlatma olmadan atomik olarak uygulanır. Yalnızca yeniden
başlatma sınıfı dosyalar (`zygisk/` altında bir `.so`, bir `/system/**` katmanı, bir
`*.rule` sepolicy dosyası) **aşamalanır** ve bir sonraki önyüklemede değiştirilir, çünkü
çalışan bir süreç canlı inode'u zaten eşlemiştir. Bu olduğunda WebUI kalıcı bir "reboot to
activate" afişi gösterir. Bkz. [[Reboot Handling]].

## Feed MITM'lenirse veya zehirlenirse güvenli mi?

Evet, bir `hardened` feed'de. Her manifesto alanı düşmanca girdi olarak ele alınır.
Manifesto, kanonik biçimi üzerinde geçerli bir ed25519 imzası taşımalıdır ve
`validate_plan()` **herhangi bir indirmeden önce** hata durumunda kapalı çalışır: tüm
manifestoyu bir mutlak veya `..` yolunda, 64 hex karakter olmayan bir `sha256`'da
veya geçersiz bir mod, sınıf veya kodlamada reddeder. Manifesto ayrıca modül
id'nize bağlıdır, böylece farklı bir modül için geçerli olarak imzalanmış bir feed onun
yerine sunulamaz. Her blob'un sha256'sı profilden bağımsız olarak indirmeden sonra
doğrulanır. Bkz. [[Security and Trust Model]].

## Cihazda neye ihtiyaç duyar (bağımlılıklar)?

Çok az. Saf POSIX sh (mksh / busybox / toybox) artı toybox'ın `sha256sum`,
`gzip`, `base64` ve `date`'i; gömülü `ed25519-mini` doğrulayıcısı; ve yalnızca bir
`https` kaynağı için, bir kez alınan ve Tier-2'de önbelleğe alınan statik bir `curl`.
Bir `file://` kaynağı hiç curl gerektirmez. **`jq`'ya bağımlılık yoktur**: motor
JSON'u `awk` ile yazılmış bir gron tarzı düzleştirici ile ayrıştırır. Bkz. [[Engine]].

## Cihazda openssl gerekli mi?

Hayır. `openssl` yalnızca PC/yayın tarafında kullanılır (`vdlu-keygen`, `vdlu-sign`).
Cihazda, imza doğrulaması, HAM 32 baytlık bir açık anahtar okuyan ince gömülü
`ed25519-mini` ikilisini kullanır. Bkz. [[Producer]] ve
[[Security and Trust Model]].

## İmzalama anahtarını nasıl döndürürüm?

`vdlu-keygen` ile yeni bir anahtar çifti üretin, yeni HAM 32 baytlık açık anahtarı
öncekinin yanına cihaz keyring'ine ekleyin ve yeni `key_id` ile imzalamaya başlayın.
Cihaz, manifestonun `key_id`'siyle `<keyring>/<key_id>.pub`'u seçer, bu yüzden motor
değişikliği gerekmez. Hem mevcut hem de önceki açık anahtarı göndermek, döndürülmüş bir
anahtarın eski kurulumları asla tuğlalaştırmaması anlamına gelir. Bir döndürme keyring'de birden fazla anahtar bıraktığı için, bir modül güncellemesini hangi anahtarın imzalayabileceğini de sabitlemeniz gerekir: `key_id` yapılandırmasını ayarlayın (döndürme penceresi sırasında virgülle ayrılmış). Tek anahtarlı bir keyring otomatik olarak sabitler ve hiçbir yapılandırmaya ihtiyaç duymaz. Bkz. [[Security and Trust Model]].

## hardened vs trusted - hangisini kullanırım?

Herhangi bir herkese açık feed için `hardened` kullanın (`https` üzerinden sunulan, ör. GitHub Pages).
İmzayı zorunlu kılar ve alt sürümleri engeller. `trusted`'ı yalnızca zaten kontrol
ettiğiniz özel bir `file://` veya SSH ile aşamalanmış kaynak için kullanın, orada imza
elden geldiğincedir (her blob hash'i yine de kontrol edilir). Şüphe duyduğunuzda `hardened` kullanın:
hata durumunda kapalı varsayılandır ve `trusted` olmayan herhangi bir değer
`hardened` olarak ele alınır. Bkz. [[Security and Trust Model]].

## Bir blob kurcalanırsa veya manifesto hatalı biçimlendirilirse ne olur?

Güncelleme iptal edilir ve hiçbir şey uygulanmaz. Hatalı biçimlendirilmiş bir manifesto,
herhangi bir fetch'ten önce `validate_plan()` tarafından tamamen reddedilir. sha256'sı
manifesto ile eşleşmeyen bir blob reddedilir; aynı blob üzerinde üç başarısızlık, hiçbir
şey uygulanmadan fetch aşamasını iptal eder. Herhangi bir sert başarısızlıkta günlük
`ERROR` kaydeder ve modül sağlam bırakılır. Bkz. [[Engine]].

## Bir güncelleme dosyalarımı silebilir veya cihazı tuğlalaştırabilir mi?

Risk tasarım gereği sınırlandırılmıştır. Üzerine yazılan ve silinen dosyalar önce
`rollback/<version>/`'ye yedeklenir ve `apply`, başarılı bir yedek olmadan üzerine yazmak
yerine iptal eder. Silmeler yalnızca bir işlem `DONE`'a ulaştığında çalışır, asla
bir yeniden başlatma hâlâ beklerken değil. Başarısız bir uygulama, zaten yazdığı canlı
dosyaları geri alır. Yollar, kullanımdan önce modül dizini içinde içerme için doğrulanır,
böylece bir manifesto ağacın dışına yazamaz veya silemez. Bkz. [[Engine]] ve
[[Security and Trust Model]].

## KernelSU VE Magisk VE APatch üzerinde çalışır mı?

Evet. VDLU, modüle gömülü saf POSIX sh artı bir WebUI'dir, bu yüzden
KernelSU, APatch ve Magisk üzerinde aynı şekilde çalışır. Motoru çalıştırmak ve
ilerlemeyi yoklamak için kök yöneticisinin WebUI köprüsünü (`ksu.exec`) kullanır.
Bkz. [[Architecture]] ve [[WebUI]].

## Cihaz üstü ayak izi ne kadar büyük?

Küçük. Motor betiklerdir; tek ikililer, ABI başına `ed25519-mini`
doğrulayıcısı (küçücük) ve bir `https` kaynağı için, bir kez alınan ve önbelleğe alınan
statik bir `curl` (~1MB). Zaten kendi `curl`'ünü paketleyen bir modül onu yeniden kullanır
ve hiç indirme eklemez. Tier-2 blob önbelleği, doğrulanmış içeriği artı son 3 geri alma
sürümünü tutar. Bkz. [[Engine]] ve [[Architecture]].
