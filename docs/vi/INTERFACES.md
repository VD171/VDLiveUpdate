> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · Tiếng Việt · [中文](../zh/INTERFACES.md)

---

# VDLU - Hợp đồng giao diện (đường ghép giữa các thành phần)

**Luật hội tụ:** mọi thành phần đều tuân theo tệp này. Các mảnh từ 4 agent phải **khớp vào nhau** - các
chữ ký CLI, tên tệp và khóa JSON bên dưới là **bất biến** (một thay đổi nghĩa là phải căn chỉnh tại đây trước).

Các nguyên tắc kế thừa từ các repo: **POSIX sh thuần** trên thiết bị (không có bashism; chạy với toybox/busybox +
`sha256sum`/`gzip`/`base64` của toybox + `curl` được tải về + `ed25519-mini` nhúng - gọn nhẹ, không có gói
binary), **không chú thích thừa**, **luôn release**, **nghiêm ngặt khi thất bại** (giao dịch có thể tiếp tục, không có gì
bị "xong" giả, không mất gì), **không nới lỏng gì**.

---

## 1. Bố cục trạng thái (Tier-2, bên ngoài thư mục module)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` trong journal = engine đã dừng do một yêu cầu hủy (một trạng thái không kết thúc, có thể tiếp tục; `error`
vẫn là null).

Engine được vendor trong module: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine nhận qua env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI của engine (thành phần ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = lỗi (stderr có lý do):

| cmd | làm gì |
|---|---|
| `check` | DIFF: tải manifest, so sánh; in một dòng JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; không thay đổi gì. Thiết bị ĐI TRƯỚC feed (downgrade bị chặn, hardened) = một trạng thái LÀNH: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (không bao giờ "check failed"). rc của do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | chu trình đầy đủ: DIFF→FETCH→APPLY→COMMIT; tôn trọng `cancel`; ghi tiến độ vào `journal.json`; áp dụng LIVE, staging REBOOT-hard |
| `resume` | tiếp tục giao dịch `journal.json` từ pha hiện tại (idempotent) |
| `boot` | chế độ pre-zygote: `resume` + thực hiện HOÁN ĐỔI của `staged/*.vdlu-new` (áp dụng `.so`), đóng `PENDING_REBOOT`→`DONE` |
| `status` | in `journal.json` (hoặc `{"state":"idle"}`) |
| `cancel` | tạo `$VDLU_DIR/cancel` (một `run` đang chạy dừng tại điểm an toàn kế tiếp) |

Nguồn blob/manifest: `source` từ config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` bắt đầu bằng `https://` (curl tĩnh tải về, TLS) hoặc `file://` (staging cục bộ).

## 3. manifest.json (do PRODUCER tạo ra, ENGINE tiêu thụ)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = cây đích HOÀN CHỈNH. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Mặc định theo path; không bao giờ hạ cấp `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, xác định; toybox gunzip trên thiết bị) chỉ khi nén tốt VÀ
  kích thước đáng kể; `sha256` LUÔN LUÔN của nội dung gốc.
- `sig`: chữ ký của manifest chuẩn hóa KHÔNG CÓ trường `sig` (§4 của verify).

## 4. journal.json (ENGINE ghi, WEBUI đọc - hợp đồng tiến độ)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Máy trạng thái (thứ tự cố định): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` chỉ khi băm lại TẤT CẢ khớp. Một REBOOT-hard đã staging ⇒ `PENDING_REBOOT` (không phải `DONE`). Các lối ra
khỏi pha `fetch`: `ERROR` (thất bại cứng) hoặc `DEFERRED` (net_policy đã chặn việc tải - lành/có thể tiếp tục,
không phải lỗi).

## 5. config (key=value, mỗi dòng một cái; chỉnh sửa được trong WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Thử lại khởi động (offline) - KIÊN NHẪN, an toàn pin:** chỉ lúc `boot` (không bao giờ lúc check/auto-open). Nếu
việc tải manifest thất bại do MẠNG (`fetch_offline` phân loại theo mã thoát của fetcher), nó chờ và
thử lại cho đến khi thành công HOẶC cạn `boot_retry_minutes` thời gian AWAKE. Một thiết kế **không giữ gì và không hao pin**:
- **Không wakelock:** giữa các lần thử nó là `sleep`, đóng băng trong deep-sleep → thiết bị ngủ bình thường
  (~không tốn pin); lần thử lại tạm dừng và tiếp tục khi thiết bị đã thức.
- **Không giữ khóa:** `acquire_lock_try`+release GIỮA các lần thử (không giữ khóa trong khi chờ) →
  `run`/check thủ công không bao giờ bị chặn; nếu một run thủ công staging một TARGET trong lúc đó, boot hoãn lại.
- **Không đánh thức radio vô cớ:** một thăm dò `net_allowed` (qua `net_type`/`ip route get`, tra cứu route ở
  kernel tôn trọng policy-routing của Android; không gói tin) kiểm soát mỗi lần thử - nó chỉ tốn một fetch khi
  mạng đã xuất hiện.
- KHÔNG BAO GIỜ thử lại một thất bại xác định (manifest/sig/downgrade). `--connect-timeout 15` trên fetch (không
  treo ở captive portal). `service.sh` đưa nó vào nền (boot không bao giờ treo).
- ⛔ **CỨNG: bật `boot_retry_minutes>0` đòi hỏi engine KIÊN NHẪN** (loại có
  `net_allowed`+`acquire_lock_try`, chuẩn `da7115f4`+). Boot-retry TRƯỚC ĐÓ (giữ khóa suốt cả
  cửa sổ + thử lại curl mù offline) **HAO PIN/ĐÁNH THỨC RADIO** - bật thử lại trong một engine cũ
  là một footgun. Khi bật nó, hãy vendor engine hiện tại.

**`net_policy` (any|wifi|mobile):** kiểm soát **VIỆC TẢI** theo loại mạng. `net_type()` phân loại cổng ra
của `ip route get` (iface di động `rmnet/ccmni/v4-*/clat` = mobile; mọi thứ khác = wifi; tra cứu ở kernel, không
gói tin). `net_allowed()` so với `net_policy` và kiểm soát `do_fetch` (các blob) + thăm dò boot-retry kiên nhẫn.
**Việc kiểm tra manifest vẫn miễn phí** (nhỏ xíu → UI báo một cập nhật trên bất kỳ mạng nào); chỉ việc tải
chờ mạng được phép. Một lần tải trên mạng không được phép = trạng thái **`DEFERRED`** trong journal
(KHÔNG phải ERROR; một toast INFO xanh dịu "đang chờ mạng X"; plan/target tồn tại, nó tiếp tục ở lần
check/boot kế tiếp trên mạng đúng). `net_policy` **thay thế** `allow_metered` (thứ chưa bao giờ được dùng).
Engine `97baf887`+ (`file://` không bao giờ bị kiểm soát).

## 6. Chữ ký (PRODUCER ký trên PC qua openssl; ENGINE xác minh trên thiết bị qua ed25519-mini)

- Chuẩn hóa: manifest KHÔNG CÓ `sig`, khóa được sắp xếp, JSON gọn (không có khoảng trắng thừa), UTF-8.
  Cái được ký/xác minh = `sha256` hex của dạng chuẩn hóa đó (cho tính xác định xuyên công cụ).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → chèn `key_id` + `sig` (base64 của chữ ký ed25519 của sha256 chuẩn hóa) vào manifest, tại chỗ.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 nếu `sig` khớp với khóa công khai `<key_id>.pub` trong
  keyring (SLIM: khóa công khai **RAW 32 byte**). Bên trong, không openssl: toybox `sha256sum`/`base64 -d` + binary
  `ed25519-mini` nhúng (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=hợp lệ/1=không hợp lệ/2=usage).
  rc!=0 = từ chối. **`profile=hardened` ⇒ verify bắt buộc; thất bại = abort.**
  `profile=trusted` ⇒ verify là best-effort (nguồn đã tin cậy qua SSH), nhưng băm của mỗi blob LUÔN được kiểm tra.
- **allowlist khóa module-update (fail-closed, trước khi chọn pubkey):** `key_id` của manifest phải là một khóa MODULE-UPDATE được chấp nhận trước khi `<key_id>.pub` được chọn - `key_id` của config (§5) chính là allowlist đó. Một keyring CŨNG có thể mang một khóa tin cậy thấp hơn (ví dụ một khóa fingerprint-feed, tự động, tài khoản khác); không có allowlist, một manifest ký bằng khóa đó sẽ xác minh được và áp dụng một bản cập nhật flashless root đầy đủ nếu bị rò rỉ. `verify_manifest` thực thi điều này trong CẢ HAI profiles và truyền tập đã giải quyết cho `vdlu-verify` qua env `VDLU_KEYID_ALLOW` (để trình xác minh standalone cũng đồng thuận). Chưa đặt là an toàn mặc định (keyring một khóa: chỉ khóa đó; keyring nhiều khóa: bị từ chối cho đến khi `key_id` được ghim). Gốc tin cậy của fingerprint-feed là một đường RIÊNG với khóa được ghim của chính nó và không bị ảnh hưởng.
- `producer/vdlu-keygen <id> <out>` → sinh `<id>.pem` (priv) + `<id>.pub` (PEM, cho công cụ trên PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` của keyring gọn trên thiết bị). openssl `genpkey -algorithm ed25519`.

## 7. Blob - xác minh (ENGINE)

Tải `<source>/blobs/<sha>` (hoặc `.gz` nếu `enc=gz`), ghi `.part`, nếu `gz` thì giải nén (`gunzip`),
kiểm tra `sha256sum` == `sha256` của manifest; khớp → `mv` nguyên tử tới `$VDLU_DIR/blobs/<sha>`. 3 lần thất bại trên
cùng một blob = hủy bỏ pha (không áp dụng gì). Một blob đã có trong `$VDLU_DIR/blobs/<sha>` với băm ok =
bỏ qua việc tải.

## 8. APPLY theo class (ENGINE)

- `live`/`soft`: sao lưu `rollback/<v>/<path>` → ghi `$MODULE_DIR/<path>.vdlu-tmp` từ blob → `chmod mode` →
  `rename` nguyên tử đè lên đích. Đã ở băm đích = bỏ qua. (Trong biến thể Zygisk, việc ghi đi tới thư mục
  được mount = hợp nhất theo từng tệp, không bao giờ `rm -rf` thư mục.)
- `reboot`: hiện thực hóa vào `$VDLU_DIR/staged/<path>.vdlu-new` (KHÔNG chạm vào bản live). Hoán đổi lúc `boot`.
- `delete[]`: sao lưu → xóa.

## 9. WEBUI ↔ ENGINE (thành phần WEBUI)

- Kích hoạt: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (nền).
- Tiến độ: một poll nhẹ `ksu.exec("cat $VDLU_DIR/journal.json")` mỗi ~1s; render `{phase,state,total,done,current,bytes}`.
- Sống còn: journal vắng mặt 8 tick ⇒ "không phản hồi". Journal ĐÓNG BĂNG (cùng giá trị) 20 tick ⇒ kiểm tra `lock.d`: còn sống = tiếp tục (fetch chậm của 1 blob), chết = lỗi + Resume. Không có cái này, một run chết giữa chừng fetch sẽ đóng băng toast ở "updating".
- Hủy: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: đọc/ghi `$VDLU_DIR/config` (key=value) trong một tab "Updates".
- Toast: thanh + `phase done/total · current`; khi kết thúc với `reboot_pending` ⇒ một banner bền "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): trước tiên làm một `check()` LẶNG LẼ (không toast tiến độ); chỉ kích hoạt `run`+toast bền nếu `update && fetch>0`. Đã cập nhật/đi trước/không có gì mới = một kết quả inline trong panel, không có toast thừa. Không xâm lấn như nút thủ công (toast chỉ xuất hiện khi có một lần tải thực sự). curl bootstrap là một lần.

## 10. Tích hợp vào demo (thành phần INTEGRATION) - ĐOẠN MÃ, đừng chỉnh các tệp live

Tạo, trong `integration/demo/`, các đoạn mã + một `INTEGRATION.md` nói mỗi cái đi đâu (không áp dụng):
- hook `auto_on_reboot` trong `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) và `auto_on_webui_open`.
- các giá trị mặc định của `config` + keyring nhúng + việc vendor (`modules/<mod>/vdlu/`).
- biến thể PARTIAL (hợp nhất vào thư mục được mount).

## 11. Toolchain được tải + baseline (SLIM, Phương án B)

**Bố cục trong module (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **KHÔNG CÓ** `bin/` (openssl/curl/zstd). `customize.sh` có thể cắt tỉa
`verify/` xuống còn ABI của thiết bị (`vdlu-verify` tìm mini tại `<dir>/ed25519-mini` HOẶC `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binary nhúng, chỉ verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=hợp lệ,
1=không hợp lệ, 2=usage/IO. msg = đúng các byte đã ký (KHÔNG băm lại). TweetNaCl PD, tĩnh theo từng ABI, PROVENANCE.

**tools-feed** (chỉ profile public/https): phục vụ tại `<tools_source>` (mặc định suy ra: đổi đoạn cuối
của `source` thành `vdlu-tools`, ví dụ `https://<user>.github.io/<repo>/vdlu-tools`). Chứa:
- `tools-manifest.json` - một manifest `vdlu-pack` ĐÃ KÝ trên cây `<abi>/curl`, ghim `sha256` của
  mỗi curl (cùng khóa `release-2026`).
- `<abi>/curl` - curl **tĩnh** THÔ (tự chứa, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS KHÔNG
  mang theo CA bundle: `fetch_url` truyền `--capath` (tự động phát hiện kho tin cậy Android: `/system/etc/security/cacerts`
  → APEX conscrypt; `ca_path` ghi đè). Không capath = lỗi 60. Tính toàn vẹn là ed25519; kiểm tra cert là phòng-thủ-theo-tầng.

**install-tool** (ENGINE): `update.sh install-tool <abi>` đọc `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI tải nó qua `fetch()` và ghi nó vào đó), **xác minh chữ ký của tools-manifest (ed25519-mini,
BẮT BUỘC trong mọi profile)** + băm của curl == manifest, và chỉ khi đó mới cài nó vào `$VDLU_DIR/tools/<abi>/curl` (0755).
curl chạy với quyền root → sig+hash trước exec đóng RCE. Tồn tại trong Tier-2: không bao giờ tải lại (trừ khi gỡ cài).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): chạy trước check/run/resume. `file://` = no-op; curl ĐÃ
có sẵn (Tier-2, HOẶC `module/bin/<abi>/curl` từ một module **tự-đóng-gói**, HOẶC system) = no-op
(VDLU tái sử dụng curl hiện có); chỉ `https` **mà hoàn toàn không có curl** mới tải curl + tools-manifest qua webview, ghi
chúng vào `.work` (base64 theo khối qua `ksu.exec`), gọi `install-tool`. Tin cậy = việc kiểm tra trên thiết bị, không phải việc tải.

> 🪤 **Slim (fetch-bootstrap) ≠ bắt buộc.** Một module có `bin/` tồn tại cho CÁC TÍNH NĂNG RIÊNG của nó (ví dụ nó đóng gói
> restic/rclone/age/tar/curl...) **không** thu nhỏ xuống ~2MB cũng chẳng tải curl - VDLU tiếp nhận slim engine
> (gz, mini, baseline, các bản vá) và **tái sử dụng** toolchain nhúng. Chỉ các module không có toolchain riêng
> mới tăng thêm ~2MB.

**baseline.json** (bản vá from:0): bản release sao chép `manifest.json` ĐÃ KÝ của phiên bản phát hành tới
`vdlu/baseline.json`; trên một lần cài mới engine gieo `current.json` từ nó (`init_paths`, chỉ khi vắng mặt) → thiết bị
sinh ra "đã cập nhật", không tự động cập nhật chính nó và không tải lại.

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
