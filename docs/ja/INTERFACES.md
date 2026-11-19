> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · 日本語 · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - インターフェース契約 (コンポーネント間の継ぎ目)

**収束の法則:** すべてのコンポーネントはこのファイルに準拠する。4 つのエージェントが作る部品は**組み合わさって機能**しなければならない。以下の
CLI シグネチャ、ファイル名、JSON キーは**不変**である (変更するならまずここで整合させること)。

リポジトリから継承した原則: デバイス上では**純粋な POSIX sh** (bashism なし。toybox/busybox +
toybox の `sha256sum`/`gzip`/`base64` + 取得した `curl` + 組み込みの `ed25519-mini` で動作する。スリムで、バイナリ
バンドルなし)、**無駄なコメントはゼロ**、**常にリリース**、**失敗時には厳格に** (再開可能なトランザクション、何も
偽って「完了」とせず、何も失わない)、**何も緩めない**。

---

## 1. 状態レイアウト (Tier-2、モジュールディレクトリの外)

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
journal 内の `cancelled:true` = エンジンがキャンセルで停止した状態 (非終端で再開可能な状態。`error`
は null のまま)。

モジュールに同梱されるエンジン: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`)。`$MODULE_DIR =
/data/adb/modules/<module>`。エンジンは環境変数経由で次を受け取る: `VDLU_DIR`、`MODULE_DIR`、`MODID`。

## 2. エンジン CLI (ENGINE コンポーネント)

`sh update.sh <cmd>` - rc 0 = ok、!=0 = エラー (理由は stderr に出る):

| cmd | 動作 |
|---|---|
| `check` | DIFF: manifest をダウンロードして比較する。1 行の JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` を出力する。何も変更しない。デバイスがフィードより AHEAD (ダウングレードはブロック、堅牢化済み) = **良性**の状態: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (決して「check failed」としない)。do_diff の rc: 2 fetch/parse、3 verify/meta、4 ahead |
| `run` | フルサイクル: DIFF→FETCH→APPLY→COMMIT。`cancel` を尊重する。進捗を `journal.json` に書く。LIVE を適用し、REBOOT-hard をステージする |
| `resume` | `journal.json` のトランザクションを現在のフェーズから再開する (冪等) |
| `boot` | pre-zygote モード: `resume` + `staged/*.vdlu-new` の SWAP を行う (`.so` を適用)、`PENDING_REBOOT`→`DONE` を閉じる |
| `status` | `journal.json` を出力する (なければ `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` を作成する (進行中の `run` は次の安全地点で停止する) |

Blob/manifest のソース: config の `source`。`<source>` + `/manifest.json`、`/blobs/<sha>`、`/blobs/<sha>.gz`。
`source` は `https://` (静的 curl で取得、TLS) または `file://` (ローカルステージング) で始まる。

## 3. manifest.json (PRODUCER が生成し、ENGINE が消費する)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = 完全なターゲットツリー。`class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`、`system/**`、`*.rule`)。
  パスによるデフォルト。`reboot`→`live` へのダウングレードは決してしない。
- `enc`: `gz` (gzip `-9 -n`、決定論的。デバイス上では toybox gunzip) は圧縮がよく効き、**かつ**
  サイズが大きい場合のみ。`sha256` は**常に**オリジナルの内容に対するもの。
- `sig`: `sig` フィールドを除いた正規 manifest の署名 (verify の §4)。

## 4. journal.json (ENGINE が書き、WEBUI が読む - 進捗契約)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

状態機械 (固定順): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`。
`DONE` は**すべて**の再ハッシュが一致したときのみ。REBOOT-hard がステージされると ⇒ `PENDING_REBOOT` (`DONE` ではない)。
`fetch` フェーズからの出口: `ERROR` (ハード失敗) または `DEFERRED` (net_policy がダウンロードをブロック - 良性/再開可能で、
エラーではない)。

## 5. config (key=value、1 行 1 件。WEBUI で編集可能)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (オフライン時) - 忍耐強く、バッテリーに優しい:** `boot` 時のみ (check/auto-open では決してしない)。manifest
の取得がネットワーク起因で失敗した場合 (`fetch_offline` がフェッチャーの終了コードで分類する)、成功するか
`boot_retry_minutes` 分の AWAKE 時間を使い切るまで待って再試行する。**何も保持せず、バッテリーを消耗させない**設計:
- **wakelock ゼロ:** 試行の間は `sleep` であり、deep-sleep でフリーズする → デバイスは通常どおりスリープする
  (バッテリー消費はほぼゼロ)。再試行は一時停止し、デバイスが既に起きたら再開する。
- **保持ロックゼロ:** 試行の**間**は `acquire_lock_try`+release (待機中にロックを保持しない) →
  `run`/手動 check は決してブロックされない。その間に手動 run が TARGET をステージした場合、boot は譲る。
- **無駄に radio を起こさない:** `net_allowed` プローブ (`net_type`/`ip route get` 経由。Android のポリシールーティングを尊重する
  カーネルのルート検索。パケットなし) が各試行をゲートする - ネットワークが現れたときだけ fetch を費やす。
- 決定論的な失敗 (manifest/sig/downgrade) は決して再試行しない。fetch には `--connect-timeout 15` (captive portal で
  ハングしない)。`service.sh` がそれをバックグラウンド化する (boot は決してハングしない)。
- ⛔ **HARD: `boot_retry_minutes>0` を有効にするには忍耐強いエンジンが必要** (
  `net_allowed`+`acquire_lock_try` を備えたもの、正規 `da7115f4`+)。以前の boot-retry (ウィンドウ全体でロックを保持し
  + オフラインで盲目的に curl を再試行する) は**バッテリーを消耗させ/radio を起こす** - 古いエンジンで再試行を
  有効にするのは自爆行為である。有効にするときは現在のエンジンを同梱すること。

**`net_policy` (any|wifi|mobile):** **ダウンロード**をネットワークタイプでゲートする。`net_type()` は
`ip route get` の egress を分類する (セルラー iface `rmnet/ccmni/v4-*/clat` = mobile。それ以外 = wifi。カーネル検索、
パケットなし)。`net_allowed()` は `net_policy` と比較し、`do_fetch` (blobs) + 忍耐強い boot-retry の
プローブをゲートする。**manifest の check は無料のまま** (小さい → どのネットワークでも UI が更新を報告する)。
ダウンロードのみが許可されたネットワークを待つ。許可されていないネットワークでのダウンロード = journal 内の **`DEFERRED`**
状態 (ERROR ではない。穏やかな青い INFO トースト「waiting for X network」。plan/target は保持され、正しいネットワークで
次の check/boot のときに再開する)。`net_policy` は `allow_metered` (消費されたことがない) を**置き換える**。
エンジン `97baf887`+ (`file://` は決してゲートされない)。

## 6. 署名 (PRODUCER が PC 上で openssl で署名、ENGINE がデバイス上で ed25519-mini で検証)

- 正規化: `sig` を除いた manifest、キーをソート、コンパクトな JSON (余分な空白なし)、UTF-8。
  署名/検証されるのは、その正規形の `sha256` 16 進 (クロスツールの決定性を与える)。
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → `key_id` + `sig` (正規 sha256 の ed25519 署名の base64) を manifest にその場で注入する。
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → keyring 内の `<key_id>.pub` 公開鍵に `sig` が一致すれば rc 0
  (SLIM: 公開鍵は**生の 32 バイト**)。内部では openssl 不使用: toybox `sha256sum`/`base64 -d` + 組み込みの
  `ed25519-mini` バイナリ (CLI `ed25519-mini <pub32> <msg> <sig64>`、rc 0=有効/1=無効/2=使用法)。
  rc!=0 = 拒否。**`profile=hardened` ⇒ 検証は必須。失敗 = 中止。**
  `profile=trusted` ⇒ 検証はベストエフォート (ソースは SSH 経由で既に信頼済み) だが、すべての blob のハッシュは**常に**チェックされる。
- `producer/vdlu-keygen <id> <out>` → `<id>.pem` (秘密) + `<id>.pub` (PEM、PC 上のツール用) +
  `<id>.pub.raw` (**生の 32B** = デバイス上のスリム keyring の `<id>.pub`) を生成する。openssl `genpkey -algorithm ed25519`。

## 7. Blob - 検証 (ENGINE)

`<source>/blobs/<sha>` (または `enc=gz` なら `.gz`) をダウンロードし、`.part` に書き込み、`gz` なら展開し (`gunzip`)、
`sha256sum` == manifest の `sha256` をチェックする。一致 → アトミックな `mv` で `$VDLU_DIR/blobs/<sha>` へ。同じ blob で
3 回失敗 = フェーズを中止する (何も適用しない)。`$VDLU_DIR/blobs/<sha>` に既にハッシュが ok の blob がある =
ダウンロードをスキップする。

## 8. クラス別 APPLY (ENGINE)

- `live`/`soft`: `rollback/<v>/<path>` にバックアップ → blob から `$MODULE_DIR/<path>.vdlu-tmp` を書く → `chmod mode` →
  ターゲット上にアトミックな `rename`。既にターゲットのハッシュである = スキップ。(Zygisk バリアントでは書き込みは
  マウントされたディレクトリへ = ファイルごとのマージであり、ディレクトリの `rm -rf` は決してしない。)
- `reboot`: `$VDLU_DIR/staged/<path>.vdlu-new` に実体化する (ライブなものには触れない)。swap は `boot` で行う。
- `delete[]`: バックアップ → 削除。

## 9. WEBUI ↔ ENGINE (WEBUI コンポーネント)

- 起動: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (バックグラウンド)。
- 進捗: 約 1 秒ごとの軽量ポーリング `ksu.exec("cat $VDLU_DIR/journal.json")`。`{phase,state,total,done,current,bytes}` をレンダリングする。
- Liveness: journal が 8 tick 不在 ⇒「応答なし」。journal が 20 tick FROZEN (同じ値) ⇒ `lock.d` をチェックする: 生きている = 続行 (1 blob の遅い fetch)、死んでいる = エラー + Resume。これがないと、fetch 途中で死んだ run はトーストを「updating」で固めてしまう。
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`。
- Config: 「Updates」タブで `$VDLU_DIR/config` (key=value) を読み書きする。
- Toast: バー + `phase done/total · current`。`reboot_pending` で終了すると ⇒ 永続バナー「reboot to activate the .so」。
- Auto-open (`auto_on_webui_open=1`): まず QUIET な `check()` を行う (進捗トーストなし)。`update && fetch>0` のときだけ `run`+永続トーストを起動する。最新/ahead/新しいものなし = パネル内のインライン結果で、トーストの残りはゼロ。手動ボタンと同様に非侵襲的 (本当のダウンロードがあるときだけトーストが現れる)。curl のブートストラップは 1 回だけ。

## 10. デモへの統合 (INTEGRATION コンポーネント) - スニペット、ライブファイルは編集しない

`integration/demo/` に、スニペット + 各スニペットの配置先を記した `INTEGRATION.md` を (適用せずに) 生成する:
- `post-fs-data`/`service.sh` 内の `auto_on_reboot` フック (pre-zygote → `update.sh boot`) と `auto_on_webui_open`。
- `config` のデフォルト + 組み込み keyring + 同梱 (`modules/<mod>/vdlu/`)。
- PARTIAL バリアント (マウントされたディレクトリへのマージ)。

## 11. 取得されるツールチェーン + ベースライン (SLIM、アプローチ B)

**モジュール (zip) 内のレイアウト:** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`。`bin/` (openssl/curl/zstd) は**なし**。`customize.sh` は `verify/` を
デバイスの ABI まで刈り込める (`vdlu-verify` は mini を `<dir>/ed25519-mini` または `<dir>/verify/<abi>/ed25519-mini` で見つける)。

**ed25519-mini** (組み込みバイナリ、検証専用): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=有効、
1=無効、2=使用法/IO。msg = 署名された正確なバイト列 (再ハッシュはしない)。TweetNaCl PD、ABI ごとに静的、PROVENANCE。

**tools-feed** (public/https プロファイルのみ): `<tools_source>` で提供される (デフォルトの導出: `source` の最後の
セグメントを `vdlu-tools` に置き換える。例 `https://<user>.github.io/<repo>/vdlu-tools`)。内容:
- `tools-manifest.json` - `<abi>/curl` ツリー上の署名された `vdlu-pack` manifest。各 curl の `sha256` を
  ピン留めする (同じ `release-2026` キー)。
- `<abi>/curl` - 生の**静的** curl (自己完結、約 1MB。curl 8.11.1 + mbedTLS)。🪤 mbedTLS は
  CA バンドルを持たない: `fetch_url` は `--capath` を渡す (Android トラストストアの自動検出: `/system/etc/security/cacerts`
  → APEX conscrypt。`ca_path` で上書き)。capath なし = エラー 60。完全性は ed25519 であり、cert チェックは多層防御。

**install-tool** (ENGINE): `update.sh install-tool <abi>` は `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
を読み (WEBUI が `fetch()` でダウンロードしてそこに書き込む)、**tools-manifest の署名を検証し (ed25519-mini、
どのプロファイルでも必須)** + curl のハッシュ == manifest を検証し、それからのみ `$VDLU_DIR/tools/<abi>/curl` (0755) にインストールする。
curl は root として実行される → exec 前の sig+hash が RCE を塞ぐ。Tier-2 に永続化する: 再ダウンロードされない (アンインストール時を除く)。

**fetch-bootstrap** (WEBUI、`ensureToolchain()`): check/run/resume の前に実行される。`file://` = no-op。curl が**既に**
利用可能 (Tier-2、または**自己同梱**モジュールの `module/bin/<abi>/curl`、またはシステム) = no-op
(VDLU は既存の curl を再利用する)。curl が**まったくない** `https` の場合のみ、webview 経由で curl + tools-manifest をダウンロードし、
それらを `.work` に書き (`ksu.exec` 経由のチャンク base64)、`install-tool` を呼ぶ。信頼 = ダウンロードではなく、オンデバイスのチェック。

> 🪤 **スリム (fetch-bootstrap) ≠ 必須。** **自分自身の**機能のために `bin/` が存在するモジュール (例: 
> restic/rclone/age/tar/curl などを同梱) は、約 2MB までスリム化せず、curl もダウンロードしない - VDLU はスリムなエンジン
> (gz、mini、baseline、修正群) を採用し、組み込みツールチェーンを**再利用**する。自前のツールチェーンを持たないモジュール
> だけが約 2MB を得る。

**baseline.json** (from:0 の修正): リリースは出荷されるバージョンの署名済み `manifest.json` を
`vdlu/baseline.json` にコピーする。新規インストール時にエンジンはそこから `current.json` を seed する (`init_paths`、不在の場合のみ) → 
デバイスは「current」な状態で生まれ、自己の自動更新も再取得もしない。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
