# Contributing

Hoan nghênh các đóng góp. VDLU là một engine tự cập nhật tăng dần, không cần flash,
được vendor vào các module KernelSU / APatch / Magisk. Trang này là luồng làm việc dev
thực tế; để biết các mảnh ghép khớp với nhau thế nào, hãy đọc [[Architecture]], [[Engine]] và
[[Producer]] trước.

## Không có gì phải biên dịch

VDLU là các script (POSIX sh, một chút Python ở phía phát hành, vanilla JS cho
WebUI), nên không có bước build. Bạn xác minh một thay đổi bằng cách chạy pipeline
từ đầu đến cuối và bằng cách kiểm tra tĩnh từng mảnh.

## Hợp đồng đường nối trước tiên

Hợp đồng giao diện giữa các thành phần (các chữ ký CLI, các tên tệp và các
khóa JSON được chia sẻ bởi engine, producer và WebUI) là **luật hội tụ**.
Hãy coi nó là bất biến. Nếu thay đổi của bạn chạm vào đường nối producer-tới-engine
(schema manifest, schema journal, các khóa config, quy tắc chữ ký/chuẩn-tắc-hóa),
**căn chỉnh hợp đồng giao diện trước**, rồi thay đổi mã ở cả hai phía cho khớp.
Một thay đổi ở một phía của đường nối mà không có phía kia sẽ âm thầm phá những người áp dụng.
Xem [[Producer]] để biết quy tắc chuẩn tắc hóa mà bộ ký và bộ xác minh phải đồng thuận từng byte.

## Kiểm thử từ đầu đến cuối trước một PR

Chạy producer và engine cùng nhau trên một cây dùng-một-lần, theo đúng cách một
bản phát hành của người áp dụng làm:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Rồi kiểm tra tĩnh từng thành phần:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Và mở `webui/demo.html` trong một trình duyệt: nó giả lập cầu nối root-manager
(`ksu.exec`), nên bạn có thể vận hành bảng Updates, toast tiến trình, hủy
và biểu ngữ khởi động lại mà không cần thiết bị. Xem [[WebUI]].

## Nội quy

- **POSIX sh trên thiết bị.** Không dùng cú pháp bash ngoài `local`, và không `jq`. Nó phải
  chạy trên toybox / busybox.
- **Bảo mật là không thể thương lượng.** Mọi trường manifest là đầu vào thù địch;
  `validate_plan()` giữ fail-closed, và khóa ký riêng không bao giờ chạm vào
  CI hay một thiết bị. Đừng nới lỏng một lần kiểm tra để làm một bài test vượt qua.
- **Nghiêm ngặt khi thất bại.** Giữ cho giao dịch có thể tiếp tục: không có gì báo cáo "done"
  mà không có một lần băm lại khớp, không có gì bị ghi đè mà không có một lần sao lưu, và
  các lần apply giữ nguyên tử.
- **Luôn chất lượng phát hành.** Giữ các comment súc tích; không comment thừa thãi.
- **Một thay đổi logic cho mỗi PR.** Nói cái gì đã thay đổi và tại sao.

## Mở issue

Mở một issue mô tả bạn đã làm gì, bạn mong đợi gì, và điều gì đã xảy ra.
Với một lỗi, hãy kèm id module, profile nguồn (`hardened` hoặc `trusted`),
lệnh `update.sh` mà bạn đã chạy, và `journal.json` liên quan (nó ghi lại
pha, trạng thái và lỗi). Với một tính năng, hãy nói nó chạm vào thành phần nào (engine,
producer, hoặc WebUI) để tác động tới đường nối rõ ràng ngay từ đầu.
