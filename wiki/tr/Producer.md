# Üretici (Producer)

**Üretici**, VDLU'nun PC / yayın (release) tarafıdır: bitmiş bir modül ağacını, cihazın güncellenebileceği imzalı, içerik adresli bir feed'e dönüştüren küçük araç kümesi. Burada hiçbir şey telefonda çalışmaz. Bu araçlar yayın makinenizde (veya güvenli olan kısımlar için CI'da) çalışır.

Bunlardan dört tane vardır:

| Araç | Çalıştığı yer | Dil | İş |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Son modül ağacını `manifest.json` + `blobs/<sha256>`'a dolaş |
| `vdlu-keygen` | PC | sh + openssl | Bir ed25519 imzalama anahtar çifti üret |
| `vdlu-sign` | PC | sh + openssl | Bir manifestoya yerinde `key_id` + imza enjekte et |
| `vdlu-gc` | PC | python3 | Yayınlanmış bir feed'den yetim blob'ları buda (hataya karşı güvenli) |

Yayın akışı, yayın başına bir kez yapılan üç adımdır: **paketle, sonra imzala, sonra yayınla**. `vdlu-keygen` tek seferlik bir kurulumdur ve `vdlu-gc`, feed büyüdüğünde çalıştırdığınız bir temizlik işidir. Üreticinin yaydığı her şey, cihazdaki motorun tükettiği şey olan [[Feed Format]]'a uyar.

---

## vdlu-pack

`vdlu-pack`, **`.zip`'inizin gönderdiği tam ağacı** (son ağaç, yapınız kendi beyaz listesini ve ABI budamasını uyguladıktan sonra) alır ve onun için feed'i üretir.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

`<out_dir>` içine iki şey yazar:

- `manifest.json` - hedef ağacın tam açıklaması (her dosya `sha256`'sı, `size`'ı, `mode`'u, kodlaması ve yeniden başlatma sınıfı ile), hâlâ **imzasız** (`key_id` ve `sig` alanları boş yer tutuculardır).
- `blobs/<sha256>` (veya `blobs/<sha256>.gz`) - farklı dosya içeriği başına bir blob.

### İçerik adresli ve tekilleştiren

Her blob, **orijinal (sıkıştırılmamış) içeriğinin sha256'sı** ile adlandırılır. Ad hash olduğu için, aynı içerik aynı blob'a iner. `vdlu-pack` bir blob'u yalnızca zaten mevcut değilse yazar, yani:

- Değişmeyen bir dosya aynı blob adını korur ve asla yeniden yazılmaz veya yeniden gönderilmez.
- Aynı içeriğe sahip iki farklı dosya bir blob'u paylaşır.
- Geri alınan bir dosya, önceden zaten orada olan blob'u yeniden kullanır.

Bu nedenle yayınlama **yapı gereği artımlıdır**: yayınlar arasında `blobs/` yalnızca büyür ve yalnızca gerçekten yeni içerik eklenir. Cihaz aynı hash'lerle alır, bu yüzden yalnızca henüz sahip olmadığı blob'ları indirir.

### Sıkıştırma (`enc` alanı)

Her dosya için `vdlu-pack`, blob'un nasıl depolanacağına karar verir:

- Dosya en az 4096 bayt olduğunda **ve** gzip (belirlenimci `-9 -n`) en az yüzde 10 tasarruf sağladığında `gz`.
- Aksi halde `raw` (hat üzerindeki gzip'in zaten kapsadığı küçük dosyalar veya zaten sıkıştırılamaz veri).
- Yapı sunucusunda `gzip` eksikse, her şey `raw` depolanır. Paketleme bunun yüzünden asla başarısız olmaz.

Manifestodaki `sha256` **her zaman** orijinal içeriğe aittir; `enc` yalnızca blob'un nasıl depolandığını adlandırır. Cihaz `gz` blob'ları toybox `gunzip` ile açar ve ardından hash'i orijinale karşı kontrol eder.

### Yeniden başlatma sınıfı ve güvenlik

`vdlu-pack` ayrıca her dosyayı yolundan türetilen bir yeniden başlatma `class`'ı (`live`, `soft`, `reboot`) ile etiketler, böylece motor neyin yeniden başlatma olmadan uygulanabileceğini ve neyin aşamalanması gerektiğini bilir. Kurallar ve cihazın her sınıfla ne yaptığı [[Reboot Handling]]'de ele alınır.

`vdlu-pack`'in kasıtlı olarak **yapmadığı** birkaç şey:

- Sembolik bağlantıları (symlink) izlemez (bir uyarı ile atlar, böylece ağacın dışındaki içerik, bir sistem dosyasına bağlantı gibi, asla bir blob'a sızamaz).
- Normal olmayan dosyaları atlar (dizinler, fifo'lar, aygıtlar).
- `built` zaman damgası için `SOURCE_DATE_EPOCH`'a uyar, böylece manifestolar yeniden üretilebilir (reproducible).
- Sabit bir yol kümesini feed'den tamamen hariç tutar (güven kökü, kurulum iskeleleri ve birkaç diğeri). Tam liste ve her birinin neden hariç tutulduğu [[Feed Format]] içindedir.

### `delete[]` listesi

`--prev <previous manifest.json>`'u geçin ve `vdlu-pack` `delete[]`'i hesaplar: önceki yayında var olan ancak bunda gitmiş olan yollar, böylece cihaz arkasında yetimler bırakmak yerine onları kaldırır. Hariç tutulan yollar, önceki manifestoda görünseler bile asla silme olarak yayılmaz (tam semantik için bkz. [[Feed Format]]).

---

## vdlu-keygen

Tek seferlik bir adım. `vdlu-keygen`, feed'iniz için ed25519 imzalama anahtar çiftini oluşturur.

```sh
vdlu-keygen <id> <out_dir>
```

Üç dosya yazar:

| Dosya | Nedir | Nereye gider |
|---|---|---|
| `<id>.pem` | **Özel** imzalama anahtarı (mod `0600`) | Yayın makinenizde kalır. Asla. |
| `<id>.pub` | PEM olarak açık anahtar | Yalnızca PC tarafı araçlar |
| `<id>.pub.raw` | **Ham 32 bayt** olarak açık anahtar | Modülün cihaz üzerindeki keyring girdisi olarak gönderilir |

Ham 32 baytlık açık anahtar, cihaz doğrulayıcısının okuduğu şeydir (`openssl` taşımaz, bu yüzden PEM'i okuyamaz). `<id>.pub.raw`'ı modüle `vdlu/keyring/<id>.pub` olarak gömersiniz. PEM yalnızca PC tarafı kullanım içindir. Bu ayrım ve anahtar döndürmenin (key rotation) nasıl çalıştığı [[Security and Trust Model]] içinde açıklanmıştır.

> Özel `.pem`, tüm sistemdeki tek sırdır. Onu her cihazdan uzak ve her depo (repository) gönderiminin dışında tutun. Aşağıdaki CI notuna bakın.

---

## vdlu-sign

`vdlu-sign`, `vdlu-pack`'in ürettiği imzasız manifestoyu alır ve onu **yerinde** imzalar.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

`key_id` alanını ayarlar, manifestonun kanonik biçimini hesaplar ve ed25519 imzasını (base64) `sig` alanına yazar. İmza, manifestonun kesin bir bayt dönüşümü üzerindedir, böylece PC ve cihaz, cihazda hiçbir JSON kütüphanesi olmadan tam olarak aynı imzalı baytları türetir. Bu dönüşüm (**kanonikleştirme**), biçimdeki en önemli tek değişmezdir (invariant) ve [[Feed Format]]'da tam olarak belgelenmiştir.

Özel anahtar yalnızca burada, makinenizde okunur ve asla ondan ayrılmaz.

### İmzalama anahtarı CI'dan uzak kalır

Bu kasıtlı bir tasarım noktasıdır. CI, `vdlu-pack` çalıştırabilir ve tamamen geçerli bir **anahtarsız temel çizgi (keyless baseline)** (imzasız bir tohum manifestosu; bkz. [[Feed Format]]) üretebilir, böylece yeni bir kurulum, CI asla bir özel anahtara dokunmadan güncel doğar. Yayınlanan feed'in asıl imzalanması, sizin tarafınızdan, yerel olarak, `vdlu-sign` ile yapılır. Bu şekilde imzalama anahtarı yüzde 100 CI'nın dışındadır ve yalnızca elle yayınladığınız feed imzalanır.

---

## vdlu-gc

Blob'lar içerik adresli ve değişmez (immutable) olduğundan, `blobs/` yalnızca büyür: `vdlu-pack` ekler, asla kaldırmaz. Birçok yayın boyunca feed (ve onu barındıran Pages sitesi), hiçbir mevcut manifestonun artık referans vermediği blob'ları biriktirir. `vdlu-gc` bu yetimleri budar.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Manifestoların **tutulan kümesini (retained set)** oluşturur: mevcut `manifest.json` artı sürüme göre son `N` arşivlenmiş manifesto (varsayılan `N=3`, bir geri alma payı verir) artı `--keep` ile adlandırdığınız herhangi biri. **Hiçbir** tutulan manifesto tarafından referans verilmeyen bir blob bir yetimdir ve kaldırma için bir adaydır. Tutulan küme bir birleşimdir (union), bu yüzden bir blob, tutulan herhangi bir yayın hâlâ ona ihtiyaç duyduğu sürece kalır; daha eski bir tutulan sürümde oturan bir cihaz asla alışını kaybetmez.

`vdlu-gc` güvenli olacak şekilde yapılmıştır:

- **Varsayılan olarak kuru çalıştırma (dry-run).** `--apply` olmadan, yalnızca neyi *kaldıracağını* yazdırır. Gerçekten silmek için `--apply` eklersiniz.
- **Hataya karşı güvenli.** Hiç tutulan manifesto bulamazsa, bir feed'i boşaltma riskini almak yerine budamayı reddeder.
- **Tarihe göre değil, referansa göre tutma.** Bir blob, bir zaman damgası yüzünden değil, bir tutulan manifesto ona işaret ettiği için tutulur.

Budamadan sonra, daha küçük feed'i sunucunuza gönderin. Sunucunuz toplu yazmaları hız sınırlıyorsa (rate-limit) yazmayı zamana yayın.

---

## Bir araya getirmek

Tipik bir yayın, baştan sona:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

VDLU'yu bir modüle benimsemenin tam işlenmiş örneği için bkz. [[Quick Start]]. Üreticinin yaydığı her şeyin hat üzerindeki şekli için bkz. [[Feed Format]]. Anahtar işleme arkasındaki mantık ve feed'den neyin dışarıda tutulduğu için bkz. [[Security and Trust Model]].
