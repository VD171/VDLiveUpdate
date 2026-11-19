> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · Tiếng Việt · [中文](../zh/PRODUCER.md)

---

# VDLU producer + lớp ký

Xây dựng việc phân phối content-addressed (manifest + blob) cho một module và ký nó.
Tuân theo [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| công cụ | chạy trên | ngôn ngữ | nhiệm vụ |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | duyệt cây module cuối cùng -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | cặp khóa ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B cho keyring gọn) |
| `producer/vdlu-sign` | PC | sh + openssl | chèn `key_id` + `sig` vào một manifest, tại chỗ |
| `engine/vdlu-verify` | **thiết bị** | sh + ed25519-mini | xác minh `sig` qua ed25519-mini nhúng; keyring = khóa công khai RAW 32B (KHÔNG openssl trên thiết bị) |

## Pipeline

```sh
# 1. một lần: một khóa ký. Giữ .pem tránh xa mọi thiết bị và tránh mọi lần push repo.
producer/vdlu-keygen release-2026 ./keys

# 2. mỗi release: đóng gói cây cuối cùng (cùng cây mà .zip phát hành, sau whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = các path đã mất kể từ prev

# 3. ký manifest tại chỗ.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. xuất bản ./out/{manifest.json,blobs/} tới <source> (Pages batch cho public; rsync cho private).
#    Keyring gọn của thiết bị giữ ./keys/release-2026.pub.raw dưới dạng keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` là content-addressed và khử trùng lặp: một blob có `<sha256>` đã tồn tại không được
ghi lại, nên việc xuất bản là tăng tiến và nội dung không đổi / đã hoàn nguyên không bao giờ được push lại.

### Quyết định `enc` (vdlu-pack)

`sha256` **luôn luôn** của nội dung gốc (chưa nén); `enc` chỉ đặt tên cho cách blob được lưu.

- `gz` khi `size >= 4096` **và** gzip (`-9 -n`, xác định) tiết kiệm ít nhất 10% (`comp <= raw*0.90`).
- `raw` nếu không (văn bản nhỏ mà HTTP gzip đã bao phủ, hoặc dữ liệu vốn-không-nén-được).
- gzip thiếu trên host build -> mọi thứ `raw` (không bao giờ thất bại).

Một blob được lưu một lần, trong một định dạng: `blobs/<sha256>` (raw) hoặc `blobs/<sha256>.gz` (gz). Thiết bị
giải nén với toybox `gunzip` (luôn hiện diện), nên không đóng gói zstd.

### Quyết định `class` (vdlu-pack) - phân loại reboot

Suy ra từ path (INTERFACES §3, doc §4). Chỉ là mặc định; một quy tắc path không bao giờ hạ cấp `reboot`->`live`.

| class | khớp bởi | áp dụng |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | staging `.vdlu-new`, hoán đổi lúc khởi động |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh` ở gốc | ghi live, chạy lần khởi động kế tiếp |
| `live` | mọi thứ khác (webroot, bin, lib, confs, module.prop, ...) | ghi live, nguyên tử |

Symlink **không được theo** (không bao giờ rò rỉ nội dung từ bên ngoài cây, ví dụ một liên kết tới
`/etc/shadow`) và bị bỏ qua với một cảnh báo, vì schema manifest không có kiểu symlink.
Các tệp không-thường (thư mục, fifo, thiết bị) bị bỏ qua. `built` tôn trọng `SOURCE_DATE_EPOCH` cho
các manifest tái lập được.

### Baseline (hạt giống cài đặt) - chưa ký, không khóa

`baseline.json` (phát hành tại `vdlu/baseline.json` trong zip module) gieo `current.json` trên một lần cài mới
để thiết bị sinh ra "đã cập nhật" (không from:0, không tải lại). Engine coi nó như một **hạt giống tin cậy cục bộ**
(nó đến trong zip đã flash, vốn là ranh giới tin cậy của việc cài) và **KHÔNG xác minh chữ ký của nó** -
chỉ manifest ĐƯỢC TẢI từ feed mới đi qua `vdlu-verify`. Vậy baseline không cần **khóa nào**: nó
chỉ là đầu ra `vdlu-pack` trên cây phát hành (chưa ký; `sig`/`key_id` vẫn rỗng). Một CI do đó có thể
sinh nó **không khóa**, giữ khóa ký 100% ngoài CI - chỉ FEED đã xuất bản mới được ký (người vận hành,
cục bộ). `vdlu-pack` loại trừ `baseline.json` khỏi manifest của chính nó (chống tự-tham-chiếu). Không nghiêm trọng nếu
vắng mặt: thiết bị chỉ bắt đầu from:0 ở lần cập nhật đầu tiên, không bao giờ hỏng.

## Chuẩn hóa (điểm hội tụ)

`vdlu-sign` và `engine/vdlu-verify` phải suy ra **cùng các byte** từ một manifest, trên hai
runtime khác nhau (PC openssl so với device toybox + openssl). Quy tắc cố ý là một phép biến đổi byte,
chứ không phải một lần tái-serialize JSON, nên nó không cần thư viện JSON trên thiết bị:

1. `vdlu-pack` ghi `manifest.json` **gọn, khóa được sắp xếp, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), luôn bao gồm
   các trường `key_id` và `sig` (chuỗi rỗng giữ chỗ cho đến khi ký). Đây là dạng lưu trữ
   chuẩn.
2. **Dạng chuẩn = văn bản đó với trường `"sig"` bị gỡ bỏ.** Vì khóa được sắp xếp, `sig`
   luôn xuất hiện dưới dạng `,"sig":"<value>",` được kẹp giữa `"schema"` (trước) và `"version"` (sau),
   cả hai luôn hiện diện. Gỡ nó để lại `...,"schema":N,"version":...` đúng cú pháp.
   JSON escape mọi `"` bên trong giá trị chuỗi thành `\"`, nên token cấu trúc `"sig":"` là
   không mơ hồ ngay cả với một tên tệp chứa đúng `"sig":"` (đã kiểm thử).
3. Thông điệp được ký/xác minh là **sha256 hex** (64 ký tự ASCII, không newline) của dạng
   chuẩn. ed25519 trên hex đó (`openssl pkeyutl -sign/-verify -rawin`).

Việc gỡ bỏ trong POSIX sh (cùng một hàm trong cả hai công cụ, không `sed`/`jq`):

```sh
# $1 = toàn bộ văn bản manifest (newline cuối đã bị tước bởi $(cat ...))
_pre=${_c%%\"sig\":\"*}     # cho tới  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # sau "sig":"
_tail=${_rest#*\",}          # sau <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` là một phần của dạng chuẩn (chỉ `sig` bị tước); `vdlu-sign` đặt `key_id` **trước khi**
băm. Giá trị giữ chỗ là rỗng (`"sig":""`, lúc ký) hoặc đã điền (lúc xác minh) đều cho
các byte chuẩn giống hệt nhau, nên sign và verify đồng thuận theo thiết kế.

Python tái tạo nó như `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` rồi sha256 - chỉ dùng
để kiểm tra chéo; hai công cụ sh mới là bên tạo có thẩm quyền.

## Chữ ký (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  cho ký/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER là một tiền tố 12 byte + khóa 32 byte, nên `tail -c 32` CHÍNH LÀ khóa). Nó phát ra CẢ HAI.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` trên sha256 hex chuẩn; chữ ký lưu base64.
- `vdlu-verify` (**thiết bị, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - đọc keyring như khóa công khai **RAW 32B**,
  KHÔNG openssl trên thiết bị. `key_id` được làm sạch theo path (không `/`, `.`, `..`, `"`). 🚨 Keyring phát hành
  **`.pub.raw` (32B)**, không bao giờ `.pub` PEM (113B): PEM chỉ dành cho PC và `ed25519-mini` không thể đọc nó.

Mô hình tin cậy (INTERFACES §6, doc §11/§13): `profile=hardened` (public) làm verify bắt buộc - một
chữ ký thất bại hoặc thiếu sẽ hủy bỏ cập nhật. `profile=trusted` (private, nguồn SSH-staged) coi
verify là best-effort, nhưng sha256 của mỗi blob vẫn được kiểm tra bất kể.

## Keyring + luân chuyển

Keyring là một thư mục các tệp `<key_id>.pub`, mỗi tệp là khóa công khai ed25519 **RAW 32B** (từ `.pub.raw`
của `keygen`), KHÔNG phải PEM - `ed25519-mini` đọc 32 byte thô. Phát hành khóa công khai thô hiện tại **và** trước đó
(doc §13) để một khóa đã luân chuyển không làm hỏng các bản cài cũ hơn. `vdlu-sign` với `key_id` mới và thiết bị
chọn `<keyring>/<key_id>.pub` (thô) là toàn bộ cơ chế luân chuyển - không đổi engine. Keyring là
**ổn định** qua các release (chỉ luân chuyển khóa mới đổi nó): một lần re-vendor phải **xác minh-không-sao-chép** nó, và không bao giờ
ghi đè nó bằng `.pub` PEM phía PC.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
