> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · Türkçe · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Güvenlik Politikası

VDLiveUpdate (VDLU), çalışan bir modüle flashless root güncellemeleri uygular: modülün
kendi dizinine yazar ve açılışta bir Zygisk `.so` dosyasını değiştirir, modülün root
bağlamında çalışır. Güvenliği ciddiye alıyoruz.

## Bir güvenlik açığını bildirme

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Açık bir açıklama ekleyin ve mümkünse sorunu yeniden üreten bir manifest veya feed
ekleyin. En kısa sürede yanıt vereceğiz ve isterseniz size teşekkür edeceğiz.

## Kapsam notları

- Güncellemeler, content-addressed bloblar artı ed25519 ile imzalanmış bir `manifest.json`
  dosyasıdır. Cihaz, imzayı gömülü bir `ed25519-mini` ile doğrular (cihazda openssl yoktur)
  ve her blob, kullanılmadan önce kendi `sha256` değerine göre denetlenir.
- hardened profil (herkese açık varsayılan) geçerli bir imza gerektirir ve downgrade
  işlemini engeller. "Başlangıç" sürümü, kurulu modülün `versionCode` değeriyle
  (`module.prop` dosyasından okunur) alttan sınırlanır, böylece bir modül asla feed'in
  gerisine döndürülmez.
- Güven kökü (`keyring/` içindeki ham ed25519 açık anahtarı ve `verify/` içindeki ikili
  dosyalar) yalnızca-flash'tır ve asla ağ üzerinden döndürülmez. Üretici bunu feed'den
  hariç tutar ve engine, indirilen bir plandaki her `vdlu/` yolunu yok sayar, böylece
  sızdırılmış bir imzalama anahtarı doğrulayıcıyı veya anahtarı değiştirip root'u kalıcı
  hale getiremez.
- Başka bir modül için geçerli şekilde imzalanmış bir manifest, farklı bir modülün dizinine
  yazamaz. İmzalanan `module` alanı, cihazdaki `MODID` ile eşit olmalıdır (modüller arası
  bağlama denetimi) ve her yazma ve silme işlemi modül dizinine sınırlı kalır.
- Engine, modülün kendi root bağlamında çalışır ve onu asla zayıflatmaz. Hiçbir ayrıcalık
  eklemez ve hiçbir manifest alanını bir kabuğa enterpolasyon yapmaz, her `path`, `sha256`,
  `mode` ve `delete[]` değeri kullanılmadan önce düşmanca girdi olarak doğrulanır.
- Duruş fail-closed'dur. Bozuk veya bilinmeyen bir `profile` değeri, imzasız içeriği kabul
  etmeye asla geçmez (tam olarak `trusted` olmayan her şey `hardened` olarak değerlendirilir)
  ve herhangi bir dosya üzerine yazılmadan önce bir yedek yazılır, böylece başarısız bir
  apply kurulu sürümü asla yok etmez.
- Tam güven modeli, fail-closed garantileri ve hardening ayrıntıları için bkz.
  [TRUST-MODEL.md](TRUST-MODEL.md).

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
