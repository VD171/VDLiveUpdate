# Security and Trust Model

VDLU cập nhật một module tại chỗ, qua mạng, với quyền root. Đó là rất nhiều quyền lực chĩa vào một tệp đến từ một feed, nên toàn bộ engine được xây dựng trên một giả định duy nhất:

> **Mọi trường trong manifest đều là đầu vào thù địch.**

Một feed có thể bị đầu độc ở nguồn, hoặc bị tráo và băm nát khi truyền bởi một MITM. Khi điều đó xảy ra, manifest vẫn đến trông như một manifest: nó mang theo các đường dẫn tệp, các chuỗi `sha256`, một danh sách `delete[]`, các mode, các lớp và một cờ encoding. VDLU không coi bất kỳ thứ nào trong số đó là đáng tin. Nó xác thực toàn bộ kế hoạch trước khi nó tải một byte nào, và nó không bao giờ để một giá trị manifest chạm tới một shell.

Trang này là toàn bộ câu chuyện tin cậy. Xem [[Feed Format]] để biết schema manifest mà nó xác thực, và [[Engine]] để biết các lần kiểm tra này nằm ở đâu trong giao dịch DIFF -> FETCH -> APPLY -> COMMIT.

---

## Ý tưởng cốt lõi: fail-closed, trước khi bất cứ điều gì xảy ra

`validate_plan()` chạy bên trong pha `check`/diff, **trước** bất kỳ lần fetch nào và **trước** bất kỳ lần apply nào. Nó duyệt mọi mục trong cây tệp đã lập kế hoạch và mọi mục trong `delete[]`, và nếu bất kỳ mục đơn lẻ nào dị dạng thì nó **từ chối toàn bộ manifest** và giao dịch không bao giờ bắt đầu. Không có chấp nhận một phần, không có "bỏ qua cái xấu và áp dụng phần còn lại". Một trường xấu đầu độc cả lô, một cách có chủ đích.

Một manifest chỉ được chấp nhận nếu **tất cả** những điều này đều đúng cho **mọi** mục:

| Trường | Quy tắc | Tại sao |
|---|---|---|
| `path` | không tuyệt đối, không có thành phần `..`, không có thành phần `.`, không có `./` ở đầu, không có `/./` nhúng bên trong, không có dấu gạch chéo ở cuối, không có ký tự điều khiển (tab / newline) | một đường dẫn phải ở lại bên trong `MODULE_DIR`; một đường dẫn tuyệt đối hoặc `..` là ghi-bất-cứ-đâu |
| `sha256` | khớp chính xác `^[0-9a-f]{64}$` | một sha không phải hex nếu không sẽ bị nội suy vào một đường dẫn shell; nó là địa chỉ nội dung, nên nó phải là một hex digest thuần và không gì khác |
| `mode` | chỉ bát phân (`[0-7]`) | một chuỗi mode trở thành một đối số `chmod` |
| `size` | chỉ chữ số, và `<=` trần kích thước của engine | giới hạn lần tải và lần giải nén |
| `class` | chính xác `live`, `soft` hoặc `reboot` | lớp quyết định một tệp áp dụng live hay được staged để reboot |
| `enc` | chính xác `raw` hoặc `gz` | encoding quyết định blob có được gunzip hay không |
| các mục `delete[]` | cùng các quy tắc đường dẫn như trên | một mục `delete[]` điều khiển một lần gỡ bỏ; một `..` không được kiểm tra sẽ là `rm` bên ngoài cây |

Vì việc này chạy đầu tiên, một manifest bị đầu độc không bao giờ có thể ghi ra ngoài module, không bao giờ xóa ra ngoài module, và không bao giờ chèn một token không phải hex vào một dòng lệnh.

### Các giá trị manifest không bao giờ chạm tới một shell

Nửa sau của quy tắc: ngay cả sau khi một giá trị vượt qua xác thực, nó không bao giờ bị nội suy vào `sh`, và không bao giờ được đưa cho `awk system()`. Lệnh check được cố ý viết lại để không chứa lời gọi `system()` nào. Việc định địa chỉ theo nội dung làm phần còn lại của công việc: một blob được fetch theo `sha256` của nó, ghi vào một đường dẫn cache được đặt tên theo cùng `sha256` đó, và các byte đã tải được băm lại và so sánh trước khi bất cứ thứ gì được áp dụng. Một giá trị không phải là một hex digest 64 ký tự sạch không bao giờ đi được xa đến thế, vì `validate_plan()` đã từ chối nó rồi.

### Một tuyến phòng thủ thứ hai lúc apply

`validate_plan()` chặn `..` **về mặt từ vựng (lexically)**, nhưng một symlink đã tồn tại từ trước sẵn bên trong cây vẫn có thể chuyển hướng một lần ghi. Nên lúc apply, `contained()` phân giải đường dẫn đích thật và xác nhận nó nằm dưới gốc module, fail-closed khi nó không thể phân giải. Các lần ghi là nguyên tử (ghi vào một tên tạm, rồi `rename` đè lên đích) và mọi lần ghi đè đều được sao lưu vào `rollback/` trước; một lần sao lưu thất bại sẽ hủy lần apply thay vì ghi đè mà không có lưới an toàn.

---

## Hai profile

VDLU chạy ở một trong hai profile tin cậy, được đặt bởi `profile=` trong cấu hình.

### `hardened` (mặc định công khai)

- **Chữ ký là bắt buộc.** Manifest phải mang theo một chữ ký ed25519 hợp lệ từ một khóa trong keyring trên thiết bị, hoặc giao dịch bị hủy.
- **Hạ cấp bị chặn.** Một manifest có `version` thấp hơn phiên bản đã cài sẽ bị từ chối. Kẻ tấn công không thể cuốn bạn lùi về một bản build đã biết là có lỗ hổng.
- Đây là profile cho bất kỳ module nào được phân phối ra công chúng qua `https://`.

### `trusted` (riêng tư, nguồn staged qua SSH)

- Việc xác minh chữ ký là **best-effort**: nguồn là một feed `file://` riêng tư hoặc một feed staged qua SSH mà bạn kiểm soát, nên một chữ ký thiếu hoặc không thể xác minh không hủy ngay (hard-abort).
- **Nhưng `sha256` của mọi blob vẫn luôn được kiểm tra.** `trusted` nới lỏng *ai đã ký manifest*, không bao giờ *các byte có khớp với kế hoạch hay không*. Tính toàn vẹn nội dung là không thể thương lượng ở cả hai profile.

---

## Fail-closed bằng cách đảo ngược

Đây là phần tinh tế, và là phần mà hầu hết hệ thống làm sai.

`trusted` là chuỗi **duy nhất** chọn tham gia vào việc xác minh được nới lỏng. Engine không kiểm tra "cái này có phải `hardened` không?" Nó kiểm tra "cái này có phải **không** phải `trusted` không?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Nên **bất cứ thứ gì** khác với `trusted` theo nghĩa đen đều phân giải thành hành vi hardened:

- dòng bị thiếu hoàn toàn -> hardened
- một lỗi gõ như `hardend` -> hardened
- `trusted ` với một khoảng trắng ở cuối, hoặc một `\r` từ CRLF -> hardened
- `Trusted` sai chữ hoa chữ thường -> hardened
- một giá trị bị MITM băm nát -> hardened

Một phiên bản trước mặc định một dòng *bị thiếu* thành hardened, điều này vẫn để một *giá trị* bị hỏng rơi xuống đường mở. Đó là một fail-open: một chuỗi profile bị băm nát có thể âm thầm chấp nhận một manifest chưa ký, và một manifest chưa ký nghĩa là một `.so` do kẻ tấn công cung cấp được tráo vào dưới MITM, chính là thực thi mã từ xa ở cấp root. Việc đảo ngược đóng nó lại. Cách duy nhất để có được việc xác minh nới lỏng là đánh vần `trusted` chính xác, và ngay cả khi đó các hash blob vẫn được kiểm tra. Engine không bao giờ chỉ cách một lỗi gõ để chấp nhận mã chưa ký. (`tr -d` lột đi khoảng trắng lạc để một `trusted` hợp lệ với khoảng cách luộm thuộm không bị từ chối nhầm, mà không mở lại lỗ hổng.)

**Phép kiểm tra này gánh tải (load-bearing). Nó phải giữ nguyên `!= trusted` và không bao giờ trở thành `== hardened`.**

---

## Manifest được ràng buộc với module

Một khóa phát hành duy nhất ký nhiều module. Nên một manifest được ký hợp lệ, cho một module *khác*, về nguyên tắc có thể được phục vụ cho module này (một lỗi cấu hình feed, một lần tráo nguồn, hoặc một lần MITM chuyển hướng) và chữ ký của nó vẫn hợp lệ.

VDLU đóng điều này bằng một ràng buộc: trường `module` đã ký bên trong manifest phải bằng `MODID` của bản cài này, hoặc manifest bị từ chối như một feed xuyên-module. Vì `module` nằm bên trong dạng chuẩn tắc đã ký, một kẻ tấn công không thể thay đổi nó mà không phá chữ ký. Một feed được ký hợp lệ cho module B đơn giản là không thể áp dụng cho module A.

---

## Bộ xác minh gọn nhẹ trên thiết bị

Việc xác minh trên thiết bị dùng **ed25519-mini**, một bộ kiểm tra tí hon chỉ-để-xác-minh được xây dựng trên TweetNaCl (phạm vi công cộng). **Không có `openssl` trên thiết bị.**

- Mục keyring là **khóa công khai thô 32 byte**, lưu dưới dạng `keyring/<key_id>.pub`. (Khóa công khai PEM chỉ là một artifact phía PC; sao chép một PEM vào keyring thiết bị sẽ phá việc xác minh, vì bộ xác minh mong đợi đúng 32 byte thô.)
- `vdlu-verify <manifest.json> <keyring_dir>` tái dựng dạng chuẩn tắc (văn bản manifest với trường `sig` đã bị gỡ bỏ, dạng gọn, khóa đã sắp xếp), băm nó thành thông điệp hex 64 ký tự mà chữ ký bao phủ, giải mã chữ ký base64, kiểm tra nó là 64 byte, và hỏi `ed25519-mini <pub32> <msg> <sig64>` cho một phán quyết. rc 0 = hợp lệ, bất cứ thứ gì khác = từ chối.
- Nhị phân là tĩnh theo từng ABI (arm64-v8a, armeabi-v7a, x86, x86_64), với một `PROVENANCE.json` ghim chính xác các nguồn TweetNaCl, hash của wrapper và các cờ build, nên thứ đang chạy như root là có thể kiểm toán.
- `key_id` từ manifest tự nó được làm sạch (không `/`, không `..`, không dấu nháy) trước khi nó được dùng để chọn một tệp keyring, nên nó không thể thoát khỏi thư mục keyring.

### Keyring là flash-only, verify-not-copy, ổn định

Keyring được ship bên trong module lúc flash và không bị engine cập nhật ghi lại. Khi re-vendor, quy tắc là **verify, không copy**: keyring chỉ thay đổi khi luân chuyển khóa có chủ đích, không bao giờ như một tác dụng phụ của một bản cập nhật.

### Luân chuyển khóa không làm hỏng (brick) các bản cài cũ

Khi một khóa ký được luân chuyển, keyring ship **cả khóa công khai thô hiện tại lẫn khóa trước đó**. Bộ xác minh chọn tệp khóa theo `key_id` của manifest, nên một feed vẫn được ký bằng khóa cũ sẽ xác minh so với pubkey cũ, và một feed được ký bằng khóa mới sẽ xác minh so với khóa mới. Một thiết bị chưa cập nhật vượt qua lần luân chuyển vẫn tiếp tục hoạt động; không có gì bị bỏ mắc kẹt.

---

## Những gì tools-manifest đóng lại

Bootstrap fetch gọn nhẹ tải một `curl` tĩnh ở lần dùng đầu tiên cho các module không ship `curl` của riêng chúng. Vì nhị phân đó chạy như root, chữ ký manifest của riêng nó (ed25519-mini) và hash của nó là **bắt buộc ở mọi profile**, kể cả `trusted`, trước khi nó từng được cài hay thực thi. Webview chỉ là phương tiện vận chuyển; tin cậy đến từ chữ ký và lần kiểm tra hash trên thiết bị, không bao giờ từ việc một lần tải đã thành công.

---

## Những gì một kẻ tấn công KHÔNG THỂ làm

Ngay cả khi sở hữu feed, hoặc ngồi trên đường truyền như một MITM đầy đủ, một kẻ tấn công không thể:

- **Ghi ra ngoài module.** Các đường dẫn tuyệt đối, `..`, `.`, các ký tự điều khiển và dấu gạch chéo ở cuối đều bị từ chối trước bất kỳ lần apply nào, và việc chuyển hướng symlink lại bị bắt lần nữa lúc apply.
- **Xóa ra ngoài module.** Các mục `delete[]` vượt qua cùng một xác thực đường dẫn.
- **Chèn một lệnh.** Không giá trị manifest nào bị nội suy vào một shell hoặc `awk system()`; `sha256` phải là hex 64 ký tự thuần hoặc toàn bộ manifest bị từ chối.
- **Ship mã chưa ký tới một bản cài công khai.** `hardened` khiến chữ ký là bắt buộc, và profile fail-closed bằng cách đảo ngược, nên không lỗi gõ hay giá trị băm nát nào hạ cấp điều đó.
- **Phục vụ feed đã ký của một module khác ở đây.** Trường `module` đã ký phải bằng `MODID` này.
- **Cuốn bạn lùi lại.** Hạ cấp bị chặn trong `hardened`.
- **Làm hỏng một blob mà không bị phát hiện.** Mọi blob đã tải đều được băm lại so với `sha256` của manifest ở cả hai profile; một lần không khớp sau ba lần thử sẽ hủy pha này mà không áp dụng gì.
- **Tráo vào một bộ fetch root giả.** `curl` được bootstrap được kiểm tra chữ ký và hash trước khi nó được cài hoặc chạy, ở mọi profile.
- **Áp dụng dở dang một bản cập nhật hỏng.** Giao dịch chỉ đạt `DONE` khi một lần băm lại mọi thứ đều khớp; một lần apply thất bại sẽ rollback thay vì ghi đè mà không có bản sao lưu.

---

Xem thêm: [[Feed Format]] để biết schema manifest, [[Engine]] để biết giao dịch mà các lần kiểm tra này sống trong đó, và [[Architecture]] để biết bức tranh lớn.
