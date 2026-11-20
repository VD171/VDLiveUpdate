# VDLiveUpdate (VDLU)

**VDLU, KernelSU / APatch / Magisk modülleri için flash gerektirmeyen, artımlı (incremental) bir kendini guncelleme motorudur: kurulu bir modül, kendi dosyalarını imzalı bir feed uzerinden gunceller, yalnizca degisen kismi indirir ve bunun cogunu yeniden baslatma olmadan uygular.**

Normal bir modül güncellemesi tüm `.zip` dosyasını yeniden gönderir, yani birkaç değişen satır tam bir yeniden indirmeye mal olur ve statik bir güncelleme manifestosu yalnızca tek bir `zipUrl` gösterebilir (her cihaz için tek bir çeşit). VDLU farklı bir yol izler: gerçekten kurulu olan ağacı imzalı, içerik adresli bir feed ile karşılaştırır (diff), yalnızca farkları (delta) indirir ve bunları yerinde yazar. Bir arm64 tam kurulum arm64 tam kalır, bir lite kurulum lite kalır ve modül asla yeniden flash edilmez.

VDLU bir modüle **gömülmek (vendored)** için tasarlanmıştır, `<module>/vdlu/` içine yerleştirilir. Kendi başına bir modül değildir.

## Hedefler

- **Flash gerektirmeyen kendini güncelleme.** Kurulu bir modülü yerinde, havadan, kök (root) yöneticisi olmadan, `.zip`'i yeniden flash etmeden ve kurulu çeşidi kaybetmeden güncelle.
- **İçeriğe göre artımlı.** Yalnızca içeriği değişen blob'ları aktar. İçerik adresli bir feed (`manifest.json` + `blobs/<sha256>`), değişmemiş veya geri alınmış dosyaların asla yeniden alınmaması anlamına gelir.
- **Güvenli olduğunda yeniden başlatmasız.** Sıradan dosyaları canlı olarak hemen uygula. Yalnızca gerçekten yeniden başlatmaya ihtiyaç duyan birkaç dosya için aşamalı (staged) bir yeniden başlatmayı sakla (bir `.so`, bir `/system` katmanı, bir `sepolicy.rule`).
- **Cihazda ince.** Saf POSIX `sh`, cihazda `jq` yok, `bash` yok, `openssl` yok. Doğrulama gömülü bir `ed25519-mini` üzerine kuruludur; alınan tek ikili dosya statik bir `curl`'dür, yalnızca `https` feed'leri için kullanılır.
- **Hata durumunda kapalı (fail-closed) ve dürüst.** Her manifesto alanı düşmanca girdi olarak ele alınır ve herhangi bir şey indirilmeden önce doğrulanır. Bir yeniden hash kanıtlamadıkça hiçbir şey asla "bitti" olarak bildirilmez ve önce bir yedek alınmadan hiçbir şey üzerine yazılmaz.

## Kendine Özgü Nitelikler

VDLU'yu tipik bir OTA istemcisinden ayıran şeyler:

- **Flash gerektirmeyen ve artımlı.** Tekilleştirme (dedup) ile içerik adresli diff / fetch / apply: cihaz, imzalı feed'e karşı farkı hesaplar ve yalnızca eksik blob'ları çeker.
- **Mümkün olduğunda yeniden başlatmasız.** Sıradan dosyalar canlı uygulanır; yalnızca `.so`, `/system` katmanları ve `sepolicy.rule` dosyaları aşamalanır ve tek bir yeniden başlatmada değiştirilir. Bkz. [[Reboot Handling]].
- **Cihazda POSIX `sh`.** toybox / busybox / mksh altında çalışır. `jq` yok (`gron` tarzı bir `awk` düzleştirici JSON'u ayrıştırır), `bash`'e özgü yapılar yok, ağır bir çalışma zamanı yok.
- **İnce doğrulama.** Gömülü bir `ed25519-mini` imzaları doğrular. Cihazda **`openssl` yok**; özel anahtar asla bir cihaza veya CI'ya dokunmaz.
- **Hata durumunda kapalı güvenlik.** `validate_plan()`, herhangi bir hatalı alanda (mutlak veya `..` yolu, 64 hex karakter olmayan bir `sha256`, geçersiz bir mod / sınıf / kodlama) manifestonun **tamamını** reddeder. İki profil vardır, `trusted` ve `hardened`; `hardened`, tersine çevirme (inversion) yoluyla hata durumunda kapalıdır. Bkz. [[Security and Trust Model]].
- **Devam ettirilebilir ve atomik.** Bir günlük (journal) her işlemi çökmeye karşı güvenli kılar; yazmalar `rename` / `mv` kullanır; herhangi bir üzerine yazmadan önce bir yedek alınır, böylece başarısız bir uygulama modülü bozmak yerine geri alınır.

## Buradan başlayın

| Şunu istiyorsanız... | Gidin |
|---|---|
| VDLU'yu modülünüze adım adım benimsemek | [[Quick Start]] |
| Tüm sistemi bir bakışta anlamak | [[Architecture]] |
| Cihaz tarafı motoru (`update.sh`) öğrenmek | [[Engine]] |
| PC'nizde bir feed oluşturup imzalamak | [[Producer]] |
| Updates panelini eklemek | [[WebUI]] |
| Güven modelini ve tehdit duruşunu okumak | [[Security and Trust Model]] |
| Manifesto ve blob düzenini görmek | [[Feed Format]] |
| Neyin yeniden başlattığını ve nedenini bilmek | [[Reboot Handling]] |
| Yaygın bir soru sormak | [[FAQ]] |
| Katkıda bulunmak | [[Contributing]] |

## Proje bağlantıları

- **Kaynak:** https://github.com/VD171/VDLiveUpdate
- **Kanal (güncellemeler):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate bağımsız, resmi olmayan bir projedir. "Android", Google LLC'nin ticari markasıdır; "KernelSU", "Magisk" ve "APatch", ilgili yazarlarının markalarıdır. VDLU tamamen kendi cihazınızda ve kendi yayın (release) sunucunuzda çalışır.
