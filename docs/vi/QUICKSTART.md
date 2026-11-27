> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · Tiếng Việt · [中文](../zh/QUICKSTART.md)

---

# Hướng dẫn nhanh áp dụng VDLU

Một danh sách kiểm sao-chép-dán để vendor **VDLiveUpdate** vào một module. VDLU tự nó không phải một module:
nó được thả vào `<module>/vdlu/` và ship bên trong zip của module bạn. Về lý do đầy đủ, xem
[`INTERFACES.md`](INTERFACES.md) (hợp đồng seam), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) và
[`WEBUI.md`](WEBUI.md).

Thay `<id>` bằng id khóa ký của bạn, `<abi>` bằng (các) ABI thiết bị mà bạn ship (`arm64-v8a`,
`armeabi-v7a`, `x86_64`, `x86`), và `<module>` bằng cây module của bạn.

## Layout đích

Đây là cây `vdlu/` chính xác mà module mang theo sau khi áp dụng:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

Trạng thái thay đổi được của engine (`config`, `current.json`, journal, lock) nằm trong Tier-2,
`/data/adb/<modid>/vdlu/`, bên ngoài module dir, `config.default` gieo nó ở lần chạy đầu tiên.

## 1. Vendor engine

Sao chép engine, verify shim và verifier theo từng ABI vào `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Chỉ ship các ABI bạn hỗ trợ, `customize.sh` có thể cắt tỉa `verify/` xuống còn ABI của thiết bị lúc cài đặt.

## 2. Tạo một khóa ký (một lần)

```sh
producer/vdlu-keygen <id> ./keys
```

Lệnh này phát ra `<id>.pem` (priv, giữ nó khỏi mọi thiết bị và khỏi bất kỳ lần push repo nào), `<id>.pub`
(PEM, chỉ phía PC) và `<id>.pub.raw` (RAW 32 byte, cho keyring của thiết bị).

## 3. Nhúng khóa công khai thô

Keyring của thiết bị giữ khóa **RAW 32 byte**, không bao giờ là PEM (`ed25519-mini` không đọc được một PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring ổn định qua các release (nó chỉ đổi khi luân chuyển khóa): khi re-vendor, **xác minh, đừng ghi đè** nó.

## 4. Viết config

Ship `config.default` trong `<module>/vdlu/` (gieo `config` ở Tier-2 lúc chạy lần đầu):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

Chỉ dùng `profile=trusted` cho một nguồn `file://`/SSH riêng tư (verify best-effort, sha256 của mỗi blob vẫn
được kiểm tra). Bất kỳ giá trị nào khác với chữ `trusted` đúng nghĩa đều được xử lý như `hardened`
(fail-closed).

## 5. Đấu nối các trigger

**Lúc reboot** (`auto_on_reboot`): gọi engine pre-zygote từ `post-fs-data.sh` để các tệp đã staging (một
`.so`, một overlay `/system`, một `sepolicy.rule`) hoán đổi vào mà không cần reboot thêm:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Lúc mở WebUI** (`auto_on_webui_open`): đấu nối Updates panel drop-in trong `webroot/index.html` của bạn:

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` được vendor từ `webui/`, có thể thêm một bản dịch với
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Ký feed trong release workflow của bạn

Mỗi release, đóng gói cây module cuối cùng và ký manifest. Giữ khóa private trên máy người vận hành, không bao
giờ trong CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Ship baseline

Tạo `baseline.json` trên cây đã ship và đặt nó tại `<module>/vdlu/baseline.json`. Nó gieo `current.json` trên
một lần cài mới để thiết bị sinh ra "đã cập nhật" (không tải lại). Nó là một **hạt giống tin cậy cục bộ**: chưa
ký và không khóa, nên CI có thể dựng nó mà không bao giờ chạm vào khóa ký:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Nó không nghiêm trọng nếu vắng mặt (thiết bị chỉ bắt đầu từ `0` ở lần cập nhật đầu tiên).

---

Đó là toàn bộ việc áp dụng. `sh -n <module>/vdlu/update.sh` phải vượt qua, hãy kiểm thử producer và engine
đầu-cuối như trình bày trong [`PRODUCER.md`](PRODUCER.md) và README gốc trước khi bạn ship.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến, xem [CONTRIBUTING.md](CONTRIBUTING.md)._
