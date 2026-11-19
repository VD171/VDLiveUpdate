> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · Tiếng Việt · [中文](../zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

Client cập nhật tăng tiến, flashless cho các module KSU/Magisk. Hiện thực chu trình
`DIFF -> FETCH -> APPLY -> COMMIT` dưới dạng một giao dịch có thể tiếp tục. Tuân theo `INTERFACES.md` (luật
hội tụ).

POSIX sh thuần (mksh/busybox/toybox). **SLIM:** nó chỉ phụ thuộc vào toybox (`sha256sum`/`gzip`/`base64`/`date`) +
`ed25519-mini` nhúng (xác minh ed25519; **không có openssl trên thiết bị**) + một `curl` tĩnh được **tải về** ở
lần cập nhật https đầu tiên (WebUI làm `fetch()`, lưu nó trong Tier-2, và `install-tool` xác minh
chữ ký+băm của nó TRƯỚC khi dùng). `file://` không cần curl. Không phụ thuộc vào `jq`.

## Gọi lệnh

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = lỗi (lý do trên stderr). `vdlu-verify` được cung cấp bởi một thành phần khác
(chữ ký trong `INTERFACES.md §6`); engine chỉ gọi nó.

| cmd | làm gì |
|---|---|
| `check` | DIFF chỉ-đọc; in `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; không thay đổi gì |
| `run` | chu trình LIVE đầy đủ + staging REBOOT-hard; tôn trọng `cancel`; tiến độ trong `journal.json` |
| `resume` | tiếp tục giao dịch đang chờ (`target.json`) từ pha hiện tại; idempotent; **không** hoán đổi `.so` |
| `boot` | chế độ pre-zygote: resume **+** hoán đổi `staged/*.vdlu-new` → đóng `PENDING_REBOOT`→`DONE`. Không có giao dịch đang chờ, nó chạy một chu trình mới và áp dụng mọi thứ (bao gồm `.so`) trong một lần khởi động |
| `status` | in `journal.json` (hoặc `{"state":"idle"}`) |
| `cancel` | tạo `$VDLU_DIR/cancel`; một `run` đang chạy dừng tại điểm an toàn kế tiếp |

## Máy trạng thái (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` chỉ khi băm lại TẤT CẢ khớp. Nếu bất kỳ REBOOT-hard nào đã staging ⇒ `PENDING_REBOOT` (không bao giờ một
`DONE` giả). `ERROR` khi có bất kỳ thất bại nào, mà không làm hỏng module (các tệp LIVE đã áp dụng được hoàn nguyên
từ `rollback/<v>/`; không có gì "nửa-áp-dụng mà nói dối về điều đó"). Lối ra lành của pha `fetch`: **`DEFERRED`** -
việc tải đã bị hoãn bởi `net_policy` (mạng không được phép); plan/target tồn tại và nó tiếp tục ở lần
check/boot kế tiếp (WebUI hiện một toast info xanh "đang chờ mạng X", không phải lỗi).

## Bảo đảm nghiêm ngặt

- **FETCH:** được kiểm soát bởi `net_policy` (any/wifi/mobile; chỉ http/https, `file://` không bao giờ) - một mạng không được phép ⇒
  `DEFERRED` (có thể tiếp tục), mà không tốn dữ liệu. Chỉ tải những gì còn thiếu vào `<sha>.part` (curl với
  `--connect-timeout` + `--speed-time`, không bao giờ treo), giải nén `gz` (toybox `gunzip`), kiểm tra `sha256sum` ==
  manifest, `mv` nguyên tử tới `blobs/<sha>`. Một blob đã-cache+ok được bỏ qua. Nó có thể gieo blob từ một tệp
  cục bộ không đổi (dedup/offline). **3 lần thất bại trên cùng một blob = pha hủy bỏ mà không áp dụng gì.** Nó
  chỉ trở thành `FETCHED` khi TẤT CẢ các blob của kế hoạch đều hiện diện+đã xác minh.
- **APPLY** (chỉ từ `FETCHED`): `live`/`soft` → sao lưu tới `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` nguyên tử. `reboot` → hiện thực hóa vào `staged/<path>.vdlu-new` (KHÔNG chạm vào inode live).
  `delete[]` → sao lưu → xóa. Idempotent (một tệp đã ở băm đích được bỏ qua).
- **COMMIT:** băm lại mỗi `live`/`soft`; chỉ khi đó mới ghi `current.json`. Với các tệp đã staging ⇒
  `PENDING_REBOOT`. `boot` làm `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + xác minh lại +
  `DONE`.
- **cancel:** kiểm tra giữa các tệp (điểm an toàn); xóa `.vdlu-tmp`/`.part` đang bay, xóa `cancel`,
  để lại journal có thể tiếp tục (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** tuần tự hóa (flock không khả thi trên toybox; khôi phục khóa cũ theo PID).
  Boot-retry KIÊN NHẪN không giữ khóa trong khi chờ (`acquire_lock_try`+release giữa các lần thử) cũng không giữ
  wakelock - an toàn pin. Một crash/mạng/khởi động lại giữa chừng → `resume`/`boot` tiếp tục.
- **profile=hardened** ⇒ `vdlu-verify` bắt buộc trên manifest TRƯỚC khi dùng; thất bại = abort; downgrade bị chặn
  (phiên bản đơn điệu). **trusted** ⇒ verify là best-effort, nhưng băm của mỗi blob LUÔN được kiểm tra.
- Suy giảm uyển chuyển: thiếu binary / mạng sập / đĩa đầy → một lỗi rõ ràng trên stderr + `state:ERROR` trong
  journal, mà không làm hỏng module.

## Phân tích JSON không cần jq

Một flattener kiểu gron trong `awk` (POSIX thuần: `substr`/`index`/`gsub`/`split`/`printf` + các biến cục bộ truyền dưới dạng
tham số) token hóa manifest từng ký tự một và phát ra một dòng `path<TAB>value` cho mỗi lá vô hướng
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Bền vững với JSON nén HOẶC
in đẹp. `sh` tiêu thụ nó với `grep`/`cut`; kế hoạch theo từng tệp được lắp ráp lại trong một `awk` thứ 2 thành TSV
(`class st mode enc sha size path`), trở thành `$VDLU_DIR/plan.tsv`.

## Các tệp trạng thái (trong `$VDLU_DIR`, Tier-2)

| tệp | vai trò |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; xem INTERFACES §5) |
| `current.json` | manifest của phiên bản ĐANG HOẠT ĐỘNG (cơ sở diff); vắng mặt = chưa bao giờ cập nhật |
| `target.json` | manifest được ghim của giao dịch đang bay (hiện diện = giao dịch đang hoạt động); trở thành `current.json` khi `DONE` |
| `plan.tsv` / `plan.del` | kế hoạch + tiến độ theo từng tệp (st) / các path cần xóa |
| `journal.json` | tiến độ cho WebUI (tái tạo ở mỗi lần chuyển) |
| `blobs/<sha256>` | bộ nhớ đệm nội dung gốc đã xác minh |
| `rollback/<version>/<path>` | sao lưu các tệp bị ghi đè (undo; giữ 3 cái cuối) |
| `staged/<path>.vdlu-new` | REBOOT-hard chờ hoán đổi lúc khởi động |
| `lock.d/` | mkdir-lock (flock không khả thi trên toybox; khôi phục khóa cũ theo PID) |
| `tools/<abi>/curl` | curl tĩnh được tải (slim bootstrap); tồn tại qua các lần cập nhật |
| `cancel` | yêu cầu hủy |

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
