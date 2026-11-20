# FAQ

Câu trả lời ngắn cho những câu hỏi hay gặp nhất. Mỗi câu liên kết tới trang có
câu chuyện đầy đủ.

## "Flashless" nghĩa là gì? Tôi có còn phải flash lần đầu không?

Có, bạn flash một lần. Module được cài theo cách thông thường (flash zip trong
root manager của bạn). "Flashless" mô tả mọi bản cập nhật sau đó: VDLU chỉ fetch
những tệp đã thay đổi và áp dụng chúng tại chỗ, nên bạn không bao giờ phải flash lại một
zip đầy đủ chỉ để ship vài dòng thay đổi. Xem [[Architecture]].

## Một bản cập nhật có cần khởi động lại không?

Thường là không. Phần lớn tệp (WebUI của bạn, các nhị phân, các thư viện, các config, `module.prop`)
thuộc lớp **live** và áp dụng nguyên tử không cần khởi động lại. Chỉ các tệp thuộc lớp reboot
(một `.so` dưới `zygisk/`, một overlay `/system/**`, một tệp sepolicy `*.rule`) mới được
**staged** và hoán đổi vào ở lần boot tiếp theo, vì một tiến trình đang chạy đã
ánh xạ inode live. Khi điều đó xảy ra, WebUI hiển thị một biểu ngữ "reboot để
activate" dai dẳng. Xem [[Reboot Handling]].

## Có an toàn không nếu feed bị MITM hoặc bị đầu độc?

Có, trên một feed `hardened`. Mọi trường manifest được coi là đầu vào thù địch.
Manifest phải mang theo một chữ ký ed25519 hợp lệ trên dạng chuẩn tắc của nó, và
`validate_plan()` chạy fail-closed **trước bất kỳ lần tải nào**: nó từ chối toàn bộ
manifest khi có một đường dẫn tuyệt đối hoặc `..`, một `sha256` không phải 64 ký tự hex,
hoặc một mode, class hay encoding không hợp lệ. Manifest cũng được ràng buộc với id module
của bạn, nên một feed được ký hợp lệ cho một module khác không thể được phục vụ thay thế.
sha256 của mọi blob được xác minh sau khi tải bất kể profile nào. Xem
[[Security and Trust Model]].

## Nó cần gì trên thiết bị (các phụ thuộc)?

Rất ít. Thuần POSIX sh (mksh / busybox / toybox) cộng với `sha256sum`,
`gzip`, `base64` và `date` của toybox; bộ xác minh `ed25519-mini` được nhúng sẵn; và, chỉ cho
một nguồn `https`, một `curl` tĩnh được fetch một lần và cache trong Tier-2.
Một nguồn `file://` không cần curl chút nào. **Không có phụ thuộc vào `jq`**:
engine phân tích JSON bằng một bộ làm phẳng theo kiểu gron viết bằng `awk`. Xem [[Engine]].

## Có cần openssl trên thiết bị không?

Không. `openssl` chỉ được dùng ở phía PC/phát hành (`vdlu-keygen`, `vdlu-sign`).
Trên thiết bị, việc xác minh chữ ký dùng nhị phân `ed25519-mini` được nhúng sẵn gọn nhẹ,
nhị phân này đọc một khóa công khai THÔ 32 byte. Xem [[Producer]] và
[[Security and Trust Model]].

## Làm thế nào để tôi luân chuyển khóa ký?

Tạo một cặp khóa mới với `vdlu-keygen`, thêm khóa công khai THÔ 32 byte mới vào
keyring thiết bị bên cạnh khóa trước đó, và bắt đầu ký với `key_id` mới. Thiết bị chọn
`<keyring>/<key_id>.pub` theo `key_id` của manifest, nên không cần thay đổi engine.
Ship cả khóa công khai hiện tại lẫn khóa trước đó nghĩa là một khóa đã luân chuyển
không bao giờ làm hỏng (brick) các bản cài cũ. Xem [[Security and Trust Model]].

## hardened so với trusted - tôi dùng cái nào?

Dùng `hardened` cho bất kỳ feed công khai nào (phục vụ qua `https`, ví dụ GitHub Pages).
Nó khiến chữ ký là bắt buộc và chặn các lần hạ cấp. Chỉ dùng `trusted` cho một
nguồn `file://` riêng tư hoặc staged qua SSH mà bạn đã kiểm soát, nơi chữ ký
là best-effort (hash của mọi blob vẫn được kiểm tra). Khi nghi ngờ, dùng `hardened`:
nó là mặc định fail-closed, và bất kỳ giá trị không-`trusted` nào đều được coi là
`hardened`. Xem [[Security and Trust Model]].

## Nếu một blob bị can thiệp hoặc manifest bị dị dạng thì sao?

Bản cập nhật bị hủy và không có gì được áp dụng. Một manifest dị dạng bị từ chối toàn bộ
bởi `validate_plan()` trước bất kỳ lần fetch nào. Một blob có sha256 không khớp
manifest sẽ bị từ chối; ba lần thất bại trên cùng một blob sẽ hủy pha fetch mà
không áp dụng gì. Khi có bất kỳ thất bại nặng nào, nhật ký ghi `ERROR` và module
được giữ nguyên vẹn. Xem [[Engine]].

## Một bản cập nhật có thể xóa các tệp của tôi hoặc làm hỏng (brick) thiết bị không?

Rủi ro được kiềm chế theo thiết kế. Các tệp bị ghi đè và bị xóa trước tiên được sao
lưu vào `rollback/<version>/`, và `apply` hủy thay vì ghi đè mà không có một lần sao lưu
thành công. Các lần xóa chỉ chạy khi một giao dịch đạt `DONE`, không bao giờ
trong khi một lần khởi động lại vẫn đang chờ. Một lần apply thất bại sẽ hoàn nguyên các tệp live
mà nó đã ghi. Các đường dẫn được xác thực về tính chứa đựng bên trong thư mục module trước khi dùng,
nên một manifest không thể ghi hay xóa ra ngoài cây. Xem [[Engine]] và
[[Security and Trust Model]].

## Nó có hoạt động trên KernelSU VÀ Magisk VÀ APatch không?

Có. VDLU là POSIX sh thuần cộng với một WebUI, được vendor vào module, nên nó chạy trên
KernelSU, APatch và Magisk như nhau. Nó dùng cầu nối WebUI của root manager
(`ksu.exec`) để điều khiển engine và thăm dò tiến trình. Xem [[Architecture]] và
[[WebUI]].

## Dấu chân trên thiết bị lớn cỡ nào?

Nhỏ. Engine là các script; các nhị phân duy nhất là bộ xác minh `ed25519-mini`
theo từng ABI (tí hon) và, cho một nguồn `https`, một `curl` tĩnh (~1MB) được
fetch một lần và cache. Một module đã bó sẵn `curl` của riêng nó sẽ tái sử dụng nó
và không thêm lần tải nào cả. Cache blob Tier-2 giữ nội dung đã xác minh cộng với
3 phiên bản rollback gần nhất. Xem [[Engine]] và [[Architecture]].
