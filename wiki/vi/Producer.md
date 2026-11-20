# Producer

**Producer** là phía PC / phát hành của VDLU: tập hợp nhỏ các công cụ biến một cây module đã hoàn thiện thành một feed đã ký, định địa chỉ theo nội dung mà thiết bị có thể cập nhật từ đó. Không có gì ở đây chạy trên điện thoại. Các công cụ này chạy trên máy phát hành của bạn (hoặc, với những phần an toàn để làm vậy, trong CI).

Có bốn công cụ:

| Công cụ | Chạy trên | Ngôn ngữ | Nhiệm vụ |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Duyệt cây module cuối cùng thành `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Tạo một cặp khóa ký ed25519 |
| `vdlu-sign` | PC | sh + openssl | Chèn `key_id` + chữ ký vào một manifest, tại chỗ |
| `vdlu-gc` | PC | python3 | Dọn các blob mồ côi khỏi một feed đã xuất bản (fail-safe) |

Luồng phát hành gồm ba bước, làm một lần cho mỗi bản phát hành: **pack, rồi sign, rồi publish**. `vdlu-keygen` là một thiết lập một lần, và `vdlu-gc` là việc dọn dẹp bạn chạy khi feed phình lên. Mọi thứ producer phát ra đều tuân theo [[Feed Format]], vốn là thứ engine trên thiết bị tiêu thụ.

---

## vdlu-pack

`vdlu-pack` nhận **đúng cây mà `.zip` của bạn ship** (cây cuối cùng, sau khi bản build của bạn đã áp dụng whitelist và cắt ABI của riêng nó) và tạo ra feed cho nó.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Nó ghi hai thứ vào `<out_dir>`:

- `manifest.json` - mô tả đầy đủ của cây đích (mỗi tệp với `sha256`, `size`, `mode`, encoding và lớp reboot của nó), vẫn **chưa ký** (các trường `key_id` và `sig` là các chỗ giữ chỗ rỗng).
- `blobs/<sha256>` (hoặc `blobs/<sha256>.gz`) - một blob cho mỗi nội dung tệp khác biệt.

### Định địa chỉ theo nội dung và khử trùng lặp

Mỗi blob được đặt tên theo **sha256 của nội dung gốc (chưa nén) của nó**. Vì cái tên chính là hash, nội dung giống hệt nhau sẽ đáp vào cùng một blob. `vdlu-pack` chỉ ghi một blob nếu nó chưa có mặt, nên:

- Một tệp không thay đổi giữ nguyên tên blob, và không bao giờ bị ghi lại hay đẩy lại.
- Hai tệp khác nhau có nội dung giống hệt nhau dùng chung một blob.
- Một tệp đã hoàn nguyên tái sử dụng blob đã có từ trước.

Do đó việc xuất bản là **tăng dần theo cấu trúc**: xuyên các bản phát hành, `blobs/` chỉ bao giờ phình lên, và chỉ nội dung thực sự mới mới được thêm vào. Thiết bị fetch theo cùng các hash đó, nên nó chỉ tải những blob mà nó chưa có.

### Nén (trường `enc`)

Với mỗi tệp, `vdlu-pack` quyết định cách lưu blob:

- `gz` khi tệp lớn ít nhất 4096 byte **và** gzip (`-9 -n` tất định) tiết kiệm được ít nhất 10 phần trăm.
- `raw` nếu không (các tệp nhỏ mà gzip lúc truyền đã bao phủ, hoặc dữ liệu vốn đã không nén được).
- Nếu `gzip` không có trên máy build, mọi thứ được lưu `raw`. Việc pack không bao giờ thất bại vì chuyện này.

`sha256` trong manifest **luôn** là của nội dung gốc; `enc` chỉ đặt tên cách blob tình cờ được lưu. Thiết bị giải nén các blob `gz` bằng toybox `gunzip` rồi kiểm tra hash so với bản gốc.

### Lớp reboot và an toàn

`vdlu-pack` cũng gắn thẻ mỗi tệp với một `class` reboot (`live`, `soft`, `reboot`) suy ra từ đường dẫn của nó, nên engine biết cái gì có thể áp dụng mà không cần khởi động lại và cái gì phải được staged. Các quy tắc và việc thiết bị làm với mỗi lớp được trình bày trong [[Reboot Handling]].

Một vài điều mà `vdlu-pack` cố ý **không** làm:

- Nó không theo các symlink (nó bỏ qua chúng kèm một cảnh báo, nên nội dung từ bên ngoài cây, như một liên kết tới một tệp hệ thống, không bao giờ có thể rò rỉ vào một blob).
- Nó bỏ qua các tệp không thông thường (thư mục, fifo, thiết bị).
- Nó tôn trọng `SOURCE_DATE_EPOCH` cho dấu thời gian `built`, nên các manifest có thể tái lập.
- Nó loại trừ hoàn toàn một tập hợp đường dẫn cố định khỏi feed (trust root, giàn giáo installer, và một vài thứ khác). Danh sách đầy đủ, và lý do tại sao mỗi thứ bị loại trừ, nằm trong [[Feed Format]].

### Danh sách `delete[]`

Truyền `--prev <previous manifest.json>` và `vdlu-pack` tính `delete[]`: các đường dẫn tồn tại trong bản phát hành trước nhưng đã biến mất trong bản này, nên thiết bị gỡ bỏ chúng thay vì để lại các tệp mồ côi phía sau. Các đường dẫn bị loại trừ không bao giờ được phát ra như các lần xóa, ngay cả khi chúng xuất hiện trong manifest trước (xem [[Feed Format]] để biết ngữ nghĩa chính xác).

---

## vdlu-keygen

Một bước một lần. `vdlu-keygen` tạo cặp khóa ký ed25519 cho feed của bạn.

```sh
vdlu-keygen <id> <out_dir>
```

Nó ghi ba tệp:

| Tệp | Nó là gì | Nó đi về đâu |
|---|---|---|
| `<id>.pem` | Khóa ký **riêng** (mode `0600`) | Ở lại trên máy phát hành của bạn. Không bao giờ. |
| `<id>.pub` | Khóa công khai dạng PEM | Chỉ công cụ phía PC |
| `<id>.pub.raw` | Khóa công khai dạng **thô 32 byte** | Được ship làm mục keyring trên thiết bị của module |

Khóa công khai thô 32 byte là thứ bộ xác minh trên thiết bị đọc (nó không mang theo `openssl`, nên nó không thể đọc PEM). Bạn nhúng `<id>.pub.raw` vào module dưới dạng `vdlu/keyring/<id>.pub`. PEM chỉ để dùng phía PC. Sự phân tách này, và cách luân chuyển khóa (key rotation) hoạt động, được giải thích trong [[Security and Trust Model]].

> **Một keyring nhiều khóa phải ghim `key_id`.** Nếu keyring của module ship nhiều hơn một khóa (ví dụ khóa release cộng với một khóa feed fingerprint có độ tin cậy thấp hơn), engine sẽ không đoán khóa nào có thể ký một cập nhật module. Đặt cấu hình `key_id` thành khóa, hoặc các khóa phân tách bằng dấu phẩy trong một cửa sổ luân chuyển, được phép ký các bản cập nhật; một keyring một khóa tự động ghim và không cần cấu hình. Đây là danh sách cho phép cập nhật module, được trình bày trong [[Security and Trust Model]].

> `.pem` riêng là bí mật duy nhất trong cả hệ thống. Giữ nó khỏi mọi thiết bị và khỏi mọi lần push repository. Xem ghi chú về CI bên dưới.

---

## vdlu-sign

`vdlu-sign` nhận manifest chưa ký mà `vdlu-pack` tạo ra và ký nó **tại chỗ**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Nó đặt trường `key_id`, tính dạng chuẩn tắc của manifest, và ghi chữ ký ed25519 (base64) vào trường `sig`. Chữ ký là trên một phép biến đổi byte chính xác của manifest sao cho PC và thiết bị rút ra đúng cùng các byte đã ký mà không cần thư viện JSON nào trên thiết bị. Phép biến đổi đó (**việc chuẩn tắc hóa**) là bất biến quan trọng nhất trong định dạng, và nó được ghi lại đầy đủ trong [[Feed Format]].

Khóa riêng chỉ được đọc ở đây, trên máy của bạn, và không bao giờ rời khỏi nó.

### Khóa ký nằm ngoài CI

Đây là một điểm thiết kế có chủ đích. CI có thể chạy `vdlu-pack` và tạo ra một **baseline không khóa** hoàn toàn hợp lệ (một manifest mầm chưa ký; xem [[Feed Format]]), nên một bản cài mới ra đời đã current mà CI không bao giờ chạm vào một khóa riêng. Việc ký thực sự của feed đã xuất bản được làm bởi bạn, cục bộ, bằng `vdlu-sign`. Bằng cách đó khóa ký nằm 100 phần trăm ngoài CI, và chỉ feed mà bạn xuất bản bằng tay mới được ký.

---

## vdlu-gc

Vì các blob được định địa chỉ theo nội dung và bất biến, `blobs/` chỉ bao giờ phình lên: `vdlu-pack` thêm vào, nó không bao giờ gỡ bỏ. Qua nhiều bản phát hành, feed (và trang Pages lưu trữ nó) tích lũy các blob mà không manifest hiện tại nào còn tham chiếu. `vdlu-gc` dọn những thứ mồ côi đó.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Nó dựng **tập hợp được giữ lại** của các manifest: `manifest.json` hiện tại, cộng với `N` manifest lưu trữ gần nhất theo phiên bản (mặc định `N=3`, cho một biên rollback), cộng với bất kỳ cái nào bạn nêu tên với `--keep`. Một blob được **không** manifest giữ lại nào tham chiếu là một thứ mồ côi và là ứng viên để gỡ bỏ. Tập hợp được giữ lại là một hợp (union), nên một blob ở lại chừng nào bất kỳ bản phát hành được giữ lại nào còn cần nó; một thiết bị đang nằm ở một phiên bản được giữ lại cũ hơn không bao giờ mất lần fetch của nó.

`vdlu-gc` được xây dựng để an toàn:

- **Chạy thử (dry-run) theo mặc định.** Không có `--apply`, nó chỉ in ra những gì nó *sẽ* gỡ bỏ. Bạn thêm `--apply` để thực sự xóa.
- **Fail-safe.** Nếu nó không tìm thấy manifest được giữ lại nào cả, nó từ chối dọn thay vì liều làm rỗng một feed.
- **Giữ lại theo tham chiếu, không theo ngày.** Một blob được giữ vì một manifest được giữ lại trỏ đến nó, không bao giờ vì một dấu thời gian.

Sau khi dọn, push feed nhỏ hơn lên host của bạn. Giãn các lần ghi ra nếu host của bạn giới hạn tốc độ các lần ghi theo lô.

---

## Ghép lại với nhau

Một bản phát hành điển hình, từ đầu đến cuối:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Để xem ví dụ thực hiện đầy đủ về việc đưa VDLU vào một module, xem [[Quick Start]]. Để biết hình dạng lúc truyền của mọi thứ producer phát ra, xem [[Feed Format]]. Để biết lý do đằng sau việc xử lý khóa và những gì được giữ ngoài feed, xem [[Security and Trust Model]].
