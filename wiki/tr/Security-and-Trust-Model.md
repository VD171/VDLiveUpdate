# Güvenlik ve Güven Modeli

VDLU bir modülü yerinde, ağ üzerinden, kök (root) olarak günceller. Bu, bir feed'den gelen bir dosyaya yöneltilmiş çok fazla güçtür, bu yüzden tüm motor tek bir varsayım üzerine kuruludur:

> **Manifestodaki her alan düşmanca girdidir.**

Bir feed kaynakta zehirlenebilir veya bir MITM tarafından aktarım sırasında değiştirilip bozulabilir. Bu olduğunda manifesto yine de bir manifesto gibi görünerek gelir: dosya yolları, `sha256` dizeleri, bir `delete[]` listesi, modlar, sınıflar ve bir kodlama bayrağı taşır. VDLU bunların hiçbirine güvenilir muamelesi yapmaz. Tek bir bayt indirmeden önce tüm planı doğrular ve bir manifesto değerinin asla bir kabuğa ulaşmasına izin vermez.

Bu sayfa tam güven hikayesidir. Doğruladığı manifesto şeması için bkz. [[Feed Format]] ve bu denetimlerin DIFF -> FETCH -> APPLY -> COMMIT işleminde nerede oturduğu için bkz. [[Engine]].

---

## Temel fikir: herhangi bir şey olmadan önce hata durumunda kapalı

`validate_plan()`, herhangi bir fetch'ten **önce** ve herhangi bir apply'dan **önce** `check`/fark aşaması içinde çalışır. Planlanan dosya ağacındaki her girdiyi ve `delete[]`'teki her girdiyi dolaşır ve tek bir girdi bile hatalı biçimlendirilmişse **tüm manifestoyu reddeder** ve işlem asla başlamaz. Kısmi kabul yoktur, "kötü olanı atla ve gerisini uygula" yoktur. Kötü bir alan tüm partiyi zehirler, bilerek.

Bir manifesto yalnızca **her** girdi için şunların **hepsi** geçerliyse kabul edilir:

| Alan | Kural | Neden |
|---|---|---|
| `path` | mutlak değil, `..` bileşeni yok, `.` bileşeni yok, başta `./` yok, gömülü `/./` yok, sonda eğik çizgi yok, kontrol karakteri yok (sekme / yeni satır) | bir yol `MODULE_DIR` içinde kalmalıdır; mutlak veya `..` bir yol herhangi-bir-yere-yazmadır |
| `sha256` | tam olarak `^[0-9a-f]{64}$` ile eşleşir | hex olmayan bir sha aksi halde bir kabuk yoluna enterpole edilir; içerik adresidir, bu yüzden saf bir hex özeti olmalı ve başka hiçbir şey olmamalıdır |
| `mode` | yalnızca sekizlik (octal) (`[0-7]`) | bir mod dizesi bir `chmod` argümanı olur |
| `size` | yalnızca rakamlar ve motorun boyut tavanına `<=` | indirmeyi ve açmayı sınırlar |
| `class` | tam olarak `live`, `soft` veya `reboot` | sınıf, bir dosyanın canlı mı uygulandığına yoksa yeniden başlatma için aşamalandığına mı karar verir |
| `enc` | tam olarak `raw` veya `gz` | kodlama, blob'un gunzip'lenip lenmeyeceğine karar verir |
| `delete[]` girdileri | yukarıdakiyle aynı yol kuralları | bir `delete[]` girdisi bir kaldırmayı yönlendirir; denetlenmemiş bir `..`, ağacın dışında bir `rm` olur |

Bu önce çalıştığı için, zehirli bir manifesto asla modülün dışına yazamaz, asla modülün dışında silemez ve asla bir komut satırına hex olmayan bir belirteç enjekte edemez.

### Manifesto değerleri asla bir kabuğa dokunmaz

Kuralın ikinci yarısı: bir değer doğrulamayı geçtikten sonra bile, asla `sh`'ye enterpole edilmez ve asla `awk system()`'e beslenmez. Check komutu kasıtlı olarak hiçbir `system()` çağrısı içermeyecek şekilde yeniden yazıldı. İçerik adresleme işin geri kalanını yapar: bir blob `sha256`'sı ile alınır, aynı `sha256` ile adlandırılan bir önbellek yoluna yazılır ve indirilen baytlar herhangi bir şey uygulanmadan önce yeniden hashlenir ve karşılaştırılır. Temiz bir 64-hex özeti olmayan bir değer o kadar ileri gitmez, çünkü `validate_plan()` onu zaten reddetmiştir.

### Uygulama zamanında ikinci bir savunma hattı

`validate_plan()` `..`'yi **sözcüksel olarak (lexically)** engeller, ancak ağacın içinde önceden var olan bir sembolik bağlantı yine de bir yazmayı yeniden yönlendirebilir. Bu yüzden uygulama zamanında `contained()` gerçek hedef yolunu çözer ve modül tabanı altında oturduğunu doğrular, çözemediğinde hata durumunda kapanır. Yazmalar atomiktir (geçici bir ada yaz, ardından hedefin üzerine `rename` yap) ve her üzerine yazma önce `rollback/`'a yedeklenir; başarısız bir yedek, güvenlik ağı olmadan üzerine yazmak yerine uygulamayı iptal eder.

---

## İki profil

VDLU, yapılandırmada `profile=` ile ayarlanan iki güven profilinden birinde çalışır.

### `hardened` (herkese açık varsayılan)

- **İmza zorunludur.** Manifesto, cihaz üzerindeki keyring'de bulunan bir anahtardan geçerli bir ed25519 imzası taşımalıdır, yoksa işlem iptal edilir.
- **Alt sürüm engellenir.** `version`'ı kurulu sürümden düşük olan bir manifesto reddedilir. Bir saldırgan sizi bilinen güvenlik açığı olan bir yapıya geri alamaz.
- Bu, `https://` üzerinden herkese dağıtılan herhangi bir modül için profildir.

### `trusted` (özel, SSH ile aşamalanmış kaynak)

- İmza doğrulaması **elden geldiğincedir (best-effort)**: kaynak, kontrol ettiğiniz özel bir `file://` veya SSH ile aşamalanmış bir feed'dir, bu yüzden eksik veya doğrulanamayan bir imza sert bir şekilde iptal etmez.
- **Ancak her blob'un `sha256`'sı yine de her zaman kontrol edilir.** `trusted`, *manifestoyu kimin imzaladığını* gevşetir, asla *baytların plana uyup uymadığını* değil. İçerik bütünlüğü her iki profilde de pazarlık konusu değildir.

---

## Tersine çevirme yoluyla hata durumunda kapalı

Bu, ince kısımdır ve çoğu sistemin yanlış yaptığı kısımdır.

`trusted`, gevşetilmiş doğrulamaya katılan **tek** dizedir. Motor "bu `hardened` mı?" diye test etmez. "Bu `trusted` **değil** mi?" diye test eder:

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Yani sözlük anlamıyla `trusted` dışında **herhangi bir şey** hardened davranışına çözümlenir:

- satır tamamen eksik -> hardened
- `hardend` gibi bir yazım hatası -> hardened
- sonda boşlukla `trusted `, veya CRLF'den bir `\r` -> hardened
- yanlış harf durumuyla `Trusted` -> hardened
- MITM tarafından bozulmuş bir değer -> hardened

Daha önceki bir sürüm *eksik* bir satırı hardened olarak varsayıyordu, bu da bozuk bir *değerin* açık yola düşmesine izin veriyordu. Bu bir fail-open'dı: bozulmuş bir profil dizesi sessizce imzasız bir manifestoyu kabul edebilirdi ve imzasız bir manifesto, MITM altında değiştirilmiş saldırgan tarafından sağlanan bir `.so` anlamına gelir, bu da kök seviyesinde uzaktan kod yürütmedir. Tersine çevirme bunu kapatır. Gevşetilmiş doğrulama elde etmenin tek yolu `trusted`'ı tam olarak hecelemektir ve o zaman bile blob hash'leri kontrol edilir. Motor asla imzasız kodu kabul etmekten bir yazım hatası uzakta değildir. (`tr -d`, sağlıksız boşluklu meşru bir `trusted`'ın yanlışlıkla reddedilmemesi için başıboş boşlukları, deliği yeniden açmadan sıyırır.)

**Bu test yük taşıyıcıdır (load-bearing). `!= trusted` olarak kalmalı ve asla `== hardened` olmamalıdır.**

---

## Manifesto modüle bağlıdır

Tek bir yayın anahtarı birçok modülü imzalar. Yani *farklı* bir modül için geçerli olarak imzalanmış bir manifesto, prensipte buna sunulabilir (bir feed yanlış yapılandırması, bir kaynak değişimi veya bir MITM yönlendirmesi) ve imzası doğrulanabilir.

VDLU bunu bir bağlama ile kapatır: manifesto içindeki imzalı `module` alanı, bu kurulumun `MODID`'sine eşit olmalıdır, yoksa manifesto çapraz-modül bir feed olarak reddedilir. `module` imzalı kanonik biçimin içinde olduğundan, bir saldırgan onu imzayı bozmadan değiştiremez. B modülü için geçerli olarak imzalanmış bir feed, A modülüne basitçe uygulanamaz.

---

## İnce cihaz üstü doğrulayıcı

Cihazdaki doğrulama **ed25519-mini** kullanır, TweetNaCl (kamu malı) üzerine kurulu küçük, yalnızca-doğrulama bir denetleyici. Cihazda **`openssl` yok**.

- Keyring girdisi, `keyring/<key_id>.pub` olarak depolanan **ham 32 baytlık açık anahtardır**. (PEM açık anahtar yalnızca bir PC tarafı yapıdır; bir PEM'i cihaz keyring'ine kopyalamak doğrulamayı bozar, çünkü doğrulayıcı tam olarak 32 ham bayt bekler.)
- `vdlu-verify <manifest.json> <keyring_dir>` kanonik biçimi yeniden oluşturur (`sig` alanı kaldırılmış manifesto metni, sıkıştırılmış, sıralı anahtarlar), onu imzanın kapsadığı 64 karakterlik hex mesaja hashler, base64 imzayı çözer, 64 bayt olduğunu kontrol eder ve bir karar için `ed25519-mini <pub32> <msg> <sig64>`'e sorar. rc 0 = geçerli, başka herhangi bir şey = ret.
- İkili, ABI başına statiktir (arm64-v8a, armeabi-v7a, x86, x86_64), tam TweetNaCl kaynaklarını, sarmalayıcı hash'ini ve yapı bayraklarını sabitleyen bir `PROVENANCE.json` ile, böylece kök olarak çalışan şey denetlenebilir (auditable).
- Manifestodan gelen `key_id`, bir keyring dosyası seçmek için kullanılmadan önce kendisi temizlenir (`/` yok, `..` yok, tırnak yok), böylece keyring dizininden kaçamaz.

### Keyring yalnızca-flash, doğrula-kopyalama-değil, kararlı

Keyring, flash zamanında modülün içinde gönderilir ve güncelleme motoru tarafından yeniden yazılmaz. Yeniden gömmede kural **doğrula, kopyalama**'dır: keyring yalnızca kasıtlı bir anahtar döndürmede değişir, asla bir güncellemenin yan etkisi olarak değil.

### Anahtar döndürme eski kurulumları tuğlalaştırmaz

Bir imzalama anahtarı döndürüldüğünde, keyring **hem mevcut hem de önceki ham açık anahtarları** gönderir. Doğrulayıcı anahtar dosyasını manifestonun `key_id`'siyle seçer, böylece hâlâ eski anahtarla imzalanmış bir feed eski pubkey'e karşı doğrulanır ve yeni anahtarla imzalanmış bir feed yenisine karşı doğrulanır. Döndürmenin ötesine güncellenmeyen bir cihaz çalışmaya devam eder; hiçbir şey öksüz kalmaz.

---

## Araç manifestosunun kapattığı şey

İnce fetch önyükleyicisi, kendi curl'lerini göndermeyen modüller için ilk kullanımda statik bir `curl` indirir. Bu ikili kök olarak çalıştığı için, kendi manifesto imzası (ed25519-mini) ve hash'i, kurulmadan veya çalıştırılmadan önce `trusted` dahil **herhangi bir profilde zorunludur**. Webview yalnızca taşımadır; güven cihaz üzerindeki imza ve hash kontrolünden gelir, asla bir indirmenin başarılı olması gerçeğinden değil.

---

## Bir saldırganın YAPAMAYACAĞI şeyler

Feed'e sahip olsa veya tam bir MITM olarak hat üzerinde otursa bile, bir saldırgan şunları yapamaz:

- **Modülün dışına yazmak.** Mutlak yollar, `..`, `.`, kontrol karakterleri ve sondaki eğik çizgiler herhangi bir uygulamadan önce reddedilir ve sembolik bağlantı yeniden yönlendirmesi uygulama zamanında tekrar yakalanır.
- **Modülün dışında silmek.** `delete[]` girdileri aynı yol doğrulamasını geçer.
- **Bir komut enjekte etmek.** Hiçbir manifesto değeri bir kabuğa veya `awk system()`'e enterpole edilmez; `sha256` saf 64-hex olmalı yoksa tüm manifesto reddedilir.
- **Herkese açık bir kuruluma imzasız kod göndermek.** `hardened` imzayı zorunlu kılar ve profil tersine çevirme yoluyla hata durumunda kapalıdır, bu yüzden hiçbir yazım hatası veya bozulmuş değer onu düşürmez.
- **Burada başka bir modülün imzalı feed'ini sunmak.** İmzalı `module` alanı bu `MODID`'ye eşit olmalıdır.
- **Sizi geri almak.** Alt sürüm `hardened`'da engellenir.
- **Bir blob'u fark edilmeden bozmak.** İndirilen her blob her iki profilde de manifesto `sha256`'sına karşı yeniden hashlenir; üç denemeden sonra bir uyuşmazlık, hiçbir şey uygulanmadan aşamayı iptal eder.
- **Sahte bir kök alıcı yerleştirmek.** Önyüklenen `curl`, her profilde kurulmadan veya çalıştırılmadan önce imza ve hash kontrollüdür.
- **Bozuk bir güncellemeyi yarı uygulamak.** İşlem yalnızca her şeyin yeniden hash'i eşleştiğinde `DONE`'a ulaşır; başarısız bir uygulama bir yedek olmadan üzerine yazmak yerine geri alınır.

---

Ayrıca bakınız: manifesto şeması için [[Feed Format]], bu denetimlerin yaşadığı işlem için [[Engine]] ve büyük resim için [[Architecture]].
