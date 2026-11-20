# WebUI

VDLU ship kèm một widget WebUI chèn-vào tùy chọn: một bảng "Updates" nhỏ cho một WebUI root-manager của KernelSU hoặc APatch. Nó cho người dùng một nút Check, một nút Update now, một toast tiến trình trực tiếp kèm hủy, một biểu ngữ khởi động lại, và một bảng cài đặt, tất cả mà người dùng không bao giờ phải chạm vào một terminal.

Nó là **vanilla JavaScript**: không framework, không bước build, không CDN. Ba tệp:

| Tệp | Nó là gì |
|---|---|
| `vdlu.js` | widget; phơi ra `window.VDLU` |
| `vdlu.css` | các kiểu cho toast, biểu ngữ và bảng (giao diện tối, kế thừa các biến CSS của host) |
| `demo.html` | một trang độc lập giả lập cầu nối thiết bị để toàn bộ giao diện chạy trong một trình duyệt thường |

Widget hoàn toàn tùy chọn. [[Engine]] chạy ổn một mình từ các trigger lúc boot; WebUI chỉ là một bộ mặt thân thiện phủ lên trên nó. Xem [[Quick Start]] để biết cách nối nó vào một module.

---

## Cách giao diện nói chuyện với engine: cầu nối `ksu.exec`

Widget tự nó không bao giờ làm bất cứ điều gì đặc quyền. Nó dựng một lệnh shell và trao nó cho cầu nối `ksu.exec` của root manager, cầu nối này chạy nó như root và trả về stdout / stderr / mã thoát. Mọi thứ bảng hiển thị đều được đọc lại từ các tệp mà engine ghi.

Widget bọc cầu nối đó trong một hàm `exec(cmd)` duy nhất trả về một `Promise`:

- **resolve** với stdout khi lệnh thoát 0
- **reject** với stderr (hoặc `rc=N`) nếu không

Mỗi lệnh mang theo môi trường của hợp đồng, được widget lắp ráp:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Một vài lời gọi cụ thể:

- **Bắt đầu một bản cập nhật:** `update.sh run` được khởi chạy ở **nền** (`(... &)`) để giao diện không bao giờ bị chặn bởi một lần tải dài.
- **Đọc tiến trình:** một lần thăm dò nhẹ (khoảng mỗi giây một lần) của `cat $VDLU_DIR/journal.json`.
- **Hủy:** `touch $VDLU_DIR/cancel` (engine dừng tại điểm an toàn kế tiếp).
- **Cấu hình:** đọc và ghi `$VDLU_DIR/config` (key=value), bảo toàn thứ tự và các khóa chưa biết và chỉ chạm vào các khóa mà người dùng đã thay đổi.

Nếu host truyền các helper `exec`, `toast` và `confirm` của riêng nó vào `init()`, widget định tuyến qua hàng đợi lệnh tuần tự hóa và phần hình ảnh của riêng host, nên nó trông và hành xử giống phần còn lại của WebUI đó. Nếu chúng bị bỏ qua, widget quay về gọi `ksu.exec` trực tiếp và chèn mini-toast của riêng nó.

---

## Toast tiến trình (kèm hủy)

Một khi một bản cập nhật đang chạy, widget hiển thị một toast góc không chặn và thăm dò `journal.json`. Toast phản ánh máy trạng thái của engine:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Nó vẽ một thanh tiến trình cộng với một dòng `phase done/total - current file - bytes`, và mang theo một nút **Cancel** xuyên suốt. Mỗi trạng thái kết thúc đều có cách xử lý riêng:

- **DONE** -> một toast xanh lá, "vX applied - all verified".
- **PENDING_REBOOT** -> một toast xanh lá cộng với một biểu ngữ khởi động lại dai dẳng (bên dưới).
- **ERROR** -> một toast đỏ kèm lý do từ `journal.error` hoặc stderr, kèm nút Retry. Nó không bao giờ giả vờ thành công.
- **Cancelled** -> một toast hổ phách, "cancelled - N/M applied, resumable", kèm nút **Resume**.
- **DEFERRED** -> một toast thông tin xanh dương nhẹ nhàng, "download deferred, waiting for the allowed network". Đây là một lần chờ chính sách mạng lành tính, không phải lỗi; nó tiếp tục ở lần check hoặc boot tiếp theo trên mạng đúng.

Việc thăm dò mang tính phòng vệ. Một nhật ký ghi dở dang (engine ghi đồng thời) bị bỏ qua cho nhịp (tick) đó thay vì bị phân tích sai. Nếu nhật ký biến mất sau khi đã thấy tiến trình, điều đó nghĩa là commit đã xóa nó: widget báo cáo DONE. Nếu nhật ký vắng mặt ngay từ đầu trong 8 nhịp, nó báo cáo "no response". Và nếu nhật ký đóng băng ở cùng các giá trị trong 20 nhịp, widget kiểm tra `lock.d` của engine: nếu khóa còn sống thì đó chỉ là một lần fetch một-blob chậm và toast tiếp tục chờ; nếu khóa đã chết thì lần chạy đã chết giữa chừng, nên widget nổi lên một lỗi kèm nút Resume thay vì quay mãi ở "updating".

---

## Biểu ngữ khởi động lại

Một số tệp không thể được hoán đổi trên một hệ thống đang sống: một `.so`, một overlay `/system`, một `sepolicy.rule`. Engine staged những thứ đó và đánh dấu giao dịch `PENDING_REBOOT`. Widget khi đó hiển thị một **biểu ngữ trên cùng dai dẳng**: "Reboot to activate the new `.so` (vX)". Nó ở lại cho đến khi các tệp đã staged được hoán đổi ở lần khởi động tiếp theo. Khi mở WebUI, biểu ngữ được đánh giá lại từ nhật ký, nên một người dùng đóng và mở lại giao diện vẫn thấy nó. Xem [[Reboot Handling]] để biết điều gì xảy ra lúc boot.

Lưu ý biểu ngữ dựa theo trạng thái kết thúc `PENDING_REBOOT`, không dựa theo cờ `reboot_pending` (cờ này thành true ngay khi bất kỳ `.so` nào vào kế hoạch). Điều đó giữ cho biểu ngữ không xuất hiện giữa lần chạy trước khi bất cứ thứ gì thực sự được staged.

---

## Bảng "Updates": các công tắc độc lập theo từng danh mục

`mountUpdatesPanel(el)` vẽ bảng cài đặt vào một `<div>` rỗng mà host cung cấp. Nó có ba phần, và mỗi điều khiển độc lập và tự lưu riêng:

**Actions**
- **Check for updates** -> chạy `check`, hiển thị kết quả ngay tại chỗ (đã mới nhất / mới hơn feed / có bản cập nhật kèm số lượng tệp và một thẻ reboot).
- **Update now** -> khai hỏa `run` cộng với toast tiến trình.

**Automation** (các công tắc độc lập, mỗi cái được ghi vào `config` ngay khi nó được bật/tắt)
- **On WebUI open** (`auto_on_webui_open`) -> chạy một bản cập nhật im lặng khi giao diện mở.
- **On reboot** (`auto_on_reboot`) -> áp dụng trong pre-zygote lúc boot.
- **Boot retry every (s)** và **Boot retry up to (min)** -> các ô số để thử lại lần fetch manifest khi thiết bị boot lên offline.

**Source**
- `source` (URL feed), `channel` (stable / canary), `profile` (trusted / hardened), và một ô chọn **Network** ánh xạ tới `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Các công tắc và ô số lưu ngay lập tức và quay lại về mặt hình ảnh nếu lần ghi thất bại. Các ô văn bản và ô chọn trong phần Source tự đánh dấu là dirty và lưu cùng nhau khi nhấn một nút Save tường minh. Bảng chỉ bao giờ ghi lại các khóa mà người dùng đã chạm vào, nên mọi khóa cấu hình chưa biết hay trong tương lai đều được bảo toàn.

### Hành vi tự mở

`onWebUIOpen()` được gọi khi host nạp. Nó đánh giá nhật ký (hiển thị biểu ngữ khởi động lại hoặc đề nghị Resume cho một giao dịch chưa kết thúc do một phiên trước để lại), rồi, nếu `auto_on_webui_open=1`, nó chạy một `check()` **im lặng** trước. Toast tiến trình dai dẳng và `run` thực sự chỉ khai hỏa khi có một lần tải thật để làm (`update && fetch > 0`). Nếu thiết bị đã mới nhất hoặc đi trước feed, kết quả hiển thị ngay tại chỗ trong bảng và không có toast nào bị bỏ lại trên màn hình, nên lần tự cập nhật ít gây phiền như nút thủ công.

---

## i18n (các chuỗi theo từng ngôn ngữ)

Mọi chuỗi giao diện mặc định là **tiếng Anh**, vốn là lựa chọn trung lập cho các module đa ngôn ngữ công khai. Bản đồ khóa đầy đủ nằm trong đối tượng `DEFAULT_I18N` trong `vdlu.js` (cũng được phơi ra như `VDLU.i18n`). Một host ghi đè bất kỳ tập con khóa nào bằng cách truyền một bản đồ vào `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Một bản đồ **một phần** là ổn: bất kỳ khóa nào thiếu sẽ quay về mặc định tiếng Anh.
- Các nhãn pha và trạng thái dùng các khóa `ph_<phase>` và `st_<STATE>`; phần còn lại là các khóa phẳng như `cancel`, `updateNow`.
- Một bản dịch đã thực hiện (`i18n/pt-BR.js`) ship như một mẫu; một ngôn ngữ mới chỉ là một tệp `i18n/<lang>.js` có cùng hình dạng, hoặc host dựng bản đồ từ hệ thống i18n của riêng nó.

---

## demo.html: chạy giao diện mà không cần thiết bị

`demo.html` giả lập cầu nối `ksu.exec` để chính `vdlu.js` và `vdlu.css` đó chạy trong một trình duyệt thường, không cần root và không cần điện thoại:

```sh
xdg-open webui/demo.html
```

Bản giả lập mô phỏng `update.sh` và một `journal.json` đang tiến triển, và các nút của nó chuyển qua lại giữa các kịch bản: một bản cập nhật live cho đến DONE, một lần kết thúc `reboot_pending`, một lỗi giữa chừng, và một lần chạy có thể hủy. Đó là cách nhanh nhất để thấy và lặp lại trên giao diện, và đó là thứ bạn kiểm tra trước khi vendor widget vào một module.

---

## Nối nó vào một module (trigger mở-WebUI)

`index.html` của host nạp hai tệp và gọi ba hàm:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

Host chỉ cần cung cấp các đường dẫn Tier-2 và cấp phát một `<div>` rỗng cho bảng; toast và biểu ngữ được widget chèn vào `document.body`. `onWebUIOpen()` là trigger mở-WebUI: nó là thứ đánh giá biểu ngữ khởi động lại, đề nghị Resume trên một giao dịch bị gián đoạn, và chạy bản cập nhật tự động im lặng khi `auto_on_webui_open` được đặt.

### Một nguồn duy nhất, được re-vendor từng byte

`vdlu.js` và `vdlu.css` là **bản sao chuẩn tắc**. Một module nhúng widget sẽ re-vendor các tệp này không đổi vào `webroot/` của nó; nó không bao giờ chỉnh sửa bản sao của riêng nó tại chỗ. Một tính năng mới sinh ra trong các tệp chuẩn tắc và chảy xuống bằng cách re-vendor. Chỉnh sửa một bản sao đã vendor sẽ tạo ra sự trôi dạt âm thầm (điều này đã xảy ra: một bản sao cũ thiếu `net_policy`, toast DEFERRED và các ô thử lại lúc boot). Một người gác chẵn lẻ (parity guardian) trong cây nguồn tìm mọi bản sao và gắn cờ hoặc re-vendor những bản đã phân kỳ, chỉ bao phủ widget; keyring có nhịp verify-not-copy của riêng nó.

---

### API công khai (`window.VDLU`)

| Hàm | Làm gì |
|---|---|
| `init(opts)` | cấu hình widget; trả về `window.VDLU` |
| `onWebUIOpen()` | gọi khi nạp: biểu ngữ, đề nghị Resume, và bản cập nhật tự động im lặng |
| `mountUpdatesPanel(el)` | vẽ bảng Updates vào `el` (chuỗi id hoặc phần tử) |
| `check()` | chạy `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | khai hỏa `run` ở nền cộng với toast tiến trình kèm Cancel |
| `cancel()` | tạo `$VDLU_DIR/cancel` (engine dừng tại một điểm an toàn) |
| `resume()` | tiếp tục giao dịch hiện tại cộng với một toast |
| `refreshBanner()` | đánh giá lại biểu ngữ pending-reboot dai dẳng |

---

Xem thêm: [[Engine]] để biết các lệnh mà widget điều khiển, [[Quick Start]] để biết đầy đủ các bước áp dụng, và [[Reboot Handling]] để biết biểu ngữ đang chờ điều gì.
