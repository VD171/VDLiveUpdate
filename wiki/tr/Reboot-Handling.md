# Yeniden Başlatma Yönetimi

VDLU'nun tüm amacı, bir modülü yeniden flash etmeden ve mümkün olduğunda hiç yeniden başlatmadan güncellemektir. Bir modüldeki çoğu dosya, cihaz çalışırken değiştirilebilir. Birkaçı gerçekten değiştirilemez, çünkü çekirdek veya zygote süreci bunları zaten eşlemiştir ve bir sonraki önyüklemeye kadar bir değişikliği fark etmez.

VDLU'nun işi, bu iki grubu otomatik olarak birbirinden ayırmak, güvenli bir şekilde yapabildiği her şeyi **canlı** uygulamak ve yalnızca gerçekten önyüklemeye bağlı dosyaları, açıkça işaretlediği bir yeniden başlatmaya ertelemektir. Bu sayfa bunun nasıl olduğunu açıklar.

Bunun altındaki motor mekaniği için bkz. [[Engine]]. Büyük resim için bkz. [[Architecture]].

## Neden her seferinde yeniden başlatmayalım

Bir yeniden başlatma, bir güncellemenin birinden isteyebileceği en pahalı şeydir. Ne yapıyorlarsa onu kesintiye uğratır, bir dakika veya daha fazla sürer ve insanları güncellemelerden korkmaya alıştırır. İyi bir artımlı güncelleyici görünmez hissettirmeli: güncellemeye dokunursunuz, çalışan sistemin altında birkaç dosya değişir ve zaten yeni sürümdesinizdir.

Bu yüzden VDLU olağan varsayımı tersine çevirir. Varsayılan canlıdır. Bir dosya yalnızca kanıtlanabilir şekilde çekirdeğe veya zygote'a bağlı türlerden biri olduğunda bir yeniden başlatmaya ertelenir ve o zaman bile yalnızca o dosya bekler. Etrafındaki her şey yine de hemen güncellenir.

## Üç sınıf

Feed'deki her dosyaya bir sınıf atanır. Üretici bunu manifestoda açıkça ayarlayabilir, ancak pratikte sınıf yoldan türetilir ve motor bir dosyayı yalnızca `reboot`'a doğru yükseltir, asla `live`'a doğru düşürmez. Sınıflar şunlardır:

**LIVE** yaygın durumdur: web arayüzü varlıkları, ikililer, isteğe bağlı okunan betikler, yapılandırma dosyaları, `module.prop` ve aşağıdaki kurallarla eşleşmeyen başka her şey. Bir canlı dosya yedeklenir ve ardından sistem çalışırken hedefin üzerine atomik olarak yeniden adlandırılır. Yeniden başlatma yok ve değişiklik yeniden adlandırma yerine oturduğu anda yürürlüktedir.

**SOFT**, modülün kendi yaşam döngüsü betikleridir: `service.sh`, `post-fs-data.sh` ve `boot-completed.sh`. Bunlar tam olarak LIVE dosyalar gibi canlı uygulanır, bu yüzden yeni kopya zaten disktedir. Kendi sınıflarını almalarının nedeni, çalışan sistemin bu önyüklemede eski kopyayı zaten yürütmüş olmasıdır; yenisi basitçe bir sonraki önyüklemede çalışır, aşamalama olmadan ve afiş olmadan. Ertelenecek bir şey yok, sadece doğal bir devir teslim.

**REBOOT-hard**, çalışan bir sistemde değiştirilemeyen küçük kümedir:

- yerel kütüphaneler, `*.so` (bir `zygisk/` yolu altındaki her şey), çünkü zygote bunları başlangıçta her uygulamaya eşler;
- `/system` katman dosyaları, çünkü katman önyüklemede bağlanır;
- `sepolicy.rule` dosyaları, çünkü SELinux politikası erken yüklenir.

Bir REBOOT-hard dosyası, sistem çalışırken asla canlı inode'unun üzerine yazılmaz. Zygote'un zaten eşlediği bir `.so`'nun üzerine yazmak, çökmeleri ve tutarsız durumu elde etme şeklinizdir. Bunun yerine yeni içerik durum dizininin yanında **aşamalanır (staged)** ve herhangi bir şey onu eşleyebilmeden önce bir sonraki önyüklemede değiştirilir.

## Bir bakışta yoldan sınıfa

Motor sınıfı yoldan şöyle türetir:

| Yol deseni | Sınıf | Uygulanışı |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (`.so` dosyaları) | REBOOT-hard | aşamalanır, önyüklemede zygote öncesi değiştirilir |
| `system/**` (katman) | REBOOT-hard | aşamalanır, önyüklemede değiştirilir |
| `*.rule` (sepolicy) | REBOOT-hard | aşamalanır, önyüklemede değiştirilir |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | canlı yazılır, bir sonraki önyüklemede çalışır |
| `webroot/**`, `bin/**`, `lib/**`, yapılandırmalar, `module.prop`, diğer her şey | LIVE | canlı yazılır, hemen yürürlükte |

Manifesto dosya başına açık bir `class` taşıyabilir, ancak türetilen sınıf bir taban (floor) işlevi görür: bir dosya yoluna göre REBOOT-hard görünüyorsa, manifesto aksini söylese bile REBOOT-hard olarak ele alınır. Bu, yanlış etiketlenmiş bir feed'in asla bir `.so`'yu sıcak değiştirmeye (hot-swap) çalışmasını engeller.

## Bir çalıştırma her iki grubu aynı anda nasıl yönetir

Normal bir `run` sırasında ([[Engine]]'de açıklanan DIFF'ten FETCH'e, APPLY'a, COMMIT'e döngü), iki grup aynı işlemde yönetilir:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Yani bir `.so`'ya dokunan bir çalıştırmadan sonra, her canlı dosya için zaten yeni sürümdesiniz ve yalnızca aşamalanmış parçalar bekliyor. Günlük `reboot_pending` bildirir ve WebUI, aşamalanmış dosyaları etkinleştirmek için bir yeniden başlatmaya davet eden kalıcı bir afiş gösterir. Sahte bir "done" yoktur: aşamalanmış dosyalarla bir çalıştırma `DONE`'da değil, `PENDING_REBOOT`'ta biter.

## Önyüklemedeki değişim

Aşamalanmış dosyalar, ana modülün senkron ve **zygote öncesi** çalışması için `post-fs-data.sh`'ye bağladığı `boot` komutu tarafından uygulanır, herhangi bir süreç yeni `.so`'yu eşleyemeden önce.

`boot` bir `resume` yapar (kesintiye uğramış herhangi bir aşamayı bitirmek için) ve ardından değişimi yapar. Aşamalanmış her REBOOT-hard dosyası için şunları yapar:

1. aşamalanmış yolun modül dizini içinde kaldığını onaylar (bir içerme kontrolü);
2. `staged/<path>.vdlu-new`'ü manifesto hash'ine karşı yeniden hashler;
3. mevcut canlı dosyayı yedekler;
4. aşamalanmış dosyayı canlı olanın üzerine `mv -f` eder ve `chmod`'lar;
5. değişimin doğru yere oturduğunu onaylamak için şimdi yerindeki dosyayı yeniden hashler;
6. uygulanmış olarak işaretler.

Yalnızca her aşamalanmış dosya değiştirilip yeniden doğrulandığında işlem `PENDING_REBOOT`'tan `DONE`'a kapanır. Herhangi bir adım başarısız olursa, günlük hatayı kaydeder ve modül önceki dosyalarını korur; hiçbir şey yarı değiştirilmiş bırakılmaz.

Değişim bir yeniden hash'ler ve atomik yeniden adlandırmalar dizisi olduğundan, `boot`'u çalıştırmak son seferinde kesintiye uğramış olsa bile güvenlidir. Aşamalanmış dosyaları basitçe tekrar alır.

## auto_on_reboot

Aşamalama, yeniden başlatmasız bir hissin yalnızca yarısıdır; diğer yarısı, kullanıcının değişimi çalıştırmayı asla hatırlamak zorunda kalmaması gerektiğidir. Yapılandırmada `auto_on_reboot=1` ile, ana modülün `post-fs-data.sh`'si her önyüklemede `update.sh boot`'u çağırır. Bu şu anlama gelir:

- bir işlem yeniden başlatma bekliyorsa, aşamalanmış dosyalar zygote başlamadan önce otomatik olarak değiştirilir ve kullanıcı kendini basitçe tamamen yeni sürümde bulur;
- bekleyen bir şey yoksa, `boot` yeni bir döngü çalıştırabilir ve zaten zygote öncesi çalıştığı için o tek önyüklemede `.so` dahil her şeyi uygulayabilir.

Başka bir deyişle, aşamalanmış bir `.so`, kullanıcıya zaten yapacakları bir yeniden başlatmanın ötesinde hiçbir maliyet getirmez. İkinci kez hiçbir şeye dokunmak zorunda değiller.

## Önyüklemede çevrimdışı, pili boşaltmadan

Bazen `boot` feed'i kontrol etmek ister ama cihazın henüz ağı yoktur. VDLU onu bekleyebilir, sabırla ve ucuza, `boot_retry_minutes` ile kontrol edilir (0 onu kapatır). Bekleme kasıtlı olarak pil açısından güvenlidir:

- denemeler arasında basitçe `sleep` yapar, bu derin uykuda donar, böylece cihaz normal şekilde uyur ve yeniden deneme yalnızca cihaz zaten uyanıkken devam eder;
- bir wakelock tutmaz ve beklerken motor kilidini tutmaz, böylece manuel bir çalıştırma asla engellenmez;
- her denemeden önce, hiçbir paket göndermeyen ve radyoyu uyandırmayan bir çekirdek rota araması ile ağa izin verilip verilmediğini kontrol eder;
- kötü bir imza veya engellenmiş bir alt sürüm gibi belirlenimci bir başarısızlığı asla yeniden denemez, yalnızca gerçek bir ağ-yokluğu durumunu.

Manifesto kontrolünün kendisi herhangi bir ağda ücretsiz kalır, böylece bir güncellemenin var olduğunu her zaman öğrenirsiniz; yalnızca indirme, ağ politikasının karşılanmasını bekler, hata vermek yerine temiz bir şekilde erteler.

## Ayrıca bakınız

- [[Engine]]: işlem, sınıfa göre uygulama mantığı ve tam `boot` komutu.
- [[Architecture]]: motorun üretici ve WebUI arasında nerede oturduğu.
