# WebUI

VDLU には、オプションのドロップイン型 WebUI ウィジェットが同梱されています。KernelSU または APatch の root マネージャー WebUI 向けの小さな「Updates」パネルです。ユーザーに、Check ボタン、Update now ボタン、キャンセル付きのライブ進捗トースト、再起動バナー、設定パネルを提供し、これらすべてをユーザーがターミナルに一切触れることなく使えます。

これは**バニラ JavaScript** です。フレームワークも、ビルドステップも、CDN もありません。三つのファイル:

| ファイル | 内容 |
|---|---|
| `vdlu.js` | ウィジェット本体。`window.VDLU` を公開する |
| `vdlu.css` | トースト、バナー、パネルのスタイル(ダークテーマ。ホストの CSS 変数を継承する) |
| `demo.html` | 端末ブリッジをモックしてUI 全体をプレーンなブラウザで動かすスタンドアロンページ |

ウィジェットは完全にオプションです。[[Engine]] はブートトリガーから単独で問題なく動作します。WebUI はその上に乗る親しみやすい表面にすぎません。モジュールへの組み込みについては [[Quick Start]] を参照してください。

---

## UI がエンジンと対話する仕組み: `ksu.exec` ブリッジ

ウィジェット自体が特権的なことを行うことは決してありません。シェルコマンドを組み立てて root マネージャーの `ksu.exec` ブリッジに渡し、ブリッジがそれを root として実行して stdout / stderr / 終了コードを返します。パネルが表示するすべては、エンジンが書き込んだファイルから読み戻されます。

ウィジェットはそのブリッジを、`Promise` を返す単一の `exec(cmd)` 関数でラップします:

- コマンドが 0 で終了すると stdout で **resolve** する
- それ以外では stderr(または `rc=N`)で **reject** する

すべてのコマンドは、ウィジェットが組み立てる契約の環境変数を運びます:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

いくつかの具体的な呼び出し:

- **更新の開始:** `update.sh run` は**バックグラウンド**(`(... &)`)で起動されるので、長いダウンロードによって UI がブロックされることは決してありません。
- **進捗の読み取り:** `cat $VDLU_DIR/journal.json` の軽いポーリング(約 1 秒に 1 回)。
- **キャンセル:** `touch $VDLU_DIR/cancel`(エンジンは次の安全なポイントで停止します)。
- **設定:** `$VDLU_DIR/config`(key=value)の読み書き。順序と未知のキーを保ち、ユーザーが変更したキーだけに触れます。

ホストが独自の `exec`、`toast`、`confirm` ヘルパーを `init()` に渡すと、ウィジェットはホスト自身の直列化されたコマンドキューとビジュアルを経由するので、その WebUI の他の部分と同じように見え、同じように振る舞います。それらが省略された場合、ウィジェットは `ksu.exec` を直接呼び出すフォールバックとなり、独自のミニトーストを注入します。

---

## 進捗トースト(キャンセル付き)

更新が実行されると、ウィジェットは非ブロッキングのコーナートーストを表示し、`journal.json` をポーリングします。トーストはエンジンの状態機械を反映します:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

進捗バーに加えて、`phase done/total - current file - bytes` の一行を描画し、全体を通して **Cancel** ボタンを備えます。終端状態はそれぞれ固有の扱いを受けます:

- **DONE** -> 緑のトースト、「vX applied - all verified」。
- **PENDING_REBOOT** -> 緑のトーストに加えて、永続的な再起動バナー(下記)。
- **ERROR** -> `journal.error` または stderr からの理由を伴う赤のトースト。Retry を提示します。成功を偽ることは決してありません。
- **Cancelled** -> 琥珀色のトースト、「cancelled - N/M applied, resumable」。**Resume** を提示します。
- **DEFERRED** -> 穏やかな青の情報トースト、「download deferred, waiting for the allowed network」。これはエラーではなく無害なネットワークポリシーの待機で、適切なネットワーク上での次の check またはブートで再開します。

ポーリングは防御的です。書きかけのジャーナル(エンジンは並行して書き込む)は、誤って解析される代わりにその tick では無視されます。進捗が確認された後にジャーナルが消えた場合、それはコミットがクリアしたことを意味するので、ウィジェットは DONE を報告します。最初からジャーナルが 8 tick の間不在であれば、「no response」を報告します。そしてジャーナルが 20 tick の間同じ値で凍結した場合、ウィジェットはエンジンの `lock.d` をチェックします。ロックが生きていれば、それは単に遅い単一 blob の取得にすぎず、トーストは待ち続けます。ロックが死んでいれば実行が途中で死んだので、ウィジェットは「updating」で永遠に回り続ける代わりに、Resume ボタン付きのエラーを表面化させます。

---

## 再起動バナー

一部のファイルはライブのシステム上で入れ替えられません。`.so`、`/system` オーバーレイ、`sepolicy.rule` です。エンジンはそれらをステージングし、トランザクションを `PENDING_REBOOT` とマークします。するとウィジェットは**永続的な上部バナー**を表示します: 「Reboot to activate the new `.so` (vX)」。ステージングされたファイルが次回ブート時に入れ替えられるまで残ります。WebUI を開くとバナーはジャーナルから再評価されるので、UI を閉じて再び開いたユーザーにも依然として表示されます。ブート時に何が起こるかは [[Reboot Handling]] を参照してください。

バナーが終端状態の `PENDING_REBOOT` を手がかりにしており、`reboot_pending` フラグ(いずれかの `.so` がプランに入るとすぐに真になる)を手がかりにしていない点に注意してください。これにより、実際に何かがステージングされる前の実行途中でバナーが現れるのを防ぎます。

---

## 「Updates」パネル: カテゴリごとの独立したトグル

`mountUpdatesPanel(el)` は、ホストが提供する空の `<div>` に設定パネルを描画します。三つのセクションがあり、各コントロールは独立していて、それぞれ単独で保存します:

**Actions**
- **Check for updates** -> `check` を実行し、結果をインラインで表示します(最新 / フィードより新しい / ファイル数と再起動タグ付きで更新あり)。
- **Update now** -> `run` に進捗トーストを加えて発火します。

**Automation**(独立したトグル。切り替えた瞬間にそれぞれ `config` に書き込まれる)
- **On WebUI open**(`auto_on_webui_open`)-> UI が開いたときに静かな更新を実行します。
- **On reboot**(`auto_on_reboot`)-> ブート時のプリzygote で適用します。
- **Boot retry every (s)** と **Boot retry up to (min)** -> 端末がオフラインでブートしたときにマニフェストの取得をリトライするための数値フィールド。

**Source**
- `source`(フィード URL)、`channel`(stable / canary)、`profile`(trusted / hardened)、そして `net_policy` にマッピングされる **Network** セレクト(Wi-Fi + モバイル / Wi-Fi のみ / モバイルのみ)。

トグルと数値フィールドは即座に保存され、書き込みが失敗すれば視覚的に元に戻ります。Source セクションのテキストとセレクトのフィールドは自身を dirty とマークし、明示的な Save ボタンでまとめて保存します。パネルは常にユーザーが触れたキーだけを書き換えるので、未知または将来の config キーは保たれます。

### 自動オープンの挙動

`onWebUIOpen()` はホストのロード時に呼ばれます。ジャーナルを評価し(再起動バナーを表示するか、前のセッションが残した非終端トランザクションに対して Resume を提示する)、次に `auto_on_webui_open=1` であれば、まず**静かな** `check()` を実行します。永続的な進捗トーストと実際の `run` は、行うべき実際のダウンロードがある場合(`update && fetch > 0`)にのみ発火します。端末が最新であるかフィードより先行している場合、結果はパネル内にインライン表示され、トーストは画面に残りません。したがって自動更新は手動ボタンと同じくらい控えめです。

---

## i18n(言語ごとの文字列)

すべての UI 文字列はデフォルトで**英語**であり、これは公開される多言語モジュールにとって中立的な選択です。完全なキーマップは `vdlu.js` の `DEFAULT_I18N` オブジェクト(`VDLU.i18n` としても公開)にあります。ホストは `init({ i18n: ... })` にマップを渡すことで、キーの任意の部分集合を上書きします:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- **部分的な**マップでも問題ありません。欠けているキーは英語のデフォルトにフォールバックします。
- フェーズと状態のラベルは `ph_<phase>` と `st_<STATE>` のキーを使い、残りは `cancel`、`updateNow` のようなフラットなキーです。
- 翻訳の作業例(`i18n/pt-BR.js`)がテンプレートとして同梱されます。新しい言語は同じ形の `i18n/<lang>.js` ファイルにすぎず、あるいはホストが自身の i18n システムからマップを構築します。

---

## demo.html: 端末なしで UI を動かす

`demo.html` は `ksu.exec` ブリッジをモックするので、まったく同じ `vdlu.js` と `vdlu.css` が、root もスマートフォンもなしにプレーンなブラウザで動作します:

```sh
xdg-open webui/demo.html
```

モックは `update.sh` と進化する `journal.json` をシミュレートし、そのボタンはシナリオを切り替えます。DONE までのライブ更新、`reboot_pending` での終了、途中でのエラー、キャンセル可能な実行です。UI を見て反復するのに最も速い方法であり、ウィジェットをモジュールにベンダリングする前にあなたが確認するものです。

---

## モジュールへの組み込み(WebUI オープントリガー)

ホストの `index.html` は二つのファイルを読み込み、三つの関数を呼び出します:

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

ホストが用意する必要があるのは、Tier-2 のパスを供給することと、パネル用に空の `<div>` を一つ割り当てることだけです。トーストとバナーはウィジェットによって `document.body` に注入されます。`onWebUIOpen()` が WebUI オープントリガーです。再起動バナーを評価し、中断されたトランザクションに対して Resume を提示し、`auto_on_webui_open` が設定されていれば静かな自動更新を実行するものです。

### 単一のソース、バイト単位で再ベンダリング

`vdlu.js` と `vdlu.css` が**正準コピー**です。ウィジェットを埋め込むモジュールは、これらのファイルを変更せずに自身の `webroot/` へ再ベンダリングします。自身のコピーをその場で編集することは決してありません。新機能は正準ファイルで誕生し、再ベンダリングによって流れ下ります。ベンダリングされたコピーを編集すると、気づかないドリフトが生じます(実際に起きたことです。古いコピーに `net_policy`、DEFERRED トースト、ブートリトライのフィールドが欠けていました)。ソースツリー内のパリティ守護者がすべてのコピーを見つけ、逸脱したものをフラグするか再ベンダリングします。対象はウィジェットのみで、キーリングには独自の「コピーせず検証する」サイクルがあります。

---

### 公開 API(`window.VDLU`)

| 関数 | 機能 |
|---|---|
| `init(opts)` | ウィジェットを構成する。`window.VDLU` を返す |
| `onWebUIOpen()` | ロード時に呼ぶ: バナー、Resume の提示、静かな自動更新 |
| `mountUpdatesPanel(el)` | Updates パネルを `el`(id 文字列または要素)に描画する |
| `check()` | `update.sh check` を実行する。`Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | `run` をバックグラウンドで発火し、Cancel 付きの進捗トーストを加える |
| `cancel()` | `$VDLU_DIR/cancel` を作成する(エンジンは安全なポイントで停止する) |
| `resume()` | 現在のトランザクションを再開し、トーストを加える |
| `refreshBanner()` | 永続的な保留中再起動バナーを再評価する |

---

関連項目: ウィジェットが駆動するコマンドについては [[Engine]]、完全な導入手順については [[Quick Start]]、バナーが何を待っているかについては [[Reboot Handling]] を参照してください。
