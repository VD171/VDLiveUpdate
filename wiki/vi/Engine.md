# Engine

Engine là phía thiết bị của VDLU: phần chạy trên điện thoại, quyết định cái gì đã thay đổi, tải nó về, và áp dụng nó. Đó là một script shell POSIX duy nhất, `engine/update.sh`, cộng với một bộ kiểm tra chữ ký tí hon, `engine/vdlu-verify`. Cả hai được vendor vào module chủ tại `<module>/vdlu/` và chạy bởi root.

Toàn bộ engine được xây dựng quanh một ý tưởng: một bản cập nhật là một **giao dịch có thể tiếp tục**. Nếu điện thoại bị khởi động lại, bị giết tiến trình, hoặc mất mạng giữa chừng, lần chạy tiếp theo sẽ tiếp nối đúng chỗ nó dừng lại, và module không bao giờ bị bỏ lại áp dụng dở dang trong khi giả vờ đã xong.

Nếu bạn muốn xem bức tranh lớn trước, hãy xem [[Architecture]]. Để biết cách các bản cập nhật tránh khởi động lại bất cứ khi nào có thể, xem [[Reboot Handling]].

## Viết cho thiết bị, không phải cho laptop của bạn

`update.sh` là thuần POSIX `sh`. Nó chạy dưới mksh, busybox, hoặc toybox, không có tính năng chỉ-dành-cho-bash, và nó vượt qua `sh -n`. Điều đó quan trọng vì môi trường trên một thiết bị Android đã root là nhỏ và nghiêm ngặt.

Cụ thể, không có `jq`. VDLU phân tích `manifest.json` bằng một bộ làm phẳng nhỏ theo kiểu gron viết bằng `awk`: nó duyệt JSON từng ký tự một và phát ra một dòng `path<TAB>value` cho mỗi nút lá (ví dụ `files/0/sha256<TAB>ab..` hoặc `version<TAB>6`). Shell sau đó đọc những dòng đó bằng `grep` và `cut`. Cách này hoạt động trên cả JSON dạng gọn lẫn JSON in đẹp, và nó không bao giờ gọi ra một công cụ JSON vốn không có mặt ở đó.

Engine chỉ phụ thuộc vào những gì toybox đã có sẵn (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), bộ xác minh `ed25519-mini` được nhúng sẵn, và, với các feed `https://`, một `curl` tĩnh nhỏ được tải về và xác minh một lần. Một feed `file://` không cần `curl` chút nào.

## Sáu lệnh

Bạn gọi engine với các đường dẫn của module nằm trong môi trường và một lệnh:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Mã thoát `0` nghĩa là thành công; bất kỳ mã nào khác nghĩa là một lỗi, với lý do được in ra stderr.

| Lệnh | Việc nó làm |
|---|---|
| `check` | Diff chỉ đọc. Tải manifest, so sánh nó với những gì đã cài, và in một bản tóm tắt JSON một dòng: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Không thay đổi gì trên đĩa. Nếu thiết bị mới hơn feed (một lần hạ cấp bị chặn) nó báo cáo `{"update":false,"ahead":true,...}` với mã thoát `0`, không phải lỗi. |
| `run` | Chu trình live đầy đủ: DIFF, FETCH, APPLY, COMMIT. Áp dụng mọi tệp live ngay lập tức và staged số ít tệp thuộc lớp reboot. Tôn trọng `cancel`. Ghi tiến trình vào `journal.json`. |
| `resume` | Tiếp tục một giao dịch bị gián đoạn, bắt đầu từ bất kỳ pha nào nó đang ở. Lũy đẳng. Nó **không** hoán đổi một `.so` đã staged (việc đó dành riêng cho `boot`). |
| `boot` | Đường pre-zygote. Thực hiện một `resume` rồi hoán đổi bất kỳ tệp `*.vdlu-new` nào đã staged vào vị trí, đóng `PENDING_REBOOT` thành `DONE`. Nếu không có giao dịch nào đang chờ, nó chạy một chu trình mới và áp dụng mọi thứ, bao gồm cả `.so`, trong lần khởi động duy nhất đó. |
| `status` | In `journal.json`, hoặc `{"state":"idle"}` khi không có gì đang diễn ra. |
| `cancel` | Tạo một dấu `cancel`. Một `run` đang diễn ra sẽ dừng gọn gàng tại điểm an toàn kế tiếp. |

Lệnh `check` được cố ý làm cho rẻ, nên giao diện có thể cho bạn biết có một bản cập nhật trên bất kỳ mạng nào. Việc tải thực sự được kiểm soát riêng (xem pha fetch bên dưới).

## Giao dịch, từng bước

Mỗi `run` di chuyển qua một máy trạng thái cố định, được ghi lại trong `journal.json` để WebUI (và bạn) có thể theo dõi:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Engine tải `manifest.json`, xác thực mọi trường (xem bên dưới và [[Security and Trust Model]]), và diff cây đích đã ký so với `current.json`, manifest của phiên bản đã được cài. Kết quả là một kế hoạch theo từng tệp được ghi vào `plan.tsv`: một hàng cho mỗi tệp, mang theo lớp (class), hash đích, mode, và trạng thái tiến trình của nó. Các tệp đã ở đúng hash đích được đánh dấu để bỏ qua.

**FETCH.** Với mỗi tệp còn cần, engine tải nội dung định địa chỉ theo nội dung của nó từ `<source>/blobs/<sha>` (hoặc `<sha>.gz` khi được nén), vào một tệp `.part`. Nếu blob được gzip thì nó được giải nén, rồi SHA-256 của nó được kiểm tra so với manifest. Chỉ khi khớp thì nó mới được `mv` một cách nguyên tử vào `blobs/<sha>`. Một blob đã có trong cache với hash đúng sẽ bị bỏ qua hoàn toàn, và một tệp cục bộ không đổi có thể gieo mầm vào cache mà không cần tải. Ba lần thất bại trên cùng một blob sẽ hủy pha này mà không áp dụng gì. Pha này chỉ đạt `FETCHED` khi mọi blob trong kế hoạch đã có mặt và đã xác minh. Để biết các blob này đến từ đâu, xem [[Feed Format]].

Việc fetch được kiểm soát bởi chính sách mạng: một feed có thể bị giới hạn chỉ dùng Wi-Fi, chỉ dùng mạng di động, hoặc bất kỳ mạng nào. Khi mạng hiện tại không được phép, việc fetch không thất bại; nó vào trạng thái lành tính `DEFERRED`, giữ nguyên kế hoạch và đích đã ghim, và tiếp tục ở lần check hoặc boot tiếp theo một khi mạng đúng xuất hiện. Không tốn dữ liệu nào trong lúc chờ.

**APPLY.** Chỉ được vào từ `FETCHED`. Với mỗi tệp, engine hành động theo lớp:

- tệp `live` và `soft`: sao lưu tệp hiện tại vào `rollback/<version>/<path>`, ghi nội dung mới vào một tệp anh em `.vdlu-tmp`, `chmod` nó, xác minh hash của nó, rồi `rename` nó một cách nguyên tử đè lên đích. Một tệp đã ở đúng hash đích sẽ bị bỏ qua.
- tệp `reboot` (một `.so`, một overlay `/system`, một `sepolicy.rule`): hiện thực hóa vào `staged/<path>.vdlu-new`. Inode đang sống không bao giờ bị chạm vào ở đây. Xem [[Reboot Handling]].
- các lần xóa: sao lưu, rồi gỡ bỏ. Các lần xóa chỉ được áp dụng ở cuối cùng, trên một `DONE` sạch, không bao giờ trong khi một lần khởi động lại vẫn đang chờ.

**COMMIT.** Engine băm lại mọi tệp live và soft mà nó đã chạm vào. Chỉ khi tất cả đều khớp thì nó mới ghi `current.json`, biến phiên bản mới thành cơ sở để diff. Nếu bất kỳ tệp thuộc lớp reboot nào đã được staged, trạng thái trở thành `PENDING_REBOOT` thay vì `DONE`; việc hoán đổi và lần xác minh lại cuối cùng diễn ra sau, dưới lệnh `boot`.

## An toàn trước sự cố theo thiết kế

Những bảo đảm khiến việc chạy không giám sát này an toàn:

- **Không có gì được đánh dấu `DONE` mà không có một lần băm lại khớp.** `DONE` chỉ đạt được sau khi mọi tệp đã áp dụng được đọc lại và SHA-256 của nó được so với manifest. Một tệp reboot đã staged buộc trạng thái vào `PENDING_REBOOT`, không bao giờ là một `DONE` giả.
- **Không có gì bị mất.** Mọi tệp đều được sao lưu vào `rollback/<version>/` trước khi bị ghi đè, và ba phiên bản gần nhất được giữ lại. Nếu một lần áp dụng thất bại, các tệp live được hoàn nguyên từ bản sao lưu; module không bao giờ bị bỏ lại áp dụng dở dang mà nói dối về điều đó. `apply_live` hủy ngay nếu bước sao lưu thất bại, thay vì ghi đè mà không có đường lui.
- **Mọi thứ đều nguyên tử.** Nội dung mới đáp xuống qua `rename`/`mv` đè lên đích, nên một tiến trình đọc luôn thấy hoặc tệp cũ hoặc tệp mới, không bao giờ thấy một lần ghi bị cắt cụt.
- **Có thể tiếp tục sau sự cố hoặc bị giết tiến trình.** Một sự cố, một lần mất mạng, hay một lần khởi động lại giữa chừng để lại một nhật ký hợp lệ; `resume` (hoặc `boot`) tiếp tục từ pha đã ghi. Thiết kế giả định rằng nó sẽ bị gián đoạn.
- **Suy giảm một cách gọn gàng.** Một nhị phân thiếu, một mạng bị sập, hay một đĩa đầy sẽ tạo ra một lỗi rõ ràng trên stderr và `state:ERROR` trong nhật ký, mà không làm hỏng module.

## Khóa

Chỉ một giao dịch được phép chạm vào trạng thái tại một thời điểm. `flock` không đáng tin cậy trên toybox, nên VDLU tuần tự hóa bằng một khóa thư mục: `mkdir "$VDLU_DIR/lock.d"` thành công cho đúng một lời gọi và thất bại với số còn lại, điều này là nguyên tử trên bất kỳ hệ thống tệp hợp lý nào. Một khóa cũ bị một tiến trình đã chết để lại được khôi phục bằng cách kiểm tra PID đã ghi.

Lần thử lại kiên nhẫn lúc khởi động (dùng khi thiết bị offline lúc boot) **không** giữ khóa này trong khi chờ. Nó giành và nhả giữa các lần thử, nên một `run` thủ công không bao giờ bị chặn bởi một lần khởi động đang chờ mạng, và nó không bao giờ giữ một wakelock. An toàn pin theo thiết kế. Thêm về điều đó trong [[Reboot Handling]].

## Kiểm tra chữ ký: `vdlu-verify`

`vdlu-verify` là bộ kiểm tra chữ ký trên thiết bị, được giữ gọn một cách cố ý:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Mã thoát `0` nghĩa là chữ ký của manifest hợp lệ so với khóa công khai trong keyring có id khớp với `key_id` của manifest; bất kỳ mã nào khác là một lần từ chối.

Điều khiến nó gọn là nó dùng **không có `openssl` trên thiết bị**. Nó đọc khóa công khai keyring như một tệp **thô 32 byte**, chuẩn tắc hóa manifest (văn bản manifest với trường `sig` đã bị gỡ bỏ), băm nó bằng toybox `sha256sum`, giải mã base64 chữ ký, và trao khóa thô, thông điệp, và chữ ký 64 byte cho nhị phân `ed25519-mini` được nhúng sẵn. Bộ kiểm tra cũng từ chối bất cứ thứ gì dị dạng trước cả khi nó xác minh: một `key_id` hoặc `sig` thiếu hoặc rỗng, một `key_id` chứa dấu phân cách đường dẫn, một khóa công khai không đúng chính xác 32 byte, hoặc một chữ ký không đúng chính xác 64 byte.

Việc chuẩn tắc hóa giống hệt từng byte so với bộ ký của producer, chính điều đó khiến một chữ ký xác minh được xuyên các công cụ. Khóa riêng tương ứng không bao giờ chạm vào thiết bị hay CI; chỉ khóa công khai thô được nhúng. Toàn bộ câu chuyện tin cậy, hai profile, và lý do tại sao `hardened` fail-closed bằng cách đảo ngược nằm trong [[Security and Trust Model]].

Engine gọi `vdlu-verify` trong pha diff. Dưới profile `hardened`, một lần xác minh thất bại sẽ hủy toàn bộ bản cập nhật; dưới `trusted`, việc xác minh là best-effort, nhưng hash của mọi blob vẫn luôn được kiểm tra, nên nội dung bị hỏng đều bị bắt bất kể profile nào.

## Trạng thái trên đĩa

Toàn bộ trạng thái của engine nằm trong `$VDLU_DIR` (bên ngoài thư mục module), nên bản thân cây module chỉ bao giờ giữ các tệp đã hoàn thiện:

| Đường dẫn | Vai trò |
|---|---|
| `config` | cài đặt key=value (source, profile, channel, chính sách mạng, thử lại lúc boot) |
| `current.json` | manifest của phiên bản đang hoạt động; đây là cơ sở để diff. Vắng mặt nghĩa là chưa bao giờ cập nhật |
| `target.json` | manifest đã ghim của giao dịch đang diễn ra. Sự hiện diện của nó đánh dấu một giao dịch đang hoạt động; nó trở thành `current.json` khi `DONE` |
| `plan.tsv` / `plan.del` | kế hoạch và tiến trình theo từng tệp, và danh sách các đường dẫn cần xóa |
| `journal.json` | tiến trình cho WebUI, được ghi lại ở mỗi lần đổi trạng thái |
| `blobs/<sha256>` | cache nội dung gốc đã xác minh, đã giải nén |
| `rollback/<version>/<path>` | bản sao lưu các tệp bị ghi đè; ba phiên bản gần nhất được giữ lại |
| `staged/<path>.vdlu-new` | một tệp thuộc lớp reboot đang chờ hoán đổi lúc boot |
| `lock.d/` | khóa mkdir |
| `tools/<abi>/curl` | curl tĩnh đã tải, đã xác minh; tồn tại xuyên các bản cập nhật |
| `cancel` | một yêu cầu hủy |

## Xem thêm

- [[Reboot Handling]]: cách hệ thống lớp giữ cho phần lớn bản cập nhật không cần khởi động lại, và cách một `.so` đã staged được hoán đổi pre-zygote.
- [[Security and Trust Model]]: hai profile, xác thực fail-closed, và chuỗi ed25519 khóa thô.
- [[Feed Format]]: manifest và các blob định địa chỉ theo nội dung mà engine tiêu thụ.
- [[Architecture]]: cách engine, producer, và WebUI khớp với nhau.
