> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · 日本語 · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU エンジン (`update.sh`)

KSU/Magisk モジュール向けの flashless で増分的な更新クライアント。
`DIFF -> FETCH -> APPLY -> COMMIT` サイクルを再開可能なトランザクションとして実装する。`INTERFACES.md` (収束の
法則) に準拠する。

純粋な POSIX sh (mksh/busybox/toybox)。**SLIM:** 依存するのは toybox (`sha256sum`/`gzip`/`base64`/`date`) +
組み込みの `ed25519-mini` (ed25519 検証。**デバイス上に openssl なし**) + 最初の https 更新時に**取得される**静的な
`curl` (WebUI が `fetch()` を行い、Tier-2 に永続化し、`install-tool` が使用**前に**その署名+ハッシュを
検証する) のみ。`file://` は curl を必要としない。`jq` への依存はゼロ。

## 呼び出し

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok。`rc != 0` = エラー (理由は stderr)。`vdlu-verify` は別のコンポーネントが提供する
(署名は `INTERFACES.md §6`)。エンジンはそれを呼ぶだけ。

| cmd | 動作 |
|---|---|
| `check` | 読み取り専用 DIFF。`{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` を出力する。何も変更しない |
| `run` | フル LIVE サイクル + REBOOT-hard をステージ。`cancel` を尊重する。進捗は `journal.json` に |
| `resume` | 保留中のトランザクション (`target.json`) を現在のフェーズから再開する。冪等。`.so` の swap は**しない** |
| `boot` | pre-zygote モード: resume **+** `staged/*.vdlu-new` を swap する → `PENDING_REBOOT`→`DONE` を閉じる。保留中のトランザクションがなければ、新しいサイクルを実行し、すべて (`.so` を含む) を 1 回の boot で適用する |
| `status` | `journal.json` を出力する (なければ `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` を作成する。進行中の `run` は次の安全地点で停止する |

## 状態機械 (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` は**すべて**の再ハッシュが一致したときのみ。REBOOT-hard がステージされていれば ⇒ `PENDING_REBOOT` (偽の
`DONE` には決してしない)。いかなる失敗でも `ERROR`。ただしモジュールは壊さない (適用済みの LIVE ファイルは
`rollback/<v>/` から戻される。「半分適用して嘘をつく」ものはない)。`fetch` フェーズの良性な出口: **`DEFERRED`** -
`net_policy` によってダウンロードが延期された (ネットワークが許可されていない)。plan/target は保持され、次の
check/boot で再開する (WebUI はエラーではなく青い情報トースト「waiting for X network」を表示する)。

## 厳格性の保証

- **FETCH:** `net_policy` でゲートされる (any/wifi/mobile。http/https のみ、`file://` は決して対象外)。許可されていない
  ネットワーク ⇒ データを消費せずに `DEFERRED` (再開可能)。欠けているものだけを `<sha>.part` にダウンロードし (curl は
  `--connect-timeout` + `--speed-time` 付きで、決してハングしない)、`gz` を展開し (toybox `gunzip`)、`sha256sum` ==
  manifest をチェックし、アトミックに `blobs/<sha>` へ `mv`。キャッシュ済み+ok の blob はスキップされる。変更のない
  ローカルファイルから blob を seed できる (dedup/オフライン)。**同じ blob で 3 回失敗 = フェーズは何も適用せずに中止する。**
  plan のすべての blob が存在+検証済みになって初めて `FETCHED` になる。
- **APPLY** (`FETCHED` からのみ): `live`/`soft` → `rollback/<v>/` にバックアップ → `.vdlu-tmp` → `chmod` → 検証 →
  アトミックな `rename`。`reboot` → `staged/<path>.vdlu-new` に実体化する (ライブの inode には触れない)。
  `delete[]` → バックアップ → 削除。冪等 (既にターゲットのハッシュであるファイルはスキップされる)。
- **COMMIT:** すべての `live`/`soft` の再ハッシュ。それからのみ `current.json` を書く。ステージされたファイルがあれば ⇒
  `PENDING_REBOOT`。`boot` は `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + 再検証 +
  `DONE` を行う。
- **cancel:** ファイルの間 (安全地点) でチェックされる。進行中の `.vdlu-tmp`/`.part` を削除し、`cancel` を削除し、
  journal を再開可能な状態 (`cancelled:true`、`error:null`) にしておく。
- **mkdir-lock `$VDLU_DIR/lock.d`** が直列化する (flock は toybox で動かない。stale 回復は PID による)。
  忍耐強い boot-retry は待機中にロックを保持せず (`acquire_lock_try`+release を試行の間に行う)、wakelock も持たない -
  バッテリーに優しい。途中でのクラッシュ/ネットワーク/reboot → `resume`/`boot` が続行する。
- **profile=hardened** ⇒ 使用**前に** manifest に対する `vdlu-verify` が必須。失敗 = 中止。ダウングレードはブロック
  (単調なバージョン)。**trusted** ⇒ 検証はベストエフォートだが、すべての blob のハッシュは**常に**チェックされる。
- 優雅に劣化する: バイナリ欠落 / ネットワーク不通 / ディスクフル → stderr に明確なエラー + journal の `state:ERROR`。
  モジュールは壊さない。

## jq なしの JSON 解析

`awk` による gron スタイルのフラット化 (純粋な POSIX: `substr`/`index`/`gsub`/`split`/`printf` + パラメータとして渡される
ローカル変数) が manifest を文字単位でトークン化し、スカラーのリーフごとに 1 行の `path<TAB>value` を出力する
(`files/0/sha256<TAB>ab..`、`version<TAB>6`、`delete/0<TAB>etc/x`)。コンパクト**または**整形済みの
JSON に対して堅牢。`sh` は `grep`/`cut` でそれを消費する。ファイルごとの plan は 2 番目の `awk` で TSV
(`class st mode enc sha size path`) に再構築され、`$VDLU_DIR/plan.tsv` になる。

## 状態ファイル (`$VDLU_DIR` 内、Tier-2)

| ファイル | 役割 |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…。INTERFACES §5 参照) |
| `current.json` | ACTIVE バージョンの manifest (diff ベース)。不在 = 一度も更新されていない |
| `target.json` | 進行中トランザクションのピン留め manifest (存在 = アクティブなトランザクション)。`DONE` で `current.json` になる |
| `plan.tsv` / `plan.del` | plan + ファイルごとの進捗 (st) / 削除するパス |
| `journal.json` | WebUI 向けの進捗 (各遷移で再生成される) |
| `blobs/<sha256>` | 検証済みオリジナル内容のキャッシュ |
| `rollback/<version>/<path>` | 上書きされたファイルのバックアップ (undo。最後の 3 つを保持する) |
| `staged/<path>.vdlu-new` | boot での swap を待つ REBOOT-hard |
| `lock.d/` | mkdir-lock (flock は toybox で動かない。stale 回復は PID による) |
| `tools/<abi>/curl` | 取得された静的 curl (スリムなブートストラップ)。更新をまたいで永続化する |
| `cancel` | キャンセル要求 |

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
