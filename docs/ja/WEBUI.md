> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · 日本語 · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI ウィジェット (flashless 更新)

KernelSU/APatch root マネージャ WebUI 向けの VDLU (VD Live Update) インターフェース。Vanilla JS、フレームワークなし、
ビルドなし、CDN なし。ドロップイン: ホストの `index.html` が 2 ファイルを読み込み、API を呼ぶ。

収束: `INTERFACES.md` §9 (WEBUI↔ENGINE)、§4 (journal.json)、§5 (config)。

## ファイル

| ファイル | 内容 |
|---|---|
| `vdlu.js` | コンポーネント - `window.VDLU` を公開する |
| `vdlu.css` | 進捗トースト、reboot バナー、「Updates」タブ (ダークテーマ、ホストの変数を継承する) |
| `demo.html` | モックされた `ksu.exec` を持つスタンドアロンページ - ブラウザで開く、デバイス不要 |

## ホストの `index.html` への統合

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

### ホストが定義しなければならないもの

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`)、エンジンが同梱される場所
  (`vdlu/update.sh`)。
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`)、Tier-2 の状態 (`journal.json`、`config`、
  `cancel`)。
- **`modid`** = モジュール id。

ウィジェットは契約の env (§1) を既に携えたエンジンコマンドを組み立てる:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`。`run`/`resume` は
**バックグラウンド** (`(… &)`) に送られ、進捗は `cat $VDLU_DIR/journal.json` の軽量ポーリング (約 1 秒) で読まれる。

### `exec`/`toast`/`confirm` (オプション)

省略された場合、ウィジェットは自前のものを使う:
- **`exec(cmd)`** は、stdout (rc 0) で**解決**し、stderr (rc≠0) で**拒否**する `Promise` を返さなければならない -
  まさに Demo の `webroot/index.html` の `ex()` のシグネチャ。内部フォールバックは同じ契約で
  `ksu.exec(cmd, '{}', cb)` を呼ぶ。
- **`toast(msg)`** = 短い一時的な通知 (フォールバックは自前のミニトーストを注入する)。
- **`confirm(title,msg,ok,danger,fn)`** = モーダル (今日はホストだけが使う。ウィジェットはどのフローでも
  確認を必要としない)。

ホスト自身のものを渡すと、ウィジェットは WebUI の他の部分と**同じ**直列化キューとビジュアルを通じて対話する。

## 公開 API (`window.VDLU`)

| 関数 | 動作 |
|---|---|
| `init(opts)` | 設定する (上記参照)。`window.VDLU` を返す。 |
| `onWebUIOpen()` | load 時に呼ぶ: `reboot_pending` ならバナーを表示する。非終端トランザクションがあれば **Resume** を提供する。`auto_on_webui_open=1` では **QUIET な自動更新**を実行する (まず無音の `check()`。`update && fetch>0` のときだけ `run`+永続トーストを起動する - 最新/ahead = パネル内のインライン結果、トーストはゼロ)。 |
| `mountUpdatesPanel(el)` | `el` (文字列 id または要素) 内に「Updates」タブをレンダリングする: **Check for update**、**Update now**、`auto_on_webui_open`/`auto_on_reboot` トグル、boot-retry フィールド、**Network** セレクト (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only)、`source`/`channel`/`profile` フィールド。 |
| `check()` | `update.sh check` を実行する。`Promise<{update,from,to,fetch,reboot}>`。 |
| `startUpdate()` | `run` をバックグラウンドで起動 + **Cancel** 付きの進捗トースト。 |
| `cancel()` | `$VDLU_DIR/cancel` を作成する (エンジンは安全地点で停止する)。 |
| `resume()` | `update.sh resume` + トースト (現在のフェーズから再開する)。 |
| `refreshBanner()` | 永続的な pending-reboot バナーを再評価する。 |

トースト (隅のオーバーレイ、非ブロッキング) とバナー (上部、永続) はウィジェットが `document.body` に
注入する - ホストはそれらのための HTML を必要としない。「Updates」タブはホストが割り当てる唯一の点である (空の
`<div>`)。

### トーストが反映する状態フロー (journal.json、§4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`。いつでも `ERROR`。
トーストは**バー + `phase done/total · current · bytes`**を表示する。終端:
- **`DONE`** → 緑のトースト「v&lt;target&gt; applied」。
- **`PENDING_REBOOT`** (または `reboot_pending=true`) → 緑のトースト + **永続バナー**「⚠️ Reboot to
  activate the new `.so` (vX)」。
- **`ERROR`** → 理由付きの赤いトースト (`journal.error`/stderr)。決して成功を偽らない。
- **Cancelled** → 「cancelled - N/M, resumable」+ **Resume** ボタン。

## デモの実行

`demo.html` をブラウザで開く (`xdg-open webui/demo.html`)。モックされた `ksu.exec` は `update.sh` と
`journal.json` の進化をシミュレートする。ボタンは **LIVE→DONE**、**reboot_pending**、**error mid-way**、
**cancellable** のシナリオを切り替える。デバイス上と同じ `vdlu.js`/`vdlu.css` である。

## i18n (言語)

ウィジェットの文字列はデフォルトで**英語** (公開の多言語モジュールにとって中立)。ホストは `init` にマップを渡すことで
任意のキーを上書きする:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **部分的な**マージでよい: 欠けているキーは英語のデフォルトにフォールバックする。
- フェーズ/状態キーは `ph_<phase>` / `st_<STATE>`。それ以外はフラット (`cancel`、`updateNow`、…)。
- 完全なキーマップ = `vdlu.js` 内の `DEFAULT_I18N` オブジェクト (`VDLU.i18n` としても公開される)。
- 作業例として、できあがった翻訳が提供される: `i18n/pt-BR.js`。新しい言語 = 同じ型の
  `i18n/<lang>.js` ファイル、またはホストが自前の i18n システムからマップを構築する。

## 単一ソース (モジュール間のパリティ)

これらの `vdlu.js`/`vdlu.css` は**正規コピー**である。ウィジェットを埋め込むすべてのモジュールは、
このコピーをバイト単位で自身の `webroot/` に**再同梱**する - 自身のものをその場で**決して**編集しない。
新しいウィジェット機能はここで生まれ、再同梱で下流に流れる。逆は静かなドリフトを生む (実際に起きた: 同梱コピーが
遅れをとり、`net_policy`、`DEFERRED` トースト、`boot_retry` フィールドを欠いていた)。

ガーディアン: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) はソースツリー内のすべてのコピーを見つけ、
正規のものから乖離しているものを指摘する (`vdlu.js`/`vdlu.css` のみ。keyring は「コピーではなく検証」)。

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring (`keyring/<id>.pub` RAW 32B) とエンジン (`vdlu/update.sh`) は独自の再同梱サイクルを持つ。
> このガーディアンがカバーするのは **WebUI ウィジェットのみ**である。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
