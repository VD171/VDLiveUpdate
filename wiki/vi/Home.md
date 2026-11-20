# VDLiveUpdate (VDLU)

**VDLU là một engine tự cập nhật tăng dần, không cần flash, dành cho các module KernelSU / APatch / Magisk: một module đã cài đặt tự cập nhật các tệp của chính nó qua một feed đã ký, chỉ tải về phần thay đổi và áp dụng phần lớn mà không cần khởi động lại.**

Một bản cập nhật module thông thường sẽ gửi lại toàn bộ `.zip`, nên chỉ vài dòng thay đổi cũng tốn một lần tải lại đầy đủ, và một manifest cập nhật tĩnh chỉ có thể trỏ đến một `zipUrl` duy nhất (một phiên bản cho mọi thiết bị). VDLU đi theo hướng khác: nó so sánh (diff) cây tệp thực sự đang được cài đặt với một feed đã ký, định địa chỉ theo nội dung, chỉ tải về phần chênh lệch (delta) và ghi chúng tại chỗ. Một bản cài arm64 full vẫn là arm64 full, một bản cài lite vẫn là lite, và module không bao giờ bị flash lại.

VDLU được thiết kế để **vendor** vào trong một module, đặt vào `<module>/vdlu/`. Nó không phải là một module riêng.

## Mục tiêu

- **Tự cập nhật không cần flash.** Cập nhật một module đã cài tại chỗ, qua mạng, không cần root manager, không flash lại `.zip`, và không mất phiên bản (flavor) đã cài.
- **Tăng dần theo nội dung.** Chỉ truyền những blob có nội dung thay đổi. Một feed định địa chỉ theo nội dung (`manifest.json` + `blobs/<sha256>`) có nghĩa là các tệp không đổi hoặc đã hoàn nguyên sẽ không bao giờ bị tải lại.
- **Không cần khởi động lại khi an toàn.** Áp dụng các tệp thông thường trực tiếp, ngay lập tức. Chỉ dành riêng một lần khởi động lại theo kiểu staged cho số ít tệp thực sự cần đến (một `.so`, một overlay `/system`, một `sepolicy.rule`).
- **Gọn nhẹ trên thiết bị.** Thuần POSIX `sh`, không `jq`, không `bash`, không `openssl` trên thiết bị. Việc xác minh dựa trên một `ed25519-mini` được nhúng sẵn; nhị phân duy nhất được tải về là một `curl` tĩnh, chỉ dùng cho các feed `https`.
- **Fail-closed và trung thực.** Mọi trường trong manifest đều được coi là đầu vào thù địch và được xác thực trước khi tải bất cứ thứ gì. Không bao giờ báo cáo "xong" trừ khi một lần băm lại (re-hash) chứng minh điều đó, và không có gì bị ghi đè mà không sao lưu trước.

## Điểm đặc biệt

Điều khiến VDLU khác với một client OTA thông thường:

- **Không cần flash và tăng dần.** Diff / fetch / apply định địa chỉ theo nội dung với khử trùng lặp (dedup): thiết bị tính toán delta so với feed đã ký và chỉ kéo về những blob còn thiếu.
- **Không cần khởi động lại khi có thể.** Các tệp thông thường áp dụng trực tiếp; chỉ các tệp `.so`, overlay `/system`, và `sepolicy.rule` mới được staged và hoán đổi trong một lần khởi động lại duy nhất. Xem [[Reboot Handling]].
- **POSIX `sh` trên thiết bị.** Chạy dưới toybox / busybox / mksh. Không `jq` (một bộ làm phẳng theo kiểu `gron` viết bằng `awk` sẽ phân tích JSON), không dùng cú pháp `bash`, không có runtime nặng.
- **Xác minh gọn nhẹ.** Một `ed25519-mini` được nhúng sẵn xác minh chữ ký. **Không có `openssl` trên thiết bị**; khóa riêng không bao giờ chạm vào thiết bị hay CI.
- **Bảo mật fail-closed.** `validate_plan()` từ chối **toàn bộ** manifest khi có bất kỳ trường lỗi nào (đường dẫn tuyệt đối hoặc `..`, một `sha256` không phải 64 ký tự hex, một mode / class / encoding không hợp lệ). Có hai profile, `trusted` và `hardened`, với `hardened` fail-closed bằng cách đảo ngược. Xem [[Security and Trust Model]].
- **Có thể tiếp tục và nguyên tử.** Một nhật ký (journal) khiến mọi giao dịch an toàn trước sự cố; việc ghi dùng `rename` / `mv`; một bản sao lưu được tạo trước bất kỳ lần ghi đè nào nên một lần áp dụng thất bại sẽ rollback thay vì làm hỏng module.

## Bắt đầu từ đây

| Nếu bạn muốn... | Đi tới |
|---|---|
| Đưa VDLU vào module của bạn, từng bước một | [[Quick Start]] |
| Hiểu toàn bộ hệ thống trong một cái nhìn tổng quan | [[Architecture]] |
| Tìm hiểu engine phía thiết bị (`update.sh`) | [[Engine]] |
| Xây dựng và ký một feed trên PC của bạn | [[Producer]] |
| Chèn vào bảng điều khiển Updates | [[WebUI]] |
| Đọc về mô hình tin cậy và thế trận an ninh | [[Security and Trust Model]] |
| Xem bố cục manifest và blob | [[Feed Format]] |
| Biết cái gì khởi động lại và tại sao | [[Reboot Handling]] |
| Hỏi một câu hỏi thường gặp | [[FAQ]] |
| Đóng góp | [[Contributing]] |

## Liên kết dự án

- **Mã nguồn:** https://github.com/VD171/VDLiveUpdate
- **Kênh (cập nhật):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate là một dự án độc lập, không chính thức. "Android" là thương hiệu của Google LLC; "KernelSU", "Magisk", và "APatch" là nhãn hiệu của các tác giả tương ứng. VDLU chạy hoàn toàn trên thiết bị của bạn và máy chủ phát hành của riêng bạn.
