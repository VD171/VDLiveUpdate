> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · Tiếng Việt · [中文](../zh/SECURITY.md)

---

# Chính sách bảo mật

VDLiveUpdate (VDLU) áp dụng các bản cập nhật flashless có quyền root cho một mô-đun đang
chạy: nó ghi vào thư mục riêng của mô-đun và hoán đổi một tệp `.so` Zygisk khi khởi động,
chạy trong ngữ cảnh root của mô-đun. Chúng tôi xem trọng vấn đề bảo mật.

## Báo cáo một lỗ hổng

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Hãy kèm theo mô tả rõ ràng và, nếu có thể, một manifest hoặc feed tái hiện được vấn đề.
Chúng tôi sẽ phản hồi sớm nhất có thể và ghi nhận bạn nếu bạn muốn.

## Ghi chú phạm vi

- Các bản cập nhật là các blob content-addressed cùng với một `manifest.json` được ký bằng
  ed25519. Thiết bị xác minh chữ ký bằng một `ed25519-mini` được nhúng (không có openssl
  trên thiết bị), và mỗi blob được kiểm tra so với `sha256` của nó trước khi được sử dụng.
- Hồ sơ hardened (mặc định công khai) yêu cầu một chữ ký hợp lệ và chặn downgrade. Phiên bản
  "khởi điểm" bị giới hạn dưới bởi `versionCode` của mô-đun đã cài đặt (đọc từ `module.prop`),
  nên một mô-đun không bao giờ bị đưa lùi lại phía sau feed.
- Gốc tin cậy (khóa công khai ed25519 thô trong `keyring/` và các tệp nhị phân trong
  `verify/`) là chỉ-flash và không bao giờ được xoay vòng qua mạng. Nhà sản xuất loại trừ nó
  khỏi feed và engine bỏ qua mọi đường dẫn `vdlu/` trong một kế hoạch đã tải về, nên một khóa
  ký bị rò rỉ không thể thay thế trình xác minh hoặc khóa và duy trì root.
- Một manifest được ký hợp lệ cho một mô-đun khác không thể ghi vào thư mục của một mô-đun
  khác. Trường `module` đã ký phải bằng với `MODID` trên thiết bị (kiểm tra ràng buộc giữa
  các mô-đun), và mọi thao tác ghi và xóa đều bị giới hạn trong thư mục mô-đun.
- Engine chạy trong ngữ cảnh root riêng của mô-đun và không bao giờ làm suy yếu nó. Nó không
  thêm đặc quyền nào và không nội suy bất kỳ trường manifest nào vào một shell, mọi giá trị
  `path`, `sha256`, `mode` và `delete[]` đều được xác thực như đầu vào thù địch trước khi sử
  dụng.
- Tư thế là fail-closed. Một giá trị `profile` bị hỏng hoặc không xác định không bao giờ lọt
  xuống chấp nhận nội dung chưa ký (bất cứ thứ gì không chính xác là `trusted` đều được xử lý
  như `hardened`), và một bản sao lưu được ghi trước khi bất kỳ tệp nào bị ghi đè, nên một
  apply thất bại không bao giờ phá hủy phiên bản đã cài đặt.
- Xem [TRUST-MODEL.md](TRUST-MODEL.md) để biết mô hình tin cậy đầy đủ, các bảo đảm fail-closed
  và chi tiết hardening.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến, xem [CONTRIBUTING.md](CONTRIBUTING.md)._
