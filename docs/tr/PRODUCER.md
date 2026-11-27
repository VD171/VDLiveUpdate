> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · Türkçe · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU üretici + imzalama katmanı

Bir modül için içerik-adresli teslimatı (manifest + blob'lar) oluşturur ve onu imzalar.
[`INTERFACES.md`](INTERFACES.md) §3/§6/§7'ye uyar.

| araç | çalıştığı yer | dil | iş |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | nihai modül ağacını dolaş -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 anahtar çifti (`<id>.pem` priv, `<id>.pub` PEM, ince keyring için `<id>.pub.raw` RAW 32B) |
| `producer/vdlu-sign` | PC | sh + openssl | bir manifeste yerinde `key_id` + `sig` enjekte et |
| `engine/vdlu-verify` | **cihaz** | sh + ed25519-mini | `sig`'i gömülü ed25519-mini aracılığıyla doğrula; keyring = RAW 32B pubkey (cihazda openssl YOK) |

## Boru hattı

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` içerik-adreslidir ve yinelenenleri ayıklar: `<sha256>`'sı zaten var olan bir blob yeniden
yazılmaz, böylece yayınlama artımlıdır ve değişmemiş / geri alınmış içerik asla yeniden itilmez.

### `enc` kararı (vdlu-pack)

`sha256` **her zaman** orijinal (sıkıştırılmamış) içeriğindir, `enc` yalnızca blob'un nasıl depolandığını adlandırır.

- `gz`, `size >= 4096` **ve** gzip (`-9 -n`, deterministik) en az %10 tasarruf ettiğinde (`comp <= raw*0.90`).
- aksi halde `raw` (HTTP gzip'in zaten kapsadığı küçük metin, ya da zaten sıkıştırılamaz veri).
- derleme ana makinesinde gzip eksikse -> her şey `raw` (asla başarısız olmaz).

Bir blob tek bir formatta, bir kez depolanır: `blobs/<sha256>` (raw) ya da `blobs/<sha256>.gz` (gz). Cihaz
toybox `gunzip` ile açar (her zaman mevcuttur), bu yüzden hiç zstd paketlenmez.

### `class` kararı (vdlu-pack) - reboot taksonomisi

Yoldan türetilir (INTERFACES §3, doc §4). Yalnızca varsayılanlar, bir yol kuralı asla `reboot`->`live` düşürmesi yapmaz.

| class | neyle eşleşir | uygulanışı |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | sahnelenmiş `.vdlu-new`, boot'ta swap |
| `soft` | kök `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | canlı yazılır, sonraki boot'ta çalışır |
| `live` | diğer her şey (webroot, bin, lib, confs, module.prop, ...) | canlı yazılır, atomik |

Sembolik bağlantılar **izlenmez** (ağacın dışından içerik asla sızdırmaz, ör. `/etc/shadow`'a bir bağlantı) ve
bir uyarıyla atlanır, çünkü manifest şemasında sembolik bağlantı türü yoktur. Düzenli olmayan dosyalar (dizinler, fifo'lar,
aygıtlar) atlanır. `built`, yeniden üretilebilir manifestler için `SOURCE_DATE_EPOCH`'u dikkate alır.

### Baseline (kurulum tohumu) - imzasız, anahtarsız

`baseline.json` (modül zip'inde `vdlu/baseline.json`'da gönderilir), yeni bir kurulumda `current.json`'u tohumlar
ki cihaz "güncel" doğsun (from:0 yok, yeniden getirme yok). Motor onu bir **yerel güvenilir tohum** olarak ele alır
(flaşlanan zip içinde geldi, ki o da kurulum güven sınırıdır) ve **imzasını doğrulaMAZ** -
yalnızca beslemeden GETİRİLEN manifest `vdlu-verify`'dan geçer. Yani baseline'ın **anahtara ihtiyacı yoktur**: o
sadece gönderilen ağaç üzerinde `vdlu-pack` çıktısıdır (imzasız, `sig`/`key_id` boş kalır). Bir CI bu nedenle
onu **anahtarsız** üretebilir, imzalama anahtarını CI'dan %100 uzak tutar - yalnızca yayınlanan BESLEME imzalanır (operatör,
yerel olarak). `vdlu-pack`, `baseline.json`'u kendi manifestinden hariç tutar (kendine-referans önleme). Yoksa ölümcül değildir:
cihaz ilk güncellemede sadece from:0'dan başlar, asla bozulmaz.

## Kanonikleştirme (yakınsama noktası)

`vdlu-sign` ve `engine/vdlu-verify` bir manifestten **aynı baytları** türetmelidir, iki
farklı çalışma zamanında (PC openssl vs cihaz toybox). Kural bilinçli olarak bir bayt
dönüşümüdür, bir JSON yeniden-serileştirmesi değil, böylece cihazda bir JSON kütüphanesine ihtiyaç duymaz:

1. `vdlu-pack`, `manifest.json`'u **kompakt, anahtarlar sıralı, UTF-8** yazar
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), her zaman
   `key_id` ve `sig` alanlarını içererek (imzalanana kadar boş dize yer tutucuları). Bu kanonik
   depolama formudur.
2. **Kanonik form = `"sig"` alanı kaldırılmış o metin.** Anahtarlar sıralı olduğundan, `sig`
   her zaman `,"sig":"<value>",` olarak `"schema"` (öncesinde) ve `"version"` (sonrasında) ile köşelenmiş görünür,
   her ikisi de her zaman mevcuttur. Onu kaldırmak iyi biçimlendirilmiş `...,"schema":N,"version":...` bırakır.
   JSON, dize değerleri içindeki her `"`'yi `\"`'ye kaçışlar, bu yüzden yapısal token `"sig":"`,
   kelimenin tam anlamıyla `"sig":"` içeren bir dosya adına karşı bile belirsizlik taşımaz (test edildi).
3. İmzalanan/doğrulanan mesaj, kanonik formun **sha256 hex**'idir (64 ASCII karakter, yeni satır yok).
   O hex üzerinde ed25519 (`openssl pkeyutl -sign/-verify -rawin`).

POSIX sh'de kaldırma (her iki araçta da aynı işlev, `sed`/`jq` yok):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id`, kanonik formun bir parçasıdır (yalnızca `sig` soyulur), `vdlu-sign`, `key_id`'yi hash'lemeden **önce** ayarlar.
Değer yer tutucusunun boş (`"sig":""`, imza zamanı) ya da dolu (doğrulama zamanı) olması aynı kanonik baytları verir,
böylece imza ve doğrulama inşa gereği uyuşur.

Python onu `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` sonra sha256 olarak yeniden üretir - yalnızca
çapraz kontrol için kullanılır, yetkili üreticiler iki sh aracıdır.

## İmza (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  imzalama/openssl için) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER, 12-baytlık bir önek + 32-baytlık anahtardır, bu yüzden `tail -c 32` anahtarın TA KENDİSİDİR). İKİSİNİ de yayar.
- `vdlu-sign` (PC): kanonik sha256 hex üzerinde `openssl pkeyutl -sign -rawin`, imza base64 olarak depolanır.
- `vdlu-verify` (**cihaz, ince**): `ed25519-mini <pubkey32> <msg> <sig64>` - keyring'i **RAW 32B**
  pubkey olarak okur, cihazda openssl YOK. `key_id` yol-temizlenir (`/`, `.`, `..`, `"` yok). 🚨 Keyring
  **`.pub.raw`'u (32B)** gönderir, asla `.pub` PEM'ini (113B) değil: PEM yalnızca PC tarafıdır ve `ed25519-mini` onu okuyamaz.

Güven modeli (INTERFACES §6, doc §11/§13): `profile=hardened` (public) verify'ı zorunlu kılar - başarısız
ya da eksik bir imza güncellemeyi iptal eder. `profile=trusted` (private, SSH-sahnelenmiş kaynak) verify'ı
en iyi çaba olarak ele alır, ama her blob'un sha256'sı yine de kontrol edilir.

## Keyring + rotasyon

Keyring, `<key_id>.pub` dosyalarından oluşan bir dizindir, her biri **RAW 32B** ed25519 pubkey'dir (`keygen`'in
`.pub.raw`'undan), PEM DEĞİL - `ed25519-mini` ham 32 bayt okur. Hem mevcut **hem de** önceki ham pubkey'i gönderin
(doc §13) ki rotasyona uğramış bir anahtar eski kurulumları bozmasın. Yeni `key_id` ile `vdlu-sign` ve cihazın
`<keyring>/<key_id>.pub`'u (ham) seçmesi tüm rotasyon mekanizmasıdır - motor değişikliği yok. Keyring,
sürümler boyunca **kararlıdır** (yalnızca anahtar rotasyonu onu değiştirir): bir yeniden-vendor onu **kopyalamadan-doğrulamalı** ve asla
onu PC tarafı `.pub` PEM ile üzerine yazmamalıdır.

**Çok anahtarlı keyring'ler modül anahtarını sabitlemek ZORUNDADIR.** Engine, bir MODULE-UPDATE'i hangi `key_id`'nin imzalayabileceğini config'in `key_id` allowlist'iyle (INTERFACES §5/§6) sınırlar, bu, pubkey seçilmeden önce fail-closed kontrol edilir. Tek anahtarlı bir keyring varsayılan-güvenlidir (o tek anahtar kabul edilir). Ama keyring'i daha düşük güvenli bir anahtarı DA taşıyan bir modül - ör. release anahtarının yanında bir fingerprint-feed anahtarı - `config`'i modül anahtarını bildirene kadar reddedilir, ör. `key_id=vd-2026` (rotasyon için virgülle ayrılmış, ör. `key_id=vd-2026,vd-2027`). Bu, sızmış daha düşük güvenli bir anahtarın bir flashless root güncellemesi imzalamasını engeller.

`vdlu-pack` **keyring'i ve `verify/` ikililerini beslemeden hariç tutar** (güven kökü yalnızca flaştadır, asla ağ üzerinden sunulmaz), `baseline.json`, yükleyici iskelesi (`META-INF/`, `customize.sh`), `.vd/` flaş geçidi, CI'ın doldurduğu `update.json`/`update-mmrl.json` ve dosya başına `.sha256` eşlikçileriyle birlikte. Yalnızca modülün kendi içeriği besleme ile güncellenebilir, bu yüzden bir manifest cihazdaki güven çıpasını asla yeniden yazamaz.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
