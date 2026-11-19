> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · Tiếng Việt · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (flashless update)

Giao diện VDLU (VD Live Update) cho WebUI của trình quản lý root KernelSU/APatch. Vanilla JS, không framework, không
build, không CDN. Drop-in: `index.html` của host tải 2 tệp và gọi API.

Hội tụ: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Các tệp

| Tệp | Là gì |
|---|---|
| `vdlu.js` | thành phần - phơi bày `window.VDLU` |
| `vdlu.css` | toast tiến độ, banner reboot, tab "Updates" (chủ đề tối, kế thừa các biến của host) |
| `demo.html` | trang độc lập với một `ksu.exec` được mock - mở trong trình duyệt, không cần thiết bị |

## Tích hợp vào `index.html` của host

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### Những gì host phải định nghĩa

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), nơi engine được vendor
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), trạng thái Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id của module.

Widget lắp ráp lệnh engine đã mang sẵn env của hợp đồng (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` đi vào
**nền** (`(… &)`), và tiến độ được đọc bằng một poll nhẹ (~1s) của `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (tùy chọn)

Nếu bỏ qua, widget dùng của riêng nó:
- **`exec(cmd)`** phải trả về một `Promise` **resolve** với stdout (rc 0) và **reject** với stderr
  (rc≠0) - đúng chữ ký của `ex()` trong Demo `webroot/index.html`. Fallback nội bộ gọi
  `ksu.exec(cmd, '{}', cb)` với cùng hợp đồng.
- **`toast(msg)`** = một thông báo nhất thời ngắn (fallback chèn mini-toast của riêng nó).
- **`confirm(title,msg,ok,danger,fn)`** = một modal (hôm nay chỉ host dùng; widget không yêu cầu
  xác nhận trong bất kỳ luồng nào).

Truyền của riêng host khiến widget nói chuyện qua CÙNG hàng đợi tuần tự hóa và hình ảnh như phần còn lại của
WebUI.

## API công khai (`window.VDLU`)

| Hàm | Làm gì |
|---|---|
| `init(opts)` | cấu hình (xem trên). Trả về `window.VDLU`. |
| `onWebUIOpen()` | gọi nó khi tải: hiện banner nếu `reboot_pending`; đề nghị **Resume** nếu có một giao dịch không kết thúc; với `auto_on_webui_open=1` nó chạy một **auto-update LẶNG LẼ** (một `check()` im lặng trước; chỉ kích hoạt `run`+toast bền nếu `update && fetch>0` - đã cập nhật/đi trước = kết quả inline trong panel, không toast). |
| `mountUpdatesPanel(el)` | render tab "Updates" bên trong `el` (id dạng chuỗi hoặc element): **Check for update**, **Update now**, các toggle `auto_on_webui_open`/`auto_on_reboot`, các trường boot-retry, select **Network** (`net_policy`: Wi-Fi+mobile / chỉ Wi-Fi / chỉ mobile) và các trường `source`/`channel`/`profile`. |
| `check()` | chạy `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | kích hoạt `run` ở nền + một toast tiến độ với **Cancel**. |
| `cancel()` | tạo `$VDLU_DIR/cancel` (engine dừng tại điểm an toàn). |
| `resume()` | `update.sh resume` + toast (tiếp tục pha hiện tại). |
| `refreshBanner()` | đánh giá lại banner pending-reboot bền. |

Toast (lớp phủ góc, không chặn) và banner (trên cùng, bền) được widget chèn vào
`document.body` - host không cần HTML cho chúng. Tab "Updates" là điểm duy nhất host cấp phát (một
`<div>` rỗng).

### Luồng trạng thái mà toast phản ánh (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` ở bất kỳ lúc nào.
Toast hiện **một thanh + `phase done/total · current · bytes`**. Các trạng thái kết thúc:
- **`DONE`** → toast xanh lá "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (hoặc `reboot_pending=true`) → toast xanh lá + **banner bền** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → toast đỏ với lý do (`journal.error`/stderr). Không bao giờ giả vờ thành công.
- **Cancelled** → "cancelled - N/M, resumable" + một nút **Resume**.

## Chạy demo

Mở `demo.html` trong trình duyệt (`xdg-open webui/demo.html`). `ksu.exec` được mock mô phỏng `update.sh` và
`journal.json` tiến triển; các nút chuyển đổi giữa các kịch bản **LIVE→DONE**, **reboot_pending**, **error mid-way**
và **cancellable**. Đó là cùng `vdlu.js`/`vdlu.css` như trên thiết bị.

## i18n (ngôn ngữ)

Các chuỗi của widget mặc định là **English** (trung tính cho các module đa ngôn ngữ công khai). Host ghi đè
bất kỳ khóa nào bằng cách truyền một map trong `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Một lần hợp nhất **một phần** là ổn: một khóa thiếu quay về giá trị mặc định tiếng Anh.
- Các khóa phase/state là `ph_<phase>` / `st_<STATE>`; phần còn lại phẳng (`cancel`, `updateNow`, …).
- Map khóa đầy đủ = đối tượng `DEFAULT_I18N` trong `vdlu.js` (cũng được phơi bày như `VDLU.i18n`).
- Một bản dịch sẵn sàng được cung cấp như một ví dụ đã làm: `i18n/pt-BR.js`. Ngôn ngữ mới = một tệp
  `i18n/<lang>.js` theo cùng khuôn mẫu, hoặc host xây map từ hệ thống i18n của riêng nó.

## Nguồn duy nhất (ngang bằng giữa các module)

Các `vdlu.js`/`vdlu.css` này là **bản sao chuẩn**. Mọi module nhúng widget đều
**re-vendor** bản sao này từng-byte-một vào `webroot/` của nó - nó **không bao giờ** chỉnh sửa
bản của chính nó tại chỗ. Một tính năng mới của widget sinh ra ở đây và chảy xuống bằng re-vendor; chiều ngược lại sinh ra
drift âm thầm (nó đã xảy ra trong thực tế: một bản sao đã vendor tụt lại và thiếu `net_policy`, toast `DEFERRED`
và các trường `boot_retry`).

Người gác: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) tìm mọi bản sao trong cây nguồn và đánh dấu
những cái lệch khỏi bản chuẩn (chỉ `vdlu.js`/`vdlu.css`; keyring là "verify, not copy").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) và engine (`vdlu/update.sh`) có nhịp re-vendor của riêng chúng;
> người gác này chỉ bao phủ **widget WebUI**.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
