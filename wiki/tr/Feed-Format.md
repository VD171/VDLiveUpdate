# Feed Formatı

**Feed**, VDLU'nun hat üzerinden sunduğu ve cihazın güncellendiği şeydir. Herhangi bir şey tarafından sunulabilen düz bir statik dizindir (GitHub Pages, bir rsync hedefi, bir `file://` yolu):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Modülün kendisi ayrıca `.zip` dosyasının içinde fazladan bir dosya olan `baseline.json`'u gönderir (feed'den sunulmaz). Bütün bunları oluşturan üretici [[Producer]]'da açıklanmıştır; bu sayfa hat üzerindeki sözleşmedir.

---

## manifest.json

Manifesto, bir yayının tam açıklamasıdır: hedef ağaçtaki her dosya, neyin silineceği ve her şeyin üzerindeki imza.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Alanlar

| Alan | Anlamı |
|---|---|
| `schema` | Manifestonun kendisinin biçim sürümü (şu anda `1`). |
| `module` | Modül id'si. Cihaz kendi modül id'siyle eşleşmezse manifestoyu reddeder, böylece farklı bir modül için geçerli olarak imzalanmış bir feed onun yerine sunulamaz. |
| `version` | Tam sayı sürüm. Motor yalnızca ileri günceller; cihazdan daha eski bir feed bir hata değil, zararsız bir "ahead" (ileride) durumudur. |
| `version_name` | İnsan tarafından okunabilir sürüm dizesi (örneğin `v106`). |
| `built` | ISO 8601 yapı zaman damgası. Yeniden üretilebilirlik için `SOURCE_DATE_EPOCH`'a uyar. |
| `engine_min` | Bu manifestoyu uygulamak için gereken minimum motor sürümü. |
| `channel` | Yayın kanalı (örneğin `stable`). |
| `key_id` | Cihaz keyring'indeki hangi anahtarın bu manifestoyu imzaladığı. Doğrulama için açık anahtarı seçer. |
| `files[]` | **Tüm** hedef ağaç (bir fark değil). Her girdi: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Önceki yayında bulunan ancak şimdi gitmiş olan yollar, cihazın kaldırması için. |
| `sig` | ed25519 imzası, base64. Aşağıdaki kanonikleştirmeye bakın. |

`files[]`, bir delta değil, **tüm** ağacı açıklar. Cihaz, manifestoyu zaten sahip olduğuyla karşılaştırarak deltayı kendisi hesaplar ve yalnızca `sha256`'sı eksik olan blob'ları alır. `sha256` her zaman orijinal (sıkıştırılmamış) içeriğe aittir; `enc` yalnızca o blob'un `blobs/`'ta nasıl depolandığını söyler. `class`'ın anlamı ve cihazın her değerle ne yaptığı [[Reboot Handling]]'de ele alınır.

---

## Kanonikleştirme (imzalı baytlar)

Bu, biçimdeki en önemli tek değişmezdir (invariant). PC imzalayıcısı ve cihaz üstü doğrulayıcı tamamen farklı çalışma zamanlarında çalışır (PC'de openssl, cihazda toybox + küçük gömülü bir doğrulayıcı ve cihazda **hiç JSON kütüphanesi yok**). Yine de imzalamak ve doğrulamak için tam olarak aynı baytları türetmelidirler. Bu nedenle kural, bir JSON yeniden serileştirmesi değil, kasıtlı bir **bayt dönüşümüdür**.

**Adım 1: sabit bir depolama biçimi.** `vdlu-pack`, `manifest.json`'u sıkıştırılmış, anahtarlar sıralı, UTF-8, her zaman `key_id` ve `sig`'i içererek (imzalanana kadar boş dizeler olarak) yazar:

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Adım 2: yalnızca `sig`'i sıyır.** Kanonik biçim, **yalnızca `"sig"` alanı kaldırılmış** o tam metindir. Anahtarlar sıralı olduğundan, `sig` her zaman `,"sig":"<value>",` olarak görünür, öncesinde `"schema"` ve sonrasında `"version"` ile çevrelenmiş (her ikisi de her zaman mevcut), bu yüzden onu kaldırmak iyi biçimlendirilmiş metin bırakır. JSON, bir dize değeri içindeki her `"`'yi `\"` olarak kaçışlar (escape), bu yüzden yapısal belirteç `"sig":"`, tam anlamıyla `"sig":"` içeren bir dosya adına karşı bile belirsiz değildir.

Kaldırma, imzalayıcıda ve doğrulayıcıda aynı olan, `sed` ve `jq` olmadan birkaç POSIX parametre genişletmesidir:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Adım 3: bunun hash'ini imzala.** İmzalanan/doğrulanan mesaj, kanonik biçimin **sha256 hex**'idir (64 ASCII karakter, yeni satır yok). ed25519 o hex'i imzalar.

Yapı gereği bundan iki sonuç çıkar:

- `key_id` kanonik biçimin parçasıdır (yalnızca `sig` sıyrılır). `vdlu-sign`, `key_id`'yi hashlemeden **önce** ayarlar, böylece anahtar kimliği imza tarafından kapsanır.
- `sig` yer tutucusu ister boş (`"sig":""`, imza zamanında) ister dolu (doğrulama zamanında) olsun, onu sıyırmak aynı kanonik baytları verir. İmzalama ve doğrulama otomatik olarak anlaşır.

İki POSIX sh aracı yetkilidir (authoritative). Bir Python eşdeğeri, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` ardından sha256, yalnızca onları çapraz kontrol etmek için vardır.

Bütün bunların etrafındaki güven mantığı (doğrulamanın neden cihaz üstü olduğu, `hardened`'in hata durumunda nasıl kapandığı) [[Security and Trust Model]]'de yaşar.

---

## baseline.json (kurulum tohumu)

Bir modül yeni kurulduğunda, kendi gönderilen sürümü için zaten "güncel" olmalı, az önce kurduğu sürümün gereksiz bir kendini güncellemesi olmadan. `baseline.json`'un yaptığı budur.

`baseline.json`, feed'de değil, **modül zip'inin içinde** (`vdlu/baseline.json`'da) gönderilir. Yeni bir kurulumda, motor "etkin sürüm" kaydını ondan tohumlar, böylece cihaz güncel doğar, `from:0` olmadan ve zaten sahip olduğunun yeniden alınması olmadan.

Temel özellikler:

- Gönderilen sürüm için **imzalı manifestonun anahtarsız bir kopyasıdır**: aynı `vdlu-pack` çıktısı, imzasız bırakılmış (`key_id` ve `sig` boş kalır).
- **Doğrulanmaz.** Motor onu yerel bir güvenilir tohum olarak ele alır çünkü kurulum güven sınırı olan flash edilen zip'in içinde geldi. Yalnızca *feed'den alınan* bir manifesto imza doğrulamasından geçer.
- İmza gerektirmediği için, **CI onu anahtarsız oluşturabilir**, bu da imzalama anahtarını tamamen CI'nın dışında tutan şeydir (bkz. [[Producer]]).
- `vdlu-pack`, **`baseline.json`'u kendi manifestosundan hariç tutar**, böylece manifesto asla temel çizgiye referans vermez (bu bir kendine referans döngüsü olurdu: manifesto'dan temel çizgiye'den manifesto'ya).
- **Yoksa ölümcül değildir.** Onsuz, cihaz ilk güncellemesinde basitçe `from:0`'dan başlar ve ihtiyacı olanı alır. Asla bozuk değil, sadece daha az optimal.

---

## Blob'lar

Her farklı dosya içeriği, **orijinal içeriğin sha256'sı** ile adlandırılan `blobs/` altında bir blob'dur:

- Ham bir blob için `blobs/<sha256>`.
- Gzip'lenmiş bir blob için `blobs/<sha256>.gz` (gzip yalnızca dosya en az 4096 bayt olduğunda ve sıkıştırma en az yüzde 10 tasarruf sağladığında tutulur).

Bir blob bir kez, tek bir biçimde depolanır. İçerik adresleme tekilleştirmeyi bedava verir: değişmemiş, paylaşılan veya geri alınmış içerik zaten var olan bir blob'a eşlenir, böylece feed yalnızca gerçekten yeni içerikle büyür ve cihaz yalnızca eksik olduğu hash'leri indirir. Cihaz, kullanmadan önce (bir `gz` blob'u açtıktan sonra) indirilen her blob'un `sha256`'sını manifesto ile kontrol eder.

---

## Feed'den neyin hariç tutulduğu ve neden

Feed **yalnızca modülün kendi içeriğini** taşır. Sabit bir yol kümesi kasıtlı olarak dışarıda tutulur. `vdlu-pack`, hem ağacı dolaşırken hem de `delete[]`'i hesaplarken bir hariç tutma yüklemi (predicate) uygular.

| Hariç tutulan | Neden |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (güven kökü: ham açık anahtarlar + doğrulayıcı ikilisi) | **Bu temel güvenlik nedenidir.** Güven çıpası (trust anchor) **yalnızca-flash**'tır. Keyring veya doğrulayıcı feed ile teslim edilebilir olsaydı, bir manifesto onu doğrulayan şeyin ta kendisinin üzerine yazabilirdi. Onları hattan uzak tutmak, bir manifestonun cihaz üstü güven çıpasını asla yeniden yazamayacağı anlamına gelir. |
| `vdlu/baseline.json` | İmzalı manifestonun bir kopyasıdır (kurulum tohumu); onu paketlemek bir kendine referans döngüsü olurdu. |
| `.vd/` flash altyapısı | Zip'te gönderilen, asla canlı uygulanmayan flash-kapısı iskelesi. |
| `update.json`, `update-mmrl.json` | Boyutları/sha'ları CI tarafından zip'ler oluşturulduktan *sonra* doldurulur, bu yüzden gönderilen kopya herhangi bir feed kopyasından farklıdır. Onları beslemek, her kurulumun ilk kendini güncellemesinde hayalet (phantom) bir tek dosya alışına neden olur ve zaten cihaz üstünde köreltidirler (yönetici uzaktaki ham güncelleme JSON'unu okur). |
| `META-INF/`, `customize.sh` (kurulum iskelesi) | Yönetici tarafından **flash** zamanında tüketilir ve kurulu modülde tutulmaz. Bunlar VDLU içeriği değildir; onları sunmak blob israf eder ve biri sürümler arasında değişirse, canlı modül dizinine bir kurulum dosyası olarak yazılır. |
| Dosya başına `.sha256` yoldaşları | Yalnızca flash edilebilir zip'e aittirler, artımlı bir güncellemeden sonra bayatlarlar ve manifestoyu ikiye katlarlar. |
| Geliştirme/doküman dosyaları (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Asla cihaza gönderilmez; onları sunmak blob israf eder ve her doküman düzenlemesinde imzalı manifestoyu çalkalar. |

Güven kökü hariç tutmasının arkasındaki mantık [[Security and Trust Model]]'de genişletilmiştir.

---

## delete[] semantiği

`delete[]`, cihaza hangi yolları kaldıracağını söyler, böylece yayınlar arasında düşürülen bir dosya cihaz üzerinde bir yetim olarak oyalanmaz. `--prev <previous manifest.json>`'u `vdlu-pack`'e geçerek hesaplanır: önceki yayında olan ve mevcut olmayan bir yol bir silme girdisi olur.

Önemli kural: **hariç tutulan yollar `--prev` ile bile asla silme olarak yayılmaz.** Her önceki yol, ağacı dolaşırken kullanılan aynı hariç tutma yükleminden geçirilir. Bir `--prev`, hâlâ şimdi hariç tutulan yolları listeleyen daha eski bir manifestoya işaret ederse (başıboş bir `baseline.json`, `META-INF/*`, bir keyring girdisi vb.), bu yollar silme girdilerine **dönüştürülmez**. Hariç tutulan bir yol asla feed içeriği olmadı, bu yüzden VDLU'nun silmesi gereken bir şey değil ve cihaza asla feed aracılığıyla sunulmayan bir dosyayı kaldırması emredilmez. Bu, hariç tutma listesinin asla yıkıcı bir talimat olarak geri dönmesini engelleyen şeydir.
