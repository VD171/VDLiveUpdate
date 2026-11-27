> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · Tiếng Việt · [中文](../zh/AI-AGENTS.md)

---

# Điều khiển VDLU từ một tác nhân AI

VDLiveUpdate (VDLU) là trình cập nhật tăng dần, không cần flash mà các mô-đun KSU/Magisk nhúng trong `vdlu/`. Toàn bộ engine được điều khiển từ shell, nên một trợ lý hoặc tác nhân AI có thể kiểm tra, áp dụng, tiếp tục và hoàn tất một bản cập nhật không giao diện, cùng chu trình mà WebUI chạy, không UI và không con người trong vòng lặp. Phân tích JSON mà nó in ra, đừng bao giờ bóc tách văn bản.

## Hợp đồng

Một điểm vào duy nhất, chạy với quyền root trên thiết bị, với ba biến môi trường của engine được đặt:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` là thư mục trạng thái Tier-2 (ngoài mô-đun, sống sót qua một lần reflash), `MODULE_DIR` là cây mô-đun đang sống, `MODID` là id mô-đun.
- `rc 0` = ok, `rc != 0` = lỗi, với lý do trên stderr.
- Các động từ đọc (`check`, `status`) in ra **một đối tượng JSON** trên stdout. Phân tích nó, đừng bao giờ bóc tách văn bản.
- Engine chỉ phụ thuộc vào toybox (`sha256sum`/`gzip`/`base64`) cộng một `ed25519-mini` nhúng cộng một `curl` tĩnh được tải ở lần cập nhật https đầu tiên, không `jq`.

Trong quá trình phát triển cùng kịch bản đó nằm ở `engine/update.sh` trong kho này, nên `sh engine/update.sh <verb>` với ba biến được đặt điều khiển một bản sao thử nghiệm theo cùng cách.

## Các động từ

| Động từ | Làm | In ra |
|------|------|--------|
| `check` | DIFF chỉ đọc so với feed, không thay đổi gì | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, hoặc `{"update":false,"ahead":true,"from":N,"to":M}` khi thiết bị đi trước feed (chặn hạ cấp, lành tính, rc 0) |
| `run` | chu trình LIVE đầy đủ DIFF -> FETCH -> APPLY -> COMMIT, áp dụng các tệp LIVE và dàn dựng các REBOOT-hard, tôn trọng `cancel` | tiến trình trong `journal.json` |
| `resume` | tiếp tục giao dịch đang chờ từ pha hiện tại, lũy đẳng, không bao giờ tráo `.so` | `journal.json` đã cập nhật |
| `boot` | chế độ pre-zygote, `resume` cộng việc tráo `.so` đã dàn dựng, đóng `PENDING_REBOOT` thành `DONE` | `journal.json` đã cập nhật |
| `status` | ảnh chụp chỉ đọc, không thay đổi gì | `journal.json`, hoặc `{"state":"idle"}` khi không có giao dịch nào đang hoạt động |
| `cancel` | yêu cầu dừng, một `run` đang chạy dừng ở điểm an toàn kế tiếp | tạo `$VDLU_DIR/cancel` |

Một bản cập nhật không giao diện là `check` để xem có gì đang chờ, `run` để áp dụng mọi thứ có thể lên live, rồi `boot` ở lần khởi động kế tiếp để tráo mỗi `.so` đã dàn dựng (hoặc `resume` để thử lại một lần tải bị hoãn). Mỗi động từ đều an toàn khi gọi lại, một sự cố hoặc mất mạng giữa chu trình để lại một nhật ký có thể tiếp tục, không bao giờ là một mô-đun áp dụng dở.

## JSON trạng thái

`status` (và tệp sống tại `$VDLU_DIR/journal.json`) là hợp đồng tiến trình mà cả WebUI lẫn tác nhân đều đọc:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` di chuyển theo thứ tự cố định: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` chỉ đạt được sau khi băm lại mọi thứ khớp. Một tệp REBOOT-hard đã dàn dựng cho ra `PENDING_REBOOT`, không bao giờ là `DONE` giả, chạy `boot` để hoàn tất nó.
- `DEFERRED` nghĩa là `net_policy` đã chặn việc tải, một trạng thái lành tính và có thể tiếp tục chứ không phải lỗi, kế hoạch vẫn còn và `check`/`boot` kế tiếp sẽ tiếp tục.
- `ERROR` mang lý do trong `error`, các tệp LIVE đã áp dụng được hoàn nguyên từ `rollback/`, mô-đun không bao giờ bị để lại áp dụng dở.
- `cancelled:true` với `error:null` là một lần dừng sạch, nhật ký vẫn có thể tiếp tục.

## Hợp đồng đường nối

Mọi thành phần (engine, producer, WebUI) tuân theo [`INTERFACES.md`](INTERFACES.md), luật hội tụ. Các động từ CLI, lược đồ `manifest.json`, các khóa `journal.json` và các khóa config định nghĩa ở đó là **bất biến**, hãy coi tệp đó là nguồn sự thật duy nhất và căn chỉnh theo nó trước khi thay đổi bất kỳ cái nào. Về nội bộ engine (giao dịch có thể tiếp tục, các bảo đảm nghiêm ngặt, việc loại trừ trust-anchor) xem [`ENGINE.md`](ENGINE.md), về phía feed (xây dựng và ký feed định địa chỉ theo nội dung) xem [`PRODUCER.md`](PRODUCER.md).

## Quy tắc cho một tác nhân

- Dùng các động từ và JSON, đừng bao giờ bóc tách WebUI và đừng bao giờ sửa các tệp trạng thái bằng tay.
- Coi `INTERFACES.md` là bất biến, một thay đổi nghĩa là căn chỉnh hợp đồng trước.
- Một bản vá từ tác nhân AI vượt qua cùng thanh rà soát như mọi bản khác, build luôn release, đừng nới lỏng gì, đừng mất gì.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến, xem [CONTRIBUTING.md](CONTRIBUTING.md)._
