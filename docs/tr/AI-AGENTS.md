> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · Türkçe · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# VDLU'yu bir yapay zeka ajanından sürme

VDLiveUpdate (VDLU), KSU/Magisk modüllerinin `vdlu/` içine gömdüğü flashsız, artımlı güncelleyicidir. Tüm motor kabuktan sürülür, böylece bir yapay zeka asistanı veya ajanı bir güncellemeyi başsız olarak denetleyebilir, uygulayabilir, sürdürebilir ve tamamlayabilir, WebUI'nin çalıştırdığı döngünün aynısı, UI olmadan ve döngüde insan olmadan. Yazdırdığı JSON'u ayrıştır, asla metin kazıma yapma.

## Sözleşme

Cihazda root olarak çalıştırılan tek bir giriş noktası, motorun üç ortam değişkeni ayarlanmış halde:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR`, Tier-2 durum dizinidir (modülün dışında, bir reflash'ı atlatır), `MODULE_DIR` modülün canlı ağacıdır, `MODID` modül kimliğidir.
- `rc 0` = tamam, `rc != 0` = hata, nedeni stderr'de.
- Okuma fiilleri (`check`, `status`) stdout'a **bir JSON nesnesi** yazdırır. Onu ayrıştır, asla metin kazıma yapma.
- Motor yalnızca toybox'a (`sha256sum`/`gzip`/`base64`) artı gömülü bir `ed25519-mini`'ye artı ilk https güncellemesinde indirilen statik bir `curl`'e bağlıdır, sıfır `jq`.

Geliştirme sırasında aynı betik bu depoda `engine/update.sh` konumunda bulunur, bu yüzden üç değişken ayarlıyken `sh engine/update.sh <verb>` bir hazırlık kopyasını aynı şekilde sürer.

## Fiiller

| Fiil | Yapar | Yazdırır |
|------|------|--------|
| `check` | akışa karşı salt okunur DIFF, hiçbir şeyi değiştirmez | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, veya cihaz akışın ilerisinde olduğunda `{"update":false,"ahead":true,"from":N,"to":M}` (sürüm düşürme engellendi, zararsız, rc 0) |
| `run` | tam LIVE döngüsü DIFF -> FETCH -> APPLY -> COMMIT, LIVE dosyalarını uygular ve REBOOT-hard olanları sahneler, `cancel`'a uyar | `journal.json` içinde ilerleme |
| `resume` | bekleyen işlemi mevcut fazından sürdürür, idempotent, asla `.so`'yu değiştirmez | güncellenmiş `journal.json` |
| `boot` | pre-zygote modu, `resume` artı sahnelenmiş `.so`'nun değişimi, `PENDING_REBOOT`'u `DONE`'a kapatır | güncellenmiş `journal.json` |
| `status` | salt okunur anlık görüntü, hiçbir şeyi değiştirmez | `journal.json`, veya hiçbir işlem etkin değilken `{"state":"idle"}` |
| `cancel` | bir durdurma ister, sürmekte olan bir `run` bir sonraki güvenli noktada durur | `$VDLU_DIR/cancel` oluşturur |

Başsız bir güncelleme, bekleyen bir şey olup olmadığını görmek için `check`, canlıya gidebilecek her şeyi uygulamak için `run`, ardından sahnelenmiş her `.so`'yu değiştirmek için sonraki önyüklemede `boot`'tur (veya ertelenmiş bir fetch'i yeniden denemek için `resume`). Her fiili yeniden çağırmak güvenlidir, döngü ortasında bir çökme veya düşen ağ, sürdürülebilir bir günlük bırakır, asla yarı uygulanmış bir modül değil.

## Durum JSON'u

`status` (ve `$VDLU_DIR/journal.json`'daki canlı dosya), WebUI ile bir ajanın her ikisinin de okuduğu ilerleme sözleşmesidir:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` sabit bir sırada ilerler: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE`'a yalnızca her şeyin yeniden karması eşleştikten sonra ulaşılır. Sahnelenmiş bir REBOOT-hard dosyası `PENDING_REBOOT` verir, asla sahte bir `DONE` değil, bitirmek için `boot` çalıştır.
- `DEFERRED`, `net_policy`'nin indirmeyi engellediği anlamına gelir, zararsız ve sürdürülebilir bir durum, hata değil, plan kalıcıdır ve sonraki `check`/`boot` devam eder.
- `ERROR`, nedeni `error`'da taşır, uygulanan LIVE dosyaları `rollback/`'ten geri alınır, modül asla yarı uygulanmış bırakılmaz.
- `error:null` ile `cancelled:true` temiz bir durmadır, günlük sürdürülebilir kalır.

## Dikiş sözleşmesi

Her bileşen (motor, üretici, WebUI) yakınsama yasası olan [`INTERFACES.md`](INTERFACES.md)'ye uyar. CLI fiilleri, `manifest.json` şeması, `journal.json` anahtarları ve orada tanımlı config anahtarları **değişmezdir**, o dosyayı tek doğruluk kaynağı olarak gör ve bunlardan birini değiştirmeden önce ona hizala. Motor içleri için (sürdürülebilir işlem, titizlik güvenceleri, trust-anchor dışlaması) bkz. [`ENGINE.md`](ENGINE.md), akış tarafı için (içerik adresli akışı oluşturup imzalamak) bkz. [`PRODUCER.md`](PRODUCER.md).

## Bir ajan için kurallar

- Fiilleri ve JSON'u kullan, asla WebUI'yi kazıma ve durum dosyalarını asla elle düzenleme.
- `INTERFACES.md`'yi değişmez say, bir değişiklik önce sözleşmeyi hizalamak demektir.
- Bir yapay zeka ajanından gelen bir yama, diğer her yama ile aynı inceleme çıtasını geçer, build her zaman release, hiçbir şeyi gevşetme, hiçbir şeyi kaybetme.

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
