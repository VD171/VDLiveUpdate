# Mimari

VDLU, ortadaki tek bir şeyle birleştirilmiş iki tarafa sahiptir. PC'de, [[Producer]] bir modül ağacını imzalı, içerik adresli bir feed'e dönüştürür. Cihazda, [[Engine]] bu feed'i okur, neyin değiştiğini hesaplar ve uygular. Aralarındaki dikiş **imzalı manifesto artı blob deposudur** (bkz. [[Feed Format]]). Boşluğu başka hiçbir şey geçmez.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

İki taraf asla bir çalışma zamanını paylaşmaz. Producer `python3` ve `openssl` kullanır; Engine, toybox ve gömülü bir `ed25519-mini` ile saf POSIX `sh`'dir. Yalnızca her ikisi de bir manifestodan **aynı kanonik baytları** türettiği için anlaşırlar (bkz. [[Security and Trust Model]]). WebUI, motoru kök yöneticisi köprüsü üzerinden çalıştıran ve ilerleme günlüğünü okuyan ince, vanilla JS bir paneldir; kendi güncelleme mantığını barındırmaz. Bkz. [[WebUI]].

## İki taraf

| Taraf | Çalıştığı yer | Yapıldığı şey | İş |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Modül ağacını `manifest.json` + `blobs/`'a dolaş, imzala, yetim blob'ları buda |
| [[Engine]] | cihaz | POSIX `sh` + toybox + `ed25519-mini` | Kurulu ağacı feed ile karşılaştır, farkları al, uygula, commit et |
| [[WebUI]] | cihaz (webview) | vanilla JS/CSS | Güncellemeleri tetikle, ilerlemeyi göster, yapılandırmayı düzenle, yeniden başlatma afişini göster |

## Güncelleme hattı (pipeline)

Her güncelleme tek bir işlemdir, sabit bir sırada çalıştırılır:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` bu aşamadır, salt okunur). Motor yalnızca manifestoyu indirir, herhangi bir şeye dokunmadan **önce** her alan üzerinde `validate_plan()` çalıştırır, ardından dosya başına bir plan oluşturmak için feed'i `current.json` ile karşılaştırır. Diskte hiçbir şeyi değiştirmez. Feed'in ilerisinde olan bir cihaz zararsız bir "ahead" (ileride) sonucudur, bir hata değil.
- **FETCH.** Yalnızca planın eksik olduğu blob'ları `<sha>.part` içine indirir, `gz`'yi açar, `sha256sum`'ı manifesto ile kontrol eder ve her doğrulanmış blob'u atomik olarak önbelleğe `mv` eder. Zaten önbelleğe alınmış (veya değişmemiş yerel bir dosyadan tohumlanmış) bir blob atlanır, böylece bir geri alma veya paylaşılan bir dosya hiçbir maliyet getirmez. Tek bir blob üzerinde üç başarısızlık, hiçbir şey uygulanmadan aşamayı iptal eder. Ağ politikası tarafından engellenen bir indirme bir hata olarak değil, `DEFERRED` (devam ettirilebilir) olarak çıkar.
- **APPLY.** Sıradan (`live` / `soft`) dosyalar şimdi yazılır: `rollback/<v>/`'ye yedekle, bir `.vdlu-tmp` yaz, `chmod` et, doğrula, ardından hedefin üzerine atomik `rename` yap. Yeniden başlatma sınıfı dosyalar `staged/<path>.vdlu-new` içine maddeleştirilir ve canlı inode'a dokunulmaz. Bir `delete[]` girdisi yedeklenir, ardından kaldırılır. Her adım idempotenttir: hedef hash'te zaten bulunan bir dosya atlanır.
- **COMMIT.** Her canlı dosyayı yeniden hashle; yalnızca her şey eşleşirse motor `target.json`'u `current.json`'a yükseltir. Herhangi bir şey aşamalanmışsa işlem `PENDING_REBOOT` ile biter; aksi halde `DONE`.

## İçerik adresli manifesto ve blob'lar

Feed içerik adreslidir: manifesto, her dosyanın kendi `sha256`'sı ile taşındığı **tüm** hedef ağacı listeler ve blob deposu, her farklı içeriğin bir kopyasını `blobs/<sha256>` (veya `blobs/<sha256>.gz`) altında tutar.

- **Tekilleştirme (dedup).** Ağacın herhangi bir yerinde veya yayınlar arasında aynı içerik tek bir blob'dur. Yayınlama artımlıdır: `sha256`'sı sunucuda zaten bulunan bir blob asla yeniden gönderilmez ve cihaz zaten sahip olduğu içeriği asla yeniden almaz.
- **sha256 orijinaline aittir.** Hash her zaman sıkıştırılmamış içeriği adlandırır; `enc` (`raw` veya `gz`) yalnızca o blob'un nasıl depolandığını kaydeder. Cihaz `gz`'yi toybox `gunzip` ile açar, bu yüzden ekstra bir sıkıştırıcı paketlenmez.
- **Çeşit-kararlı.** Cihaz, gerçekten kurulu olana karşı fark aldığı için, feed tüm bir modül ailesini taşıyabilir; her kurulum yalnızca kendi çeşidini tamamlayan blob'ları çeker.

Tam alan-alan düzeni [[Feed Format]] içindedir.

## Devam ettirilebilir günlük (journal)

Her işlem çökmeye karşı güvenlidir çünkü ilerlemesi bir günlükte (`journal.json`) yaşar ve devam eden işlemin sabitlenmiş hedefi `target.json`'da yaşar. Durum makinesi sabit bir sırada çalışır:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Durum | Anlamı |
|---|---|
| `PLANNED` | Plan oluşturuldu, henüz hiçbir şey alınmadı |
| `FETCHING` / `FETCHED` | Blob'lar indiriliyor / tüm blob'lar mevcut ve doğrulanmış |
| `APPLYING` / `APPLIED_LIVE` | Dosyalar yazılıyor / tüm canlı dosyalar yazıldı |
| `PENDING_REBOOT` | Bir yeniden başlatma sınıfı dosya aşamalandı, önyükleme değişimini bekliyor |
| `DONE` | Her şeyin yeniden hash'i eşleşti; `current.json` yükseltildi |
| `ERROR` | Sert başarısızlık; modül bozulmadan bırakıldı, canlı dosyalar `rollback/`'tan geri alındı |
| `DEFERRED` | İndirme ağ politikasıyla geri tutuldu; plan devam eder, sonra sürdürülür |

`DONE` yalnızca her şeyin yeniden hash'i eşleştiğinde **ulaşılır**, bu yüzden günlük asla yarı uygulanmış bir güncellemenin tamamlandığını iddia etmez. Bir çökme, kopan bir ağ veya ortada bir yeniden başlatma devam ettirilebilir bir günlük bırakır; `update.sh resume` (veya `boot`) mevcut aşamadan devam eder. Komut seti ve cihaz üzerindeki durum dosyaları için bkz. [[Engine]].

## Atomiklik ve geri alma

Hiçbir şey asla yerinde üzerine yazılmaz ve hiçbir şey kaybolmaz:

- **Atomik yazmalar.** Her dosya bir geçici dosya (`.vdlu-tmp`) ve atomik bir `rename` / `mv` ile yerine konur, böylece bir okuyucu asla yarı yazılmış bir dosya görmez.
- **Üzerine yazmadan önce yedek.** Önceki içerik, yeni dosya üzerine `rename` edilmeden önce `rollback/<version>/<path>`'ye gider (son birkaç sürüm tutulur). Bir uygulama başarısız olursa, canlı dosyalar bozuk bırakılmak yerine geri alma kopyasından geri alınır. Başarısız bir yedek, güvenlik ağı olmadan üzerine yazmak yerine uygulamayı **iptal eder**.
- **Serileştirilmiş.** Bir `mkdir` tabanlı kilit (`lock.d/`, çünkü `flock` toybox'ta çalışmaz, PID ile bayat kilit kurtarma) eşzamanlı çalıştırmaları serileştirir.

## Yeniden başlatmasızlık ilkesi

Çoğu dosya modül canlıyken değiştirilebilir, bu yüzden VDLU bunları hemen uygular. Yalnızca üç sınıf yeniden başlatmaya ihtiyaç duyar, çünkü canlı bir süreç bunları zaten eşlemiştir: bir `.so` (Zygisk tarafından yüklenen), bir `/system` katmanı ve bir `sepolicy.rule`. Bunlar **aşamalanır, asla canlı bir inode üzerine yazılmaz** ve bir sonraki önyüklemede tek bir zygote öncesi adımda değiştirilir. Tam sınıflandırma ve önyükleme akışı [[Reboot Handling]] içindedir.

## Hata durumunda kapalı güven duruşu

Feed, PC'den cihaza geçen tek şeydir, bu yüzden motor onun her baytını düşmanca olarak ele alır. `validate_plan()`, herhangi bir indirmeden önce DIFF aşamasında çalışır ve herhangi bir hatalı biçimlendirilmiş alanda tüm manifestoyu reddeder. İmza doğrulaması gömülü bir `ed25519-mini` kullanır (cihazda `openssl` yok), özel anahtar asla bir cihaza veya CI'ya dokunmaz ve `hardened` profili tersine çevirme yoluyla hata durumunda kapalıdır, böylece bozuk bir profil değeri asla sessizce imzasız bir feed'i kabul edemez. Tam model, iki profil ve her birinin yanıtladığı tehditler [[Security and Trust Model]] içindedir.
