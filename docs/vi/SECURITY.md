> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · Tiếng Việt · [中文](../zh/SECURITY.md)

---

# Chính sách bảo mật và mô hình tin cậy

VDLiveUpdate (VDLU) áp dụng **cập nhật root flashless** cho một module đang chạy: nó ghi vào
`/data/adb/modules/<mod>` và hoán đổi một `.so` của Zygisk lúc boot. Mọi trường của một manifest được tải về
(`path`, `sha256`, `delete[]`, `mode`, ...) đều là **đầu vào thù địch** - một feed bị đầu độc hoặc một MITM
chuyển nó đến. Trang này là mô hình tin cậy và chính sách công bố có trách nhiệm. Về hợp đồng seam đầy đủ, xem
[`INTERFACES.md`](INTERFACES.md), và nội bộ engine/producer trong [`ENGINE.md`](ENGINE.md) và
[`PRODUCER.md`](PRODUCER.md); trang wiki **Security-and-Trust-Model** mang cùng mô hình này cho người đọc bên
ngoài repo.

## Các phiên bản được hỗ trợ

Các bản vá bảo mật đáp xuống `ENGINE_VERSION` mới nhất; một manifest đã ký khai báo engine tối thiểu mà nó cần
qua `engine_min`, và engine trên thiết bị từ chối một manifest đòi hỏi nhiều hơn những gì nó hiện thực. Các
engine được vendor cũ hơn được kỳ vọng phải **re-vendor** để lấy một bản vá, chứ không được back-patch tại
chỗ.

| ENGINE_VERSION | trạng thái |
|---|---|
| 4 (hiện tại) | được hỗ trợ - allowlist `key_id`, từ chối path có dot-segment/trailing-slash, giới hạn kích thước, check-time lock |
| 3 | đã bị thay thế - `hardened` mặc định, `profile` fail-closed bằng phép đảo, ràng buộc module/MODID, chặn downgrade |
| <= 2 | không hỗ trợ - re-vendor engine hiện tại |

Bất kỳ thay đổi nào ở verify của engine hoặc logic apply đều tăng `ENGINE_VERSION`.

## Báo cáo một lỗ hổng

Báo cáo riêng tư. **Đừng** mở một issue, PR hay bài đăng diễn đàn công khai cho một lỗi bảo mật. Hãy dùng các
liên hệ của dự án (xem [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kênh: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Vui lòng kèm theo phiên bản engine, `profile` đang dùng, và một manifest hoặc feed tái hiện được vấn đề. Các
bản vá xuất xưởng dưới dạng một `ENGINE_VERSION` mới với một mục trong `CHANGELOG.md`; hãy phối hợp thời điểm
công bố trên luồng báo cáo.

## Mô hình tin cậy

- **Chữ ký ed25519 tách rời.** Producer ký manifest chuẩn trên PC (openssl); thiết bị xác minh bằng
  `ed25519-mini` nhúng - **không có openssl trên thiết bị**. Thông điệp được ký là sha256 hex của manifest khi
  bỏ trường `sig` của nó (khóa được sắp xếp, compact, UTF-8), nên sign và verify suy ra cùng các byte trên hai
  runtime mà không cần thư viện JSON trên thiết bị.
- **Keyring = các pubkey RAW 32 byte**, chỉ-flash. Keyring của thiết bị phát hành `<key_id>.pub` dưới dạng khóa
  thô 32 byte (không bao giờ là PEM); `vdlu-pack` **loại trừ** keyring và các nhị phân `verify/` khỏi feed, nên
  một manifest không bao giờ có thể ghi đè neo tin cậy trên thiết bị qua mạng.
- **Allowlist `key_id` cho module-update (fail-closed, trước khi chọn pubkey).** Một keyring có thể hợp pháp
  mang nhiều hơn một khóa (ví dụ một khóa fingerprint-feed tin cậy thấp hơn bên cạnh khóa release). Trước khi
  `<key_id>.pub` được chọn, `verify_manifest` từ chối bất kỳ manifest nào có `key_id` không nằm trong allowlist
  đã cấu hình, trong **cả hai** profiles, và phản chiếu tập đã giải quyết vào `vdlu-verify` qua
  `VDLU_KEYID_ALLOW`. Điều này đóng một bypass mà ở đó một khóa tin cậy thấp hơn bị rò rỉ lẽ ra có thể ký một
  bản cập nhật flashless root đầy đủ. An toàn mặc định khi `key_id` chưa đặt: một keyring **một khóa** tự động
  ghim vào khóa duy nhất đó; một keyring **nhiều khóa** bị từ chối cho đến khi `key_id` được ghim (phân tách
  bằng dấu phẩy để luân chuyển).
- **Gốc tin cậy fingerprint-feed là một path riêng, được ghim** với khóa riêng của nó; nó không bao giờ với tới
  được qua đường module-update ở trên.
- **Baseline là một hạt giống tin cậy cục bộ.** `baseline.json` đến bên trong zip đã flash - ranh giới tin cậy
  của việc cài - nên nó chưa ký và không khóa và **không** được chạy qua `vdlu-verify`; chỉ một manifest được
  **tải** từ feed mới được xác minh. Điều này giữ khóa ký ở ngoài CI.

## Các bảo đảm fail-closed

- **`validate_plan` chạy trước bất kỳ fetch hay apply nào.** Trong `do_diff`, fail-closed, nó từ chối **toàn
  bộ** manifest nếu bất kỳ `path` nào là tuyệt đối, chứa một segment `..` hoặc `.`, kết thúc bằng `/`, hoặc giữ
  một ký tự điều khiển; nếu bất kỳ `sha256` nào không khớp `^[0-9a-f]{64}$`; hoặc nếu bất kỳ `mode`/`class`/`enc`
  nào không hợp lệ. Không trường thù địch nào chạm tới một shell, và `cmd_check` không mang nội suy `system()`
  nào.
- **Chứa đựng path.** Mọi ghi và xóa đều bị giới hạn trong `MODULE_DIR` qua `contained()` - apply, delete, và
  `stage_file` lúc reboot đều qua cùng một bộ bảo vệ. Các symlink trong cây bị producer bỏ qua (không bao giờ
  rò rỉ nội dung từ bên ngoài nó).
- **Hai profiles, fail-closed bằng phép đảo.** `trusted` (riêng tư, nguồn được SSH-staged) là opt-in **duy
  nhất** vào verify best-effort; **bất kỳ** giá trị nào khác - bao gồm một lỗi gõ, một trailing space/CR, hoặc
  một kiểu chữ hoa thường khác - được xử lý như `hardened`, nơi một chữ ký hợp lệ là **bắt buộc** và một thất
  bại sẽ abort. `sha256` của mỗi blob được kiểm tra trong cả hai profiles.
- **Chữ ký + băm trước bất kỳ exec tool nào.** `curl` tĩnh được tải chạy với tư cách root, nên `install-tool`
  xác minh chữ ký của tools-manifest (ed25519-mini, bắt buộc trong **bất kỳ** profile nào) và băm của curl
  **trước khi** nó được cài và exec - sig+hash trước exec đóng lỗ RCE.
- **Giao dịch có thể tiếp tục, an toàn-pin.** Manifest đang bay được ghim trong `target.json`; một crash, mất
  mạng, hay reboot sẽ tiếp tục từ journal mà không quyết định lại kế hoạch. Downgrade bị chặn (`version` đơn
  điệu), trường `module` đã ký phải bằng `MODID`, và `delete[]` chỉ chạy tại `finalize_done` (một
  `PENDING_REBOOT` không xóa gì). Không gì từng "xong" mà không có một lần re-hash đầy đủ; không gì bị ghi đè mà
  không có một bản sao lưu `rollback/<v>/` trước.

## Gia cố (phòng thủ theo chiều sâu)

- **Giới hạn kích thước.** Manifest, tools-manifest, và đường tải không-curl `wget`/`head -c` đều bị giới hạn
  trước khi được đọc (chống-OOM / chống-flood). Một blob thất bại ở pha của nó sau 3 lần thử.
- **Check-time lock.** `check` lấy mkdir-lock trước khi dựng lại work dir của nó, nên một lần chạy đồng thời
  không thể đua với nó.
- **Chứa đựng staging.** `stage_file` có cùng bộ bảo vệ `contained()` như các primitive apply live, nên một
  path reboot-hard đã staging cũng không thể thoát khỏi `MODULE_DIR`.
- **TLS là phòng thủ theo chiều sâu, không phải gốc tin cậy.** curl tĩnh dùng mbedTLS với trust store của
  Android (`--capath`, ghi đè `ca_path`); bảo đảm toàn vẹn là chữ ký ed25519, việc kiểm cert là một lớp thứ
  hai.

## Xem thêm

- [`INTERFACES.md`](INTERFACES.md) - hợp đồng seam bất biến (§5 config, §6 signature, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - engine phía thiết bị và máy trạng thái của nó.
- [`PRODUCER.md`](PRODUCER.md) - đóng gói, ký, chuẩn hóa, và luân chuyển khóa.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
