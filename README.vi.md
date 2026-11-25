<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** là một engine tự cập nhật tăng dần, flashless cho các mô-đun **KernelSU / APatch / Magisk**. Một mô-đun đã cài tự cập nhật chính nó bằng cách tải **chỉ những tệp đã thay đổi** (các blob được định địa chỉ theo nội dung + một manifest đã ký), áp dụng những tệp "sống" **mà không cần khởi động lại**, đồng thời dàn sẵn và đánh dấu một vài tệp thật sự cần khởi động lại (một `.so`, một overlay `/system`, một `sepolicy.rule`). Không cần trình quản lý root, không tải lại toàn bộ `.zip`, không khởi động lại trừ những tệp đã dàn sẵn đó.

Nó được thiết kế để **vendored** vào trong một mô-đun (đặt vào `<module>/vdlu/`), chứ không phải chạy như một mô-đun độc lập.

## Tại sao

Một bản cập nhật mô-đun thông thường gửi lại toàn bộ `.zip`. Với một mô-đun lớn, điều đó nghĩa là tải lại một lượng lớn chỉ để đổi vài dòng, và một manifest cập nhật tĩnh chỉ có thể trỏ tới một `zipUrl`, nên nó không thể phục vụ đúng flavor (ABI, full vs lite) mà thiết bị thực sự có. VDLU so sánh cây đã **cài** với một feed đã ký và chỉ tải phần delta, nên một bản cài arm64-full vẫn là arm64-full, một bản cài lite vẫn là lite, và hầu hết bản cập nhật đều áp dụng khi đang chạy.

## Cách hoạt động

- **Producer (PC / bản phát hành):** `vdlu-pack` biến một cây mô-đun thành một feed được định địa chỉ theo nội dung (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` cắt tỉa các blob mồ côi theo tham chiếu tới N manifest gần nhất (fail-safe, mặc định dry-run).
- **Engine (thiết bị):** POSIX sh, không `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) chạy DIFF -> FETCH -> APPLY -> COMMIT như một **giao dịch có thể tiếp tục** (nhật ký), với rollback và một khóa `mkdir`. Chữ ký được xác minh bằng `ed25519-mini` nhúng sẵn (không `openssl` trên thiết bị).
- **WebUI:** một bảng Updates cắm-là-chạy (thông báo tiến trình, hủy, banner khởi động lại), JS thuần.

## Hồ sơ (Profiles)

- `trusted`: dùng riêng tư, nguồn `file://` hoặc SSH, xác minh theo khả năng (luôn có hash).
- `hardened`: dùng công khai, **bắt buộc chữ ký**, chặn hạ cấp phiên bản. Manifest **gắn với id của mô-đun**, và mọi trường đều được kiểm tra fail-closed trước khi bất cứ thứ gì được tải về.

## Áp dụng vào mô-đun của bạn

Vendor `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` vào `<module>/vdlu/`, nhúng **khóa công khai 32-byte thô** của bạn thành `vdlu/keyring/<id>.pub`, thêm một `config` (profile + nguồn), nối dây các trigger (`post-fs-data.sh` pre-zygote để tự cập nhật khi khởi động; một trigger khi mở WebUI), và thêm `vdlu-pack` + `vdlu-sign` vào quy trình phát hành của bạn. Xem [`docs/QUICKSTART.md`](docs/QUICKSTART.md) để có một mẫu hoàn chỉnh.

## Bảo mật

- **Mọi trường của manifest đều là đầu vào thù địch.** `validate_plan()` từ chối toàn bộ manifest theo kiểu fail-closed nếu có đường dẫn tuyệt đối hoặc `..`, một `sha256` không phải 64 ký tự hex, hoặc một mode / class / encoding không hợp lệ, **trước** bất kỳ thao tác fetch hay apply nào.
- **Khóa ký riêng không bao giờ chạm vào CI hay thiết bị**; chỉ khóa công khai thô được nhúng, và việc xác minh dùng `ed25519-mini`, không phải `openssl`.
- `hardened` là fail-closed theo phép đảo: bất cứ thứ gì khác với chuỗi `trusted` nguyên văn đều được coi là `hardened`, nên một giá trị profile bị hỏng không bao giờ có thể âm thầm chấp nhận một manifest chưa ký.
- Các tệp thuộc lớp reboot (`.so`, overlay `/system`, `sepolicy.rule`) được **dàn sẵn, không bao giờ ghi đè lên một inode đang sống**; mọi thứ khác áp dụng khi đang chạy. Một thao tác apply thất bại sẽ hủy bỏ thay vì ghi đè mà không có bản sao lưu.

## Dựng / kiểm thử

Nó là script, không có gì để biên dịch. Đầu-cuối (producer + engine cùng nhau):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, và mở `webui/demo.html` trong trình duyệt (nó giả lập cầu nối tới thiết bị).

## Tài liệu

- [`INTERFACES.md`](docs/INTERFACES.md): hợp đồng đường nối giữa các thành phần (luật hội tụ; hãy coi nó là bất biến).
- [`ENGINE.md`](docs/ENGINE.md): engine phía thiết bị (`update.sh`): giao dịch DIFF -> FETCH -> APPLY -> COMMIT có thể tiếp tục.
- [`PRODUCER.md`](docs/PRODUCER.md): phía PC/phát hành: xây dựng và ký feed địa chỉ hóa theo nội dung (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): widget bảng Updates cắm-là-chạy (toast tiến trình, hủy, banner khởi động lại).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): một hướng dẫn áp dụng từng bước và các đoạn mã nối dây.

## Xem thêm

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: giả mạo fingerprint toàn cục của thiết bị / Play Integrity, trên toàn thiết bị với phạm vi theo từng ứng dụng và một WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: sao lưu và khôi phục toàn bộ ứng dụng và dữ liệu với quyền root, điều khiển hoàn toàn từ một WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: một SSH daemon độc lập chạy với quyền root (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: các dịch vụ Google của bạn (RCS, Wallet, các chứng thực Play Integrity), đọc ngay trên thiết bị của bạn mà không cần internet.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: một trình cài đặt sideload với quyền root không ma sát cho các APK đơn, hàng loạt và phân tách, với công tắc trình xác minh Play Protect và giả mạo nguồn cài đặt.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: một trình gỡ lỗi phương thức của thiết bị: đọc từng mục qua mọi phương thức có thể đọc nó và so sánh chúng cạnh nhau.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: kho mô-đun của chúng tôi cho MMRL/WebUI-X (cài đặt tất cả những thứ này từ trình quản lý root của bạn).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: một bộ dữ liệu fingerprint `build.prop` của Pixel (fork của @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: dùng Telegram như một object store từ một CLI Go nhỏ gọn.

## Contacts

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Giấy phép

Mã của riêng VDLiveUpdate theo **Apache-2.0**; xem [LICENSE](LICENSE). Nó vendor một trình xác minh `ed25519-mini` nhỏ
và một `curl` tĩnh cho phần bootstrap tải về, mỗi thứ theo giấy phép riêng của nó; xem
[NOTICE.md](NOTICE.md) và các tệp `PROVENANCE.json` nằm cạnh các tệp nhị phân đi kèm.

## Thương hiệu

VDLiveUpdate là một dự án độc lập, không chính thức, không liên kết với hay được chứng thực bởi bất kỳ bên thứ ba nào.
"Android" là thương hiệu của Google LLC; "KernelSU", "Magisk" và "APatch" là các nhãn hiệu của các tác giả
tương ứng của chúng. VDLU chạy hoàn toàn trên thiết bị của bạn và trên máy chủ phát hành của riêng bạn.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`
