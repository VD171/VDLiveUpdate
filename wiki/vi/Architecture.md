# Architecture

VDLU có hai phía được nối với nhau bởi một thứ ở chính giữa. Trên PC, [[Producer]] biến một cây module thành một feed đã ký, định địa chỉ theo nội dung. Trên thiết bị, [[Engine]] đọc feed đó, tìm ra cái gì đã thay đổi, và áp dụng nó. Đường nối giữa chúng là **manifest đã ký cộng với kho blob** ([[Feed Format]]). Không có gì khác vượt qua khoảng cách này.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Hai phía không bao giờ dùng chung một runtime. Producer dùng `python3` và `openssl`; Engine là thuần POSIX `sh` với toybox và một `ed25519-mini` được nhúng sẵn. Chúng chỉ đồng thuận với nhau vì cả hai đều rút ra **cùng một chuỗi byte chuẩn tắc (canonical)** từ một manifest (xem [[Security and Trust Model]]). WebUI là một bảng điều khiển vanilla-JS mỏng, điều khiển engine qua cầu nối root-manager và đọc nhật ký tiến trình của nó; nó không chứa logic cập nhật nào của riêng mình. Xem [[WebUI]].

## Hai phía

| Phía | Chạy trên | Xây dựng từ | Nhiệm vụ |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Duyệt cây module thành `manifest.json` + `blobs/`, ký nó, dọn các blob mồ côi |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | Diff cây đã cài so với feed, tải delta, áp dụng, commit |
| [[WebUI]] | device (webview) | vanilla JS/CSS | Kích hoạt cập nhật, hiển thị tiến trình, chỉnh cấu hình, hiển thị biểu ngữ khởi động lại |

## Pipeline cập nhật

Mỗi lần cập nhật là một giao dịch, chạy theo một thứ tự cố định:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` chính là pha này, chỉ đọc). Engine chỉ tải manifest, chạy `validate_plan()` trên mọi trường **trước khi** chạm vào bất cứ thứ gì, rồi so sánh feed với `current.json` để dựng một kế hoạch theo từng tệp. Nó không thay đổi gì trên đĩa. Một thiết bị đi trước feed là một kết quả "ahead" lành tính, không phải lỗi.
- **FETCH.** Chỉ tải những blob mà kế hoạch còn thiếu, vào `<sha>.part`, giải nén `gz`, kiểm tra `sha256sum` so với manifest, và `mv` một cách nguyên tử mỗi blob đã xác minh vào cache. Một blob đã có trong cache (hoặc được gieo mầm từ một tệp cục bộ không đổi) sẽ bị bỏ qua, nên một lần hoàn nguyên hoặc một tệp dùng chung không tốn gì cả. Ba lần thất bại trên một blob sẽ hủy pha này mà không áp dụng gì. Một lần tải bị chính sách mạng chặn sẽ thoát ra ở trạng thái `DEFERRED` (có thể tiếp tục), không phải lỗi.
- **APPLY.** Các tệp thông thường (`live` / `soft`) được ghi ngay bây giờ: sao lưu vào `rollback/<v>/`, ghi một `.vdlu-tmp`, `chmod`, xác minh, rồi `rename` nguyên tử đè lên đích. Các tệp thuộc lớp reboot được hiện thực hóa vào `staged/<path>.vdlu-new` và inode đang sống được giữ nguyên. Một mục `delete[]` được sao lưu, rồi gỡ bỏ. Mọi bước đều lũy đẳng (idempotent): một tệp đã ở đúng hash đích sẽ bị bỏ qua.
- **COMMIT.** Băm lại mọi tệp live; chỉ khi mọi thứ khớp thì engine mới đề bạt `target.json` thành `current.json`. Nếu có gì được staged, giao dịch kết thúc ở `PENDING_REBOOT`; nếu không thì `DONE`.

## Manifest và blob định địa chỉ theo nội dung

Feed được định địa chỉ theo nội dung: manifest liệt kê **toàn bộ** cây đích, mỗi tệp được mang theo bởi `sha256` của nó, và kho blob giữ một bản sao của mỗi nội dung khác biệt dưới dạng `blobs/<sha256>` (hoặc `blobs/<sha256>.gz`).

- **Dedup.** Nội dung giống hệt nhau ở bất kỳ đâu trong cây, hay xuyên các bản phát hành, đều là một blob. Việc xuất bản là tăng dần: một blob có `sha256` đã tồn tại trên host sẽ không bao giờ bị đẩy lại, và thiết bị không bao giờ tải lại nội dung mà nó đã có.
- **sha256 là của bản gốc.** Hash luôn đặt tên cho nội dung chưa nén; `enc` (`raw` hoặc `gz`) chỉ ghi lại cách blob đó tình cờ được lưu. Thiết bị giải nén `gz` bằng toybox `gunzip`, nên không có bộ nén thừa nào được đóng gói kèm.
- **Ổn định theo phiên bản (flavor-stable).** Vì thiết bị diff so với những gì thực sự được cài, feed có thể mang cả một họ module; mỗi bản cài chỉ kéo về những blob hoàn thiện phiên bản của riêng nó.

Bố cục đầy đủ theo từng trường nằm trong [[Feed Format]].

## Nhật ký có thể tiếp tục

Mọi giao dịch đều an toàn trước sự cố vì tiến trình của nó nằm trong một nhật ký (`journal.json`), và đích đã ghim của giao dịch đang diễn ra nằm trong `target.json`. Máy trạng thái chạy theo một thứ tự cố định:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Trạng thái | Ý nghĩa |
|---|---|
| `PLANNED` | Đã dựng kế hoạch, chưa tải gì |
| `FETCHING` / `FETCHED` | Đang tải blob / tất cả blob đã có và đã xác minh |
| `APPLYING` / `APPLIED_LIVE` | Đang ghi tệp / mọi tệp live đã ghi xong |
| `PENDING_REBOOT` | Một tệp thuộc lớp reboot đã được staged, đang chờ hoán đổi lúc khởi động |
| `DONE` | Băm lại mọi thứ đều khớp; `current.json` đã được đề bạt |
| `ERROR` | Thất bại nặng; module không bị hỏng, các tệp live được hoàn nguyên từ `rollback/` |
| `DEFERRED` | Lần tải bị chính sách mạng giữ lại; kế hoạch được lưu lại, tiếp tục sau |

`DONE` **chỉ** đạt được khi một lần băm lại mọi thứ đều khớp, nên nhật ký không bao giờ tuyên bố một bản cập nhật áp dụng dở dang là hoàn tất. Một sự cố, một lần rớt mạng, hay một lần khởi động lại giữa chừng sẽ để lại một nhật ký có thể tiếp tục; `update.sh resume` (hoặc `boot`) tiếp nối từ pha hiện tại. Xem [[Engine]] để biết bộ lệnh và các tệp trạng thái trên thiết bị.

## Tính nguyên tử và rollback

Không có gì bị ghi đè tại chỗ và không có gì bị mất:

- **Ghi nguyên tử.** Mỗi tệp đáp xuống qua một tệp tạm (`.vdlu-tmp`) và một `rename` / `mv` nguyên tử, nên một tiến trình đọc không bao giờ thấy một tệp ghi dở dang.
- **Sao lưu trước khi ghi đè.** Nội dung trước đó đi vào `rollback/<version>/<path>` trước khi tệp mới được rename đè lên (vài phiên bản gần nhất được giữ lại). Nếu một lần áp dụng thất bại, các tệp live được hoàn nguyên từ bản sao rollback thay vì bị bỏ lại hư hỏng. Một lần sao lưu thất bại sẽ **hủy** lần áp dụng thay vì ghi đè mà không có lưới an toàn.
- **Tuần tự hóa.** Một khóa dựa trên `mkdir` (`lock.d/`, vì `flock` không khả thi trên toybox, với cơ chế khôi phục khóa cũ theo PID) tuần tự hóa các lần chạy đồng thời.

## Nguyên tắc không cần khởi động lại

Phần lớn tệp có thể được hoán đổi khi module đang sống, nên VDLU áp dụng chúng ngay lập tức. Chỉ có ba lớp cần khởi động lại, vì một tiến trình đang sống đã ánh xạ (map) chúng: một `.so` (được Zygisk nạp), một overlay `/system`, và một `sepolicy.rule`. Những thứ đó được **staged, không bao giờ ghi đè lên một inode đang sống**, và được hoán đổi trong một bước pre-zygote duy nhất ở lần khởi động tiếp theo. Toàn bộ phân loại và luồng khởi động nằm trong [[Reboot Handling]].

## Thế trận tin cậy fail-closed

Feed là thứ duy nhất vượt từ PC sang thiết bị, nên engine coi mọi byte của nó là thù địch. `validate_plan()` chạy trong pha DIFF, trước bất kỳ lần tải nào, và từ chối toàn bộ manifest khi có bất kỳ trường dị dạng nào. Việc xác minh chữ ký dùng một `ed25519-mini` được nhúng sẵn (không có `openssl` trên thiết bị), khóa riêng không bao giờ chạm vào thiết bị hay CI, và profile `hardened` fail-closed bằng cách đảo ngược nên một giá trị profile bị hỏng không bao giờ có thể âm thầm chấp nhận một feed chưa ký. Toàn bộ mô hình, hai profile, và các mối đe dọa mà mỗi profile trả lời nằm trong [[Security and Trust Model]].
