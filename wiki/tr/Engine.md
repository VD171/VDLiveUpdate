# Motor

Motor, VDLU'nun cihaz tarafıdır: telefonda çalışan, neyin değiştiğine karar veren, onu indiren ve uygulayan kısım. Tek bir POSIX kabuk betiği olan `engine/update.sh` artı küçük bir imza denetleyicisi olan `engine/vdlu-verify`'den oluşur. Her ikisi de ana modüle `<module>/vdlu/`'da gömülür ve kök (root) tarafından çalıştırılır.

Tüm motor tek bir fikir etrafında kurulmuştur: bir güncelleme **devam ettirilebilir bir işlemdir (resumable transaction)**. Telefon yeniden başlatılır, öldürülür veya yarı yolda ağı kaybederse, bir sonraki çalıştırma tam durduğu yerden devam eder ve modül asla bitmiş gibi davranırken yarı uygulanmış halde bırakılmaz.

Önce büyük resmi istiyorsanız bkz. [[Architecture]]. Güncellemelerin mümkün olduğunda yeniden başlatmadan nasıl kaçındığı için bkz. [[Reboot Handling]].

## Dizüstünüz için değil, cihaz için yazılmış

`update.sh` saf POSIX `sh`'dir. mksh, busybox veya toybox altında, yalnızca bash'e özgü özellikler olmadan çalışır ve `sh -n`'i geçer. Bu önemlidir çünkü köklenmiş bir Android cihazdaki ortam küçük ve katıdır.

Özellikle, `jq` yoktur. VDLU, `manifest.json`'u `awk` ile yazılmış küçük bir gron tarzı düzleştirici ile ayrıştırır: JSON'u birer karakter dolaşır ve yaprak başına bir `path<TAB>value` satırı yayar (örneğin `files/0/sha256<TAB>ab..` veya `version<TAB>6`). Kabuk daha sonra bu satırları `grep` ve `cut` ile okur. Bu, hem sıkıştırılmış hem de güzel yazdırılmış JSON üzerinde çalışır ve asla orada bulunmayan bir JSON aracını çağırmaz.

Motor yalnızca toybox'ın zaten sağladığı şeylere (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), gömülü `ed25519-mini` doğrulayıcısına ve `https://` feed'leri için bir kez alınan ve doğrulanan küçük bir statik `curl`'e bağımlıdır. Bir `file://` feed'i hiç `curl` gerektirmez.

## Altı komut

Motoru, ortamda modülün yollarıyla ve bir komutla çağırırsınız:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Çıkış kodu `0` başarı anlamına gelir; başka herhangi bir kod, nedeni stderr'e yazdırılan bir hata anlamına gelir.

| Komut | Yaptığı şey |
|---|---|
| `check` | Salt okunur fark (diff). Manifestoyu indirir, kurulu olanla karşılaştırır ve tek satırlık bir JSON özeti yazdırır: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Diskte hiçbir şeyi değiştirmez. Cihaz feed'den daha yeniyse (engellenmiş bir alt sürüm), bir hata değil, çıkış `0` ile `{"update":false,"ahead":true,...}` bildirir. |
| `run` | Tam canlı döngü: DIFF, FETCH, APPLY, COMMIT. Her canlı dosyayı hemen uygular ve birkaç yeniden başlatma sınıfı dosyayı aşamalar. `cancel`'e uyar. İlerlemeyi `journal.json`'a yazar. |
| `resume` | Kesintiye uğramış bir işlemi, hangi aşamada olursa olsun oradan başlayarak sürdürür. İdempotenttir. Aşamalanmış bir `.so`'yu değiştirmez (bu `boot` için ayrılmıştır). |
| `boot` | Zygote öncesi yol. Bir `resume` yapar ve ardından aşamalanmış tüm `*.vdlu-new` dosyalarını yerine koyar, `PENDING_REBOOT`'u `DONE`'a kapatır. Bekleyen bir işlem yoksa, yeni bir döngü çalıştırır ve o tek önyüklemede `.so` dahil her şeyi uygular. |
| `status` | `journal.json`'u veya devam eden bir şey olmadığında `{"state":"idle"}`'ı yazdırır. |
| `cancel` | Bir `cancel` işareti oluşturur. Devam eden bir `run`, bir sonraki güvenli noktada temiz bir şekilde durur. |

`check` komutu kasıtlı olarak ucuzdur, böylece arayüz size herhangi bir ağda bir güncelleme olduğunu söyleyebilir. Asıl indirme ayrıca kapılanır (aşağıdaki fetch aşamasına bakın).

## İşlem, adım adım

Her `run`, WebUI'nin (ve sizin) izleyebilmesi için `journal.json`'a kaydedilen sabit bir durum makinesi boyunca ilerler:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Motor `manifest.json`'u alır, her alanı doğrular (aşağıya ve [[Security and Trust Model]]'e bakın) ve imzalı hedef ağacı, zaten kurulu olan sürümün manifestosu olan `current.json` ile karşılaştırır. Sonuç, `plan.tsv`'ye yazılan dosya başına bir plandır: dosya başına bir satır, sınıfını, hedef hash'ini, modunu ve ilerleme durumunu taşır. Zaten hedef hash'te olan dosyalar atlanmak üzere işaretlenir.

**FETCH.** Hâlâ gereken her dosya için motor, içerik adresli blob'unu `<source>/blobs/<sha>`'dan (veya sıkıştırıldığında `<sha>.gz`) bir `.part` dosyasına indirir. Blob gzip'lenmişse açılır, ardından SHA-256'sı manifesto ile kontrol edilir. Yalnızca bir eşleşmede atomik olarak `blobs/<sha>`'ya `mv` edilir. Doğru bir hash ile zaten önbelleğe alınmış bir blob tamamen atlanır ve değişmemiş bir yerel dosya hiçbir indirme olmadan önbelleği tohumlayabilir. Aynı blob üzerinde üç başarısızlık, hiçbir şey uygulanmadan aşamayı iptal eder. Aşama yalnızca plandaki her blob mevcut ve doğrulanmış olduğunda `FETCHED`'e ulaşır. Bu blob'ların geldiği [[Feed Format]] için o sayfaya bakın. Araç zinciri kurulumunda motor, çözümlenen TLS güvenini - CA yolu ve okunabilir olup olmadığı, artı paketin boyutu ve sertifika sayısı - günlükler, böylece boot zamanındaki bir curl `rc 77`'si `boot.log`'ta kendi kendini açıklar (boş bir güven deposunu okunamaz olandan, yani boot SELinux-context durumundan ayırt eder).

Fetch, ağ politikasıyla kapılanır: bir feed yalnızca Wi-Fi'ye, yalnızca mobile veya herhangi bir ağa kısıtlanabilir. Mevcut ağa izin verilmediğinde, fetch başarısız olmaz; zararsız `DEFERRED` durumuna girer, planı ve hedefi sabitlenmiş tutar ve doğru ağ göründüğünde bir sonraki kontrol veya önyüklemede devam eder. Bu arada hiçbir veri harcanmaz.

**APPLY.** Yalnızca `FETCHED`'den girilir. Her dosya için motor sınıfa göre hareket eder:

- `live` ve `soft` dosyalar: mevcut dosyayı `rollback/<version>/<path>`'ye yedekle, yeni içeriği bir `.vdlu-tmp` kardeşine yaz, `chmod` et, hash'ini doğrula, ardından hedefin üzerine atomik olarak `rename` et. Zaten hedef hash'te olan bir dosya atlanır.
- `reboot` dosyalar (bir `.so`, bir `/system` katmanı, bir `sepolicy.rule`): `staged/<path>.vdlu-new` içine maddeleştir. Canlı inode'a burada asla dokunulmaz. Bkz. [[Reboot Handling]].
- silmeler: yedekle, ardından kaldır. Silmeler yalnızca en sonda, temiz bir `DONE`'da uygulanır, asla bir yeniden başlatma hâlâ beklerken değil.

**COMMIT.** Motor, dokunduğu her `live` ve `soft` dosyayı yeniden hashler. Yalnızca hepsi eşleştiğinde `current.json`'u yazar ve yeni sürümü fark temeli yapar. Herhangi bir yeniden başlatma sınıfı dosya aşamalanmışsa, durum `DONE` yerine `PENDING_REBOOT` olur; değişim ve son yeniden doğrulama daha sonra `boot` komutu altında gerçekleşir.

## Yapı gereği güvenli

Bunu gözetimsiz çalıştırmayı güvenli kılan garantiler:

- **Eşleşen bir yeniden hash olmadan hiçbir şey `DONE` olarak işaretlenmez.** `DONE`'a yalnızca her uygulanan dosya geri okunduktan ve SHA-256'sı manifesto ile karşılaştırıldıktan sonra ulaşılır. Aşamalanmış bir yeniden başlatma dosyası `PENDING_REBOOT`'u zorlar, asla sahte bir `DONE` değil.
- **Hiçbir şey kaybolmaz.** Her dosya üzerine yazılmadan önce `rollback/<version>/`'ye yedeklenir ve son üç sürüm tutulur. Bir uygulama başarısız olursa, canlı dosyalar yedekten geri alınır; modül asla yarı uygulanmış halde bunun hakkında yalan söyleyerek bırakılmaz. `apply_live`, yedek adımı başarısız olursa, geri dönüş olmadan üzerine yazmak yerine doğrudan iptal eder.
- **Her şey atomiktir.** Yeni içerik hedefin üzerine `rename`/`mv` ile yerine konur, böylece bir okuyucu ya eski dosyayı ya da yeni dosyayı görür, asla kesik bir yazmayı değil.
- **Bir çökme veya öldürmeden sonra devam ettirilebilir.** Bir çökme, kopan bir ağ veya ortada bir yeniden başlatma geçerli bir günlük bırakır; `resume` (veya `boot`) kaydedilen aşamadan devam eder. Tasarım, kesintiye uğrayacağını varsayar.
- **Temiz bir şekilde azalır.** Eksik bir ikili, çökmüş bir ağ veya dolu bir disk, modülü bozmadan stderr'de net bir hata ve günlükte `state:ERROR` üretir.
- **Güven çıpası hariç tutulur (`ENGINE_VERSION` 5).** Motor, getirilen bir plandaki her `vdlu/` yolunu - kendi `update.sh`, `vdlu-verify`, `verify/` ikilileri, keyring ve config - yok sayar, bu yüzden bir feed doğrulayıcıyı veya imzalama anahtarını asla ağ üzerinden değiştiremez; çıpa yalnızca tam imzalı bir yeniden-flaş ile değişir. Bkz. [[Security and Trust Model]].
- **Modül meşgulken bir güncelleme ertelenir.** Opt-in `apply_busy_file`, host modülün kendi işlemleri sırasında dokunduğu mutlak bir yola (örneğin çalışan bir yedekleme) ayarlandığında, o yol var olduğu sürece APPLY bekler, bu yüzden dosyalar asla işlem ortasında değiştirilmez; blob'lar zaten getirilmiştir, bu yüzden sonraki tetikleme yeniden indirme olmadan uygular.
- **Boyut tavanları.** Bir dosya **128 MiB** ile ve manifest **2 MiB** ile sınırlıdır, her ikisi de hem `update.sh` hem de `vdlu-verify`'da okunmadan önce uygulanır (anti decompression-bomb / anti-OOM).
- **Feed'in ilerisindeki bir modül asla geri alınmaz (`ENGINE_VERSION` 7).** Modülün kendi `module.prop` dosyasından okunan canlı kurulu `versionCode`, "from" sürümünün tabanını belirler, böylece eski bir feed'in ötesine elle güncellenmiş bir cihaz *ileride* olarak okunur: downgrade koruması zararsız döner, plan yok ve geri alma yok. `boot` ayrıca mevcut bir kurulumu kendi kendine onarır - hedefi kurulu sürümün altında olan kalıcı bir plan ya da `target <= 0` olan eski bir journal (`ENGINE_VERSION` 6), herhangi bir resume'den önce temizlenir.

## Kilit

Durumu aynı anda yalnızca bir işlem değiştirebilir. `flock` toybox'ta güvenilir değildir, bu yüzden VDLU bir dizin kilidi ile serileştirir: `mkdir "$VDLU_DIR/lock.d"` tam olarak bir çağıran için başarılı olur ve geri kalanlar için başarısız olur, bu da herhangi bir makul dosya sisteminde atomiktir. Ölü bir süreç tarafından bırakılan bayat bir kilit, kaydedilen PID kontrol edilerek kurtarılır.

Sabırlı önyükleme zamanı yeniden deneme (cihaz önyüklemede çevrimdışıyken kullanılır), beklerken bu kilidi **tutmaz**. Denemeler arasında edinir ve serbest bırakır, böylece manuel bir `run` asla ağı bekleyen bir önyükleme tarafından engellenmez ve asla bir wakelock tutmaz. Tasarım gereği pil açısından güvenli. Bununla ilgili daha fazlası [[Reboot Handling]] içinde.

## İmza denetimi: `vdlu-verify`

`vdlu-verify`, cihaz üzerindeki imza denetleyicisidir, kasıtlı olarak ince tutulmuştur:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Çıkış `0`, manifestonun imzasının, id'si manifestonun `key_id`'siyle eşleşen keyring açık anahtarına karşı geçerli olduğu anlamına gelir; başka herhangi bir kod bir reddir.

Onu ince kılan şey, **cihazda `openssl` kullanmamasıdır**. Keyring açık anahtarını **ham 32 baytlık** bir dosya olarak okur, manifestoyu kanonikleştirir (`sig` alanı kaldırılmış manifesto metni), toybox `sha256sum` ile hashler, imzayı base64 çözer ve ham anahtarı, mesajı ve 64 baytlık imzayı gömülü `ed25519-mini` ikilisine teslim eder. Denetleyici ayrıca doğrulamadan önce herhangi bir hatalı biçimlendirilmişi reddeder: eksik veya boş bir `key_id` veya `sig`, yol ayırıcıları içeren bir `key_id`, tam olarak 32 bayt olmayan bir açık anahtar veya tam olarak 64 bayt olmayan bir imza.

Bir anahtar seçmeden önce bile, motor bir **`key_id` izin listesi** uygular: manifestonun `key_id`'si, yapılandırmanın bir *modül güncellemesi* imzalamasına izin verdiği bir anahtar olmalıdır ve yalnızca keyring'de bulunan ama izin listesinde olmayan bir anahtar, pubkey'i hiç yüklenmeden reddedilir. Tek anahtarlı bir keyring o anahtarı yapılandırma olmadan otomatik olarak sabitler; çok anahtarlı bir keyring `key_id`'yi sabitlemelidir yoksa motor kapalı başarısız olur. İzin verilen küme `vdlu-verify`'a `VDLU_KEYID_ALLOW` olarak aktarılır ve her iki profilde de geçerlidir. Bu, keyring'i paylaşan bir parmak izi feed'i anahtarı gibi daha düşük güvenli bir anahtarın tam bir root güncellemesi imzalamasını durdurur; ayrı parmak izi feed'i kendi sabitlenmiş anahtarını, `FEED_KEY_ID`'yi korur. Tam hikaye [[Security and Trust Model]] içindedir.

Kanonikleştirme, üreticinin imzalayıcısıyla bayt-bayt aynıdır, bu da bir imzanın araçlar arasında doğrulanmasını sağlayan şeydir. Eşleşen özel anahtar asla bir cihaza veya CI'ya dokunmaz; yalnızca ham açık anahtar gömülüdür. Tam güven hikayesi, iki profil ve `hardened`'in neden tersine çevirme yoluyla hata durumunda kapalı olduğu [[Security and Trust Model]] içindedir.

Motor, fark aşaması sırasında `vdlu-verify`'ı çağırır. `hardened` profili altında başarısız bir doğrulama tüm güncellemeyi iptal eder; `trusted` altında doğrulama elden geldiğince (best-effort) yapılır, ancak her blob'un hash'i yine de her zaman kontrol edilir, böylece bozuk içerik profilden bağımsız olarak yakalanır.

## Diskteki durum

Motorun tüm durumu `$VDLU_DIR` içinde yaşar (modül dizininin dışında), böylece modül ağacının kendisi yalnızca bitmiş dosyaları tutar:

| Yol | Rol |
|---|---|
| `config` | key=value ayarları (source, profile, channel, ağ politikası, önyükleme yeniden denemesi) |
| `current.json` | etkin sürümün manifestosu; bu fark temelidir. Yokluğu asla güncellenmediği anlamına gelir |
| `target.json` | devam eden işlemin sabitlenmiş manifestosu. Varlığı etkin bir işlemi işaretler; `DONE`'da `current.json` olur |
| `plan.tsv` / `plan.del` | dosya başına plan ve ilerleme ve silinecek yolların listesi |
| `journal.json` | WebUI için ilerleme, her durum değişikliğinde yeniden yazılır |
| `blobs/<sha256>` | doğrulanmış, açılmış orijinal içeriğin önbelleği |
| `rollback/<version>/<path>` | üzerine yazılan dosyaların yedekleri; son üç sürüm tutulur |
| `staged/<path>.vdlu-new` | önyükleme değişimini bekleyen bir yeniden başlatma sınıfı dosya |
| `lock.d/` | mkdir kilidi |
| `tools/<abi>/curl` | alınan, doğrulanan statik curl; güncellemeler arasında kalıcıdır |
| `cancel` | bir iptal isteği |

## Ayrıca bakınız

- [[Reboot Handling]]: sınıf sisteminin çoğu güncellemeyi nasıl yeniden başlatmasız tuttuğu ve aşamalanmış bir `.so`'nun zygote öncesinde nasıl değiştirildiği.
- [[Security and Trust Model]]: iki profil, hata durumunda kapalı doğrulama ve ham anahtar ed25519 zinciri.
- [[Feed Format]]: motorun tükettiği manifesto ve içerik adresli blob'lar.
- [[Architecture]]: motor, üretici ve WebUI'nin nasıl birbirine uyduğu.
