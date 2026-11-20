# Feed Format

**Feed** là thứ VDLU phục vụ qua đường truyền và là thứ thiết bị cập nhật từ đó. Nó là một thư mục tĩnh thuần, có thể phục vụ bởi bất cứ thứ gì (GitHub Pages, một đích rsync, một đường dẫn `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Bản thân module cũng ship một tệp thêm, `baseline.json`, bên trong `.zip` (không được phục vụ từ feed). Producer dựng tất cả những thứ này được mô tả trong [[Producer]]; trang này là hợp đồng lúc-truyền.

---

## manifest.json

Manifest là mô tả đầy đủ của một bản phát hành: mọi tệp trong cây đích, cái gì cần xóa, và chữ ký trên toàn bộ.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Các trường

| Trường | Ý nghĩa |
|---|---|
| `schema` | Phiên bản định dạng của chính manifest (hiện là `1`). |
| `module` | Id module. Thiết bị từ chối manifest nếu nó không khớp với id module của chính nó, nên một feed được ký hợp lệ cho một module khác không thể được phục vụ thay thế. |
| `version` | Phiên bản dạng số nguyên. Engine chỉ cập nhật tiến tới; một feed cũ hơn thiết bị là một trạng thái "ahead" lành tính, không phải lỗi. |
| `version_name` | Chuỗi phiên bản dễ đọc cho người (ví dụ `v106`). |
| `built` | Dấu thời gian build ISO 8601. Tôn trọng `SOURCE_DATE_EPOCH` để tái lập. |
| `engine_min` | Phiên bản engine tối thiểu cần để áp dụng manifest này. |
| `channel` | Kênh phát hành (ví dụ `stable`). |
| `key_id` | Khóa nào trong keyring thiết bị đã ký manifest này. Chọn khóa công khai để xác minh. |
| `files[]` | Cây đích **đầy đủ** (không phải một diff). Mỗi mục: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Các đường dẫn có mặt trong bản phát hành trước nhưng giờ đã mất, để thiết bị gỡ bỏ. |
| `sig` | Chữ ký ed25519, base64. Xem việc chuẩn tắc hóa bên dưới. |

`files[]` mô tả **toàn bộ** cây, không phải một delta. Thiết bị tự tính delta bằng cách so sánh manifest với những gì nó đã có, và chỉ fetch những blob mà nó thiếu `sha256`. `sha256` luôn là của nội dung gốc (chưa nén); `enc` chỉ nói cách blob đó được lưu trong `blobs/`. Ý nghĩa của `class` và việc thiết bị làm với mỗi giá trị được trình bày trong [[Reboot Handling]].

---

## Chuẩn tắc hóa (các byte được ký)

Đây là bất biến quan trọng nhất trong định dạng. Bộ ký trên PC và bộ xác minh trên thiết bị chạy trên những runtime hoàn toàn khác nhau (openssl trên PC, toybox + một bộ xác minh nhúng tí hon trên thiết bị, và **không có thư viện JSON nào cả** trên thiết bị). Chúng vẫn phải rút ra chính xác cùng các byte để ký và để xác minh. Do đó quy tắc là một **phép biến đổi byte** có chủ đích, không phải một lần tuần tự hóa lại JSON.

**Bước 1: một dạng lưu trữ cố định.** `vdlu-pack` ghi `manifest.json` dạng gọn, với các khóa đã sắp xếp, UTF-8, luôn bao gồm `key_id` và `sig` (dưới dạng chuỗi rỗng cho đến khi được ký):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Bước 2: chỉ lột đi `sig`.** Dạng chuẩn tắc là chính xác văn bản đó với **chỉ trường `"sig"` bị gỡ bỏ**. Vì các khóa đã được sắp xếp, `sig` luôn xuất hiện dưới dạng `,"sig":"<value>",` được kẹp bởi `"schema"` trước nó và `"version"` sau nó (cả hai luôn có mặt), nên gỡ bỏ nó để lại văn bản đúng cú pháp. JSON escape mọi `"` bên trong một giá trị chuỗi thành `\"`, nên token cấu trúc `"sig":"` là không mập mờ ngay cả so với một tên tệp chứa theo nghĩa đen `"sig":"`.

Việc gỡ bỏ là một nhúm các phép mở rộng tham số POSIX, giống hệt nhau ở bộ ký và bộ xác minh, không có `sed` và không có `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Bước 3: ký hash của cái đó.** Thông điệp được ký/xác minh là **sha256 hex** (64 ký tự ASCII, không newline) của dạng chuẩn tắc. ed25519 ký hex đó.

Hai hệ quả tự nhiên nảy ra từ điều này theo cấu trúc:

- `key_id` là một phần của dạng chuẩn tắc (chỉ `sig` bị lột đi). `vdlu-sign` đặt `key_id` **trước khi** băm, nên danh tính khóa được chữ ký bao phủ.
- Dù chỗ giữ chỗ `sig` là rỗng (`"sig":""`, lúc ký) hay đã được điền (lúc xác minh), việc lột nó đi cho ra các byte chuẩn tắc giống hệt nhau. Việc ký và việc xác minh đồng thuận tự động.

Hai công cụ POSIX sh là thẩm quyền. Một phiên bản tương đương bằng Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` rồi sha256, chỉ tồn tại để đối chiếu chéo chúng.

Lý luận về tin cậy quanh tất cả những điều này (tại sao việc xác minh ở trên thiết bị, cách `hardened` fail-closed) nằm trong [[Security and Trust Model]].

---

## baseline.json (mầm cài đặt)

Khi một module vừa được cài mới, nó nên đã "current" cho chính phiên bản nó ship, không có lần tự cập nhật thừa cho phiên bản nó vừa cài. Đó là việc mà `baseline.json` làm.

`baseline.json` ship **bên trong zip của module** (tại `vdlu/baseline.json`), không phải trên feed. Ở một bản cài mới, engine gieo mầm bản ghi "active version" của nó từ đó, nên thiết bị ra đời đã current, không có `from:0` và không có lần fetch lại thứ nó đã có.

Các thuộc tính chính:

- Nó là một **bản sao không khóa của manifest đã ký** cho phiên bản được ship: cùng đầu ra của `vdlu-pack`, để chưa ký (`key_id` và `sig` giữ rỗng).
- Nó **không được xác minh**. Engine coi nó như một mầm tin cậy cục bộ vì nó đến bên trong zip đã flash, chính là ranh giới tin cậy khi cài. Chỉ một manifest *được fetch từ feed* mới đi qua việc xác minh chữ ký.
- Vì nó không cần chữ ký, **CI có thể tạo nó không khóa**, chính điều đó giữ cho khóa ký hoàn toàn nằm ngoài CI (xem [[Producer]]).
- `vdlu-pack` **loại trừ `baseline.json` khỏi manifest của chính nó**, nên manifest không bao giờ tham chiếu baseline (điều đó sẽ là một vòng lặp tự tham chiếu: manifest tới baseline tới manifest).
- Nó **không gây tử vong nếu vắng mặt**. Không có nó, thiết bị đơn giản bắt đầu từ `from:0` ở lần cập nhật đầu tiên và fetch những gì nó cần. Không bao giờ hỏng, chỉ là kém tối ưu hơn.

---

## Blobs

Mỗi nội dung tệp khác biệt là một blob dưới `blobs/`, được đặt tên theo **sha256 của nội dung gốc**:

- `blobs/<sha256>` cho một blob thô.
- `blobs/<sha256>.gz` cho một blob đã gzip (gzip chỉ được giữ khi tệp lớn ít nhất 4096 byte và việc nén tiết kiệm được ít nhất 10 phần trăm).

Một blob được lưu một lần, ở một định dạng. Việc định địa chỉ theo nội dung cho khử trùng lặp miễn phí: nội dung không đổi, dùng chung hoặc đã hoàn nguyên ánh xạ tới một blob đã tồn tại, nên feed chỉ phình lên bởi nội dung thực sự mới, và thiết bị chỉ tải những hash mà nó thiếu. Thiết bị kiểm tra `sha256` của mọi blob đã tải so với manifest (sau khi giải nén một blob `gz`) trước khi dùng nó.

---

## Cái gì bị loại trừ khỏi feed, và tại sao

Feed chỉ mang **nội dung của riêng module**. Một tập hợp đường dẫn cố định được giữ ngoài nó một cách có chủ đích. `vdlu-pack` áp dụng một vị từ (predicate) loại trừ cả khi duyệt cây lẫn khi tính `delete[]`.

| Bị loại trừ | Tại sao |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (trust root: các khóa công khai thô + nhị phân bộ xác minh) | **Đây là lý do bảo mật cốt lõi.** Mỏ neo tin cậy (trust anchor) là **chỉ-qua-flash**. Nếu keyring hoặc bộ xác minh có thể được giao qua feed, một manifest có thể ghi đè chính thứ xác thực nó. Giữ chúng ngoài đường truyền nghĩa là một manifest không bao giờ có thể viết lại mỏ neo tin cậy trên thiết bị. |
| `vdlu/baseline.json` | Nó là một bản sao của manifest đã ký (mầm cài đặt); pack nó sẽ là một vòng lặp tự tham chiếu. |
| hạ tầng flash `.vd/` | Giàn giáo flash-gate được ship trong zip, không bao giờ áp dụng live. |
| `update.json`, `update-mmrl.json` | Kích thước/sha của chúng được CI điền *sau khi* các zip được dựng, nên bản sao được ship khác với bất kỳ bản sao feed nào. Feed chúng sẽ gây một lần fetch một-tệp bóng ma ở mỗi lần tự cập nhật đầu tiên của mỗi bản cài, và dù sao chúng cũng là vết tích trên thiết bị (manager đọc JSON cập nhật thô từ xa). |
| `META-INF/`, `customize.sh` (giàn giáo installer) | Được manager tiêu thụ lúc **flash** và không được giữ trong module đã cài. Chúng không phải nội dung VDLU; phục vụ chúng lãng phí các blob và, nếu một cái từng thay đổi giữa các phiên bản, nó sẽ bị ghi như một tệp installer vào thư mục module đang sống. |
| Các tệp bạn đồng hành `.sha256` theo từng tệp | Chúng chỉ thuộc về zip có thể flash, trở nên lỗi thời sau một bản cập nhật tăng dần, và sẽ làm manifest gấp đôi. |
| Các tệp dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Không bao giờ được ship tới thiết bị; phục vụ chúng lãng phí các blob và làm xáo trộn manifest đã ký ở mỗi lần sửa doc. |

Lý luận đằng sau việc loại trừ trust-root được mở rộng trong [[Security and Trust Model]].

---

## Ngữ nghĩa delete[]

`delete[]` nói cho thiết bị biết các đường dẫn nào cần gỡ bỏ, để một tệp bị bỏ đi giữa các bản phát hành không nấn ná trên thiết bị như một thứ mồ côi. Nó được tính bằng cách truyền `--prev <previous manifest.json>` cho `vdlu-pack`: một đường dẫn có trong bản phát hành trước và không có trong bản hiện tại trở thành một mục delete.

Quy tắc quan trọng: **các đường dẫn bị loại trừ không bao giờ được phát ra như các lần xóa, ngay cả với `--prev`.** Mọi đường dẫn trước đó đều được chạy qua cùng vị từ loại trừ dùng khi duyệt cây. Nếu một `--prev` trỏ vào một manifest cũ hơn vẫn còn liệt kê các đường dẫn giờ bị loại trừ (một `baseline.json` lạc, `META-INF/*`, một mục keyring, và v.v.), những đường dẫn đó **không** bị biến thành các mục delete. Một đường dẫn bị loại trừ chưa bao giờ là nội dung feed, nên nó không phải việc của VDLU để xóa, và thiết bị không bao giờ bị ra lệnh gỡ bỏ một tệp không được phục vụ qua feed. Đây là điều giữ cho danh sách loại trừ không bao giờ quay ngược lại như một chỉ thị phá hoại.
