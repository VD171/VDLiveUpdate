# Quick Start

Đây là danh sách kiểm tra việc áp dụng: cách vendor **VDLiveUpdate (VDLU)** vào một
module KernelSU / APatch / Magisk. VDLU bản thân không phải là một module. Nó được đặt vào
`<module>/vdlu/` và ship bên trong zip của module bạn, để một module đã cài có thể
tự cập nhật không cần flash từ một feed đã ký mà bạn xuất bản.

Xuyên suốt, thay `<id>` bằng id khóa ký của bạn, `<abi>` bằng ABI của thiết bị
mà bạn ship (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), và `<module>`
bằng cây module của bạn.

Về lý do đằng sau mỗi phần, xem [[Engine]], [[Producer]], [[WebUI]] và
[[Security and Trust Model]].

## Bố cục `vdlu/` trong-module

Đây là cây chính xác mà module bạn mang theo sau khi áp dụng:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

Trạng thái có thể thay đổi của engine (`config`, `current.json`, nhật ký, khóa, cache blob)
sống ở Tier-2 tại `/data/adb/<modid>/vdlu/`, bên ngoài thư mục module.
`config.default` gieo mầm cho `config` Tier-2 đó ở lần chạy đầu tiên. Xem [[Engine]] để biết
bố cục trạng thái đầy đủ.

## 1. Vendor engine

Sao chép engine, shim verify và nhị phân bộ xác minh theo từng ABI vào
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Chỉ ship các ABI mà bạn hỗ trợ. `customize.sh` của bạn có thể cắt `verify/` xuống còn
ABI của thiết bị lúc cài.

## 2. Tạo một khóa ký (một lần)

```sh
producer/vdlu-keygen <id> ./keys
```

Việc này phát ra ba tệp:

- `<id>.pem` - khóa riêng. Giữ nó khỏi mọi thiết bị và khỏi bất kỳ lần push repo
  hay secret CI nào.
- `<id>.pub` - khóa công khai PEM. Chỉ phía PC (dùng bởi `vdlu-sign`).
- `<id>.pub.raw` - khóa công khai THÔ 32 byte, cho keyring thiết bị.

Xem [[Security and Trust Model]] để biết tại sao sự phân tách lại quan trọng.

## 3. Nhúng khóa công khai thô

Keyring thiết bị giữ khóa **THÔ 32 byte**, không bao giờ là PEM. `ed25519-mini`
không thể đọc một PEM, nên sao chép PEM vào đây sẽ phá việc xác minh trên thiết bị:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring ổn định xuyên các bản phát hành: nó chỉ thay đổi khi luân chuyển khóa. Khi
re-vendor, **hãy verify nó, đừng ghi đè nó**.

## 4. Viết cấu hình

Ship `config.default` trong `<module>/vdlu/`. Nó gieo mầm cho `config` Tier-2 ở lần
chạy đầu tiên:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Chỉ dùng `profile=trusted` cho một nguồn `file://` riêng tư hoặc SSH (verify là
best-effort ở đó, nhưng sha256 của mọi blob vẫn được kiểm tra). Bất kỳ giá trị nào khác
với `trusted` theo nghĩa đen đều được coi là `hardened`, fail-closed. Xem
[[Security and Trust Model]] để biết ngữ nghĩa profile đầy đủ.

## 5. Nối các trigger

**Khi khởi động lại** (`auto_on_reboot`): gọi engine pre-zygote từ
`post-fs-data.sh`, để các tệp thuộc lớp reboot đã staged (một `.so`, một overlay `/system`,
một `sepolicy.rule`) hoán đổi vào mà không cần một lần khởi động lại thêm:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Khi mở WebUI** (`auto_on_webui_open`): nối bảng Updates chèn-vào trong
`webroot/index.html` của bạn:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` và `vdlu.css` được vendor từ `webui/`. Một bản dịch có thể được thêm
với `i18n: window.VDLU_I18N_<LANG>`. Xem [[WebUI]] để biết hợp đồng của bảng.

## 6. Ký feed trong luồng phát hành của bạn

Mỗi lần phát hành, pack cây module cuối cùng và ký manifest. Giữ khóa riêng
trên máy người vận hành, không bao giờ trong CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` định địa chỉ theo nội dung và khử trùng lặp, nên việc xuất bản là tăng dần:
các blob không đổi không bao giờ bị đẩy lại. Xem [[Producer]] và [[Feed Format]].

## 7. Ship baseline

Tạo `baseline.json` trên cây được ship và đặt nó tại
`<module>/vdlu/baseline.json`. Nó gieo mầm cho `current.json` ở một bản cài mới, để
thiết bị ra đời đã "current" và không fetch lại phiên bản được ship của chính nó. Nó là
một **mầm tin cậy cục bộ**: chưa ký và không khóa, nên CI có thể dựng nó mà không bao giờ
chạm vào khóa ký:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Nó không gây tử vong nếu vắng mặt: thiết bị đơn giản bắt đầu từ phiên bản `0` ở lần
cập nhật đầu tiên.

---

Đó là toàn bộ việc áp dụng. Trước khi bạn ship, `sh -n <module>/vdlu/update.sh`
phải vượt qua, và bạn nên kiểm thử producer và engine từ đầu đến cuối như được trình bày trong
[[Contributing]] và [[Producer]].
