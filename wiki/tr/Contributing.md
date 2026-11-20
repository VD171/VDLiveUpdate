# Katkıda Bulunma

Katkılar memnuniyetle karşılanır. VDLU, KernelSU / APatch / Magisk modüllerine gömülü,
flash gerektirmeyen, artımlı bir kendini güncelleme motorudur. Bu sayfa pratik geliştirici
iş akışıdır; parçaların nasıl birbirine uyduğu için önce [[Architecture]], [[Engine]] ve
[[Producer]]'ı okuyun.

## Hiçbir şey derlenmez

VDLU betiklerdir (POSIX sh, yayın tarafında biraz Python, WebUI için vanilla JS),
bu yüzden bir yapı adımı yoktur. Bir değişikliği, hattı (pipeline) baştan sona çalıştırarak
ve her parçayı statik olarak kontrol ederek doğrularsınız.

## Önce dikiş sözleşmesi

Bileşenler arasındaki arayüz sözleşmesi (motor, üretici ve WebUI tarafından paylaşılan
CLI imzaları, dosya adları ve JSON anahtarları) **yakınsama yasasıdır (law of
convergence)**. Onu değişmez olarak ele alın. Değişikliğiniz üretici-motor dikişine
dokunuyorsa (manifesto şeması, günlük şeması, yapılandırma anahtarları,
imza/kanonikleştirme kuralı), **önce arayüz sözleşmesini hizalayın**, ardından kodu her
iki tarafta eşleşecek şekilde değiştirin. Dikişin bir tarafında diğeri olmadan bir
değişiklik, benimseyenleri sessizce bozar. İmzalayıcı ve doğrulayıcının bayt bayt
anlaşması gereken kanonikleştirme kuralı için bkz. [[Producer]].

## PR'dan önce baştan sona test et

Üreticiyi ve motoru, bir benimseyenin yayınının yaptığı gibi, atılabilir bir ağaçta
birlikte çalıştırın:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Ardından her bileşeni statik olarak kontrol edin:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Ve `webui/demo.html`'yi bir tarayıcıda açın: kök yöneticisi köprüsünü (`ksu.exec`)
taklit eder, böylece Updates panelini, ilerleme bildirimini, iptali
ve yeniden başlatma afişini cihaz olmadan çalıştırabilirsiniz. Bkz. [[WebUI]].

## Ev kuralları

- **Cihazda POSIX sh.** `local` ötesinde bashism yok ve `jq` yok. toybox / busybox
  üzerinde çalışmak zorundadır.
- **Güvenlik pazarlık konusu değildir.** Her manifesto alanı düşmanca girdidir;
  `validate_plan()` hata durumunda kapalı kalır ve özel imzalama anahtarı asla
  CI'ya veya bir cihaza dokunmaz. Bir testi geçirmek için bir denetimi gevşetmeyin.
- **Başarısızlıkta titizlik.** İşlemi devam ettirilebilir tutun: hiçbir şey eşleşen bir
  yeniden hash olmadan "done" bildirmez, hiçbir şey bir yedek olmadan üzerine yazılmaz ve
  uygulamalar atomik kalır.
- **Her zaman yayın kalitesi.** Yorumları kısa tutun; gereksiz yorum yok.
- **PR başına bir mantıksal değişiklik.** Neyin değiştiğini ve nedenini söyleyin.

## Sorun bildirme

Ne yaptığınızı, ne beklediğinizi ve ne olduğunu açıklayan bir sorun (issue) açın.
Bir hata için, modül id'sini, kaynak profilini (`hardened` veya `trusted`),
çalıştırdığınız `update.sh` komutunu ve ilgili `journal.json`'u (aşamayı, durumu ve
hatayı kaydeder) ekleyin. Bir özellik için, dikiş etkisinin baştan net olması için hangi
bileşene dokunduğunu (engine, producer veya WebUI) söyleyin.
