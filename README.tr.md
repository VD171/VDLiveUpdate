<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU**, **KernelSU / APatch / Magisk** modülleri için flashsız, artımlı bir kendi kendini güncelleme motorudur. Kurulu bir modül, **yalnızca değişen dosyaları** (içerik adresli bloblar + imzalı bir manifest) getirerek kendini günceller, canlı uygulanabilenleri **yeniden başlatma olmadan** uygular ve gerçekten bir yeniden başlatma gerektiren birkaçını (bir `.so`, bir `/system` overlay'i, bir `sepolicy.rule`) hazırlar (stage) ve işaretler. Root yöneticisi yok, tüm `.zip`'i yeniden indirmek yok, o hazırlanan dosyalar dışında yeniden başlatma yok.

Kendi başına bir modül olarak çalıştırılmak için değil, bir modülün içine **vendor edilmek** üzere (yani `<module>/vdlu/` içine yerleştirilmek üzere) tasarlanmıştır.

## Neden

Normal bir modül güncellemesi tüm `.zip`'i yeniden gönderir. Büyük bir modül için bu, değişen birkaç satır uğruna büyük bir yeniden indirme demektir ve statik bir güncelleme manifest'i yalnızca tek bir `zipUrl`'e işaret edebildiğinden, cihazın gerçekte sahip olduğu flavor'ı (ABI, full vs lite) sunamaz. VDLU, **kurulu** ağacı imzalı bir akışa (feed) karşı diff'ler ve yalnızca delta'ları getirir; böylece bir arm64-full kurulumu arm64-full kalır, bir lite kurulumu lite kalır ve çoğu güncelleme canlı uygulanır.

## Nasıl çalışır

- **Üretici (PC / release):** `vdlu-pack` bir modül ağacını içerik adresli bir akışa dönüştürür (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc`, son N manifest'e referans yoluyla sahipsiz blobları budar (fail-safe, varsayılan olarak dry-run).
- **Motor (cihaz):** POSIX sh, `jq` yok. `update.sh` (`check | run | resume | boot | status | cancel`), DIFF -> FETCH -> APPLY -> COMMIT akışını **sürdürülebilir bir işlem** (journal) olarak çalıştırır; rollback ve bir `mkdir` kilidiyle. İmza, gömülü `ed25519-mini` tarafından doğrulanır (cihazda `openssl` yok).
- **WebUI:** yerleşik bir Updates paneli (ilerleme toast'u, iptal, yeniden başlatma banner'ı), vanilla JS.

## Profiller

- `trusted`: özel kullanım, `file://` veya SSH kaynağı, elinden gelenin en iyisi doğrulama (hash her zaman).
- `hardened`: genel kullanım, **imza zorunlu**, sürüm düşürme engellenir. Manifest **modül id'sine bağlıdır** ve herhangi bir şey indirilmeden önce her alan fail-closed doğrulanır.

## Kendi modülünde benimse

`engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini`'yi `<module>/vdlu/` içine vendor et, **ham 32 baytlık açık anahtarını** `vdlu/keyring/<id>.pub` olarak göm, bir `config` (profil + kaynak) ekle, tetikleyicileri bağla (açılışta otomatik güncelleme için pre-zygote `post-fs-data.sh`; WebUI açılışında bir tetikleyici) ve release'ine `vdlu-pack` + `vdlu-sign` ekle. İşlenmiş bir şablon için [`integration/`](integration/)'a bak.

## Güvenlik

- **Her manifest alanı düşmanca girdidir.** `validate_plan()`, mutlak ya da `..` içeren bir yol, 64 hex karakter olmayan bir `sha256` veya geçersiz bir mode / class / encoding durumunda, herhangi bir getirme ya da uygulama **öncesinde** tüm manifest'i fail-closed reddeder.
- **Özel imzalama anahtarı asla CI'ya veya bir cihaza dokunmaz**; yalnızca ham açık anahtar gömülür ve doğrulama `openssl` değil `ed25519-mini` kullanır.
- `hardened`, tersine çevirme yoluyla fail-closed'dur: birebir `trusted` dışındaki her şey `hardened` olarak değerlendirilir; böylece bozuk bir profil değeri, imzasız bir manifest'i asla sessizce kabul edemez.
- Yeniden başlatma sınıfı dosyalar (`.so`, `/system` overlay'i, `sepolicy.rule`) **hazırlanır, canlı bir inode'un üzerine asla yazılmaz**; geri kalan her şey canlı uygulanır. Başarısız bir uygulama, yedek olmadan üzerine yazmak yerine iptal eder.

## Derleme / test

Bunlar betik, derlenecek bir şey yok. Uçtan uca (üretici + motor birlikte):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js` ve `webui/demo.html`'yi bir tarayıcıda aç (cihaz köprüsünü mock'lar).

## Belgeler

- [`INTERFACES.md`](INTERFACES.md): bileşenler arasındaki ek yeri (seam) sözleşmesi (yakınsama yasası; değişmez olarak ele al).
- `integration/`: adım adım bir benimseme kılavuzu ve bağlama parçacıkları.

## Ayrıca bakınız

Aynı yazara ait kardeş projeler:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: tamamen bir WebUI'den yönetilen, root olarak tam uygulama ve veri yedekleme ve geri yükleme.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: taze bir fingerprint'i tutarlı, uyumlu bir profile dönüştüren bir cihaz spoofer'ı.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: KernelSU/APatch/Magisk için bağımsız, yapılandırılabilir root'lu bir SSH daemon'ı.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: her öğeyi, onu okuyabilen her yöntem üzerinden okuyan bir cihaz yöntemi hata ayıklayıcısı.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: Google'ın cihazında neyi kaydettiğini okur, tamamen cihaz üzerinde ve internet olmadan.

## İletişim

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Lisans

VDLiveUpdate'in kendi kodu **Apache-2.0**'dır; bkz. [LICENSE](LICENSE). Getirme bootstrap'i için küçük bir `ed25519-mini` doğrulayıcısı ile statik bir `curl` vendor eder; her biri kendi lisansı altındadır; bkz.
[NOTICE.md](NOTICE.md) ve paketlenmiş binary'lerin yanındaki `PROVENANCE.json` dosyaları.

## Ticari markalar

VDLiveUpdate bağımsız, resmi olmayan bir projedir; herhangi bir üçüncü tarafla bağlantılı veya onun tarafından onaylanmış değildir.
"Android", Google LLC'nin ticari markasıdır; "KernelSU", "Magisk" ve "APatch" ilgili
yazarlarının markalarıdır. VDLU tamamen senin cihazında ve kendi release sunucunda çalışır.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
