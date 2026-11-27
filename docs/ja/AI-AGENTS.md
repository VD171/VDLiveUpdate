> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · 日本語 · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# AI エージェントから VDLU を操作する

VDLiveUpdate (VDLU) は、KSU/Magisk モジュールが `vdlu/` にベンダリングする、フラッシュレスの増分アップデーターです。エンジン全体がシェルから操作されるため、AI アシスタントやエージェントはアップデートをヘッドレスで確認、適用、再開、完了できます。WebUI が回すのと同じサイクルで、UI なし、ループに人間なしです。出力される JSON を解析し、テキストを決してスクレイプしないでください。

## 契約

単一のエントリポイントを、デバイス上で root として、エンジンの 3 つの環境変数を設定して実行します:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` は Tier-2 の状態ディレクトリ（モジュールの外、再フラッシュを生き延びる）、`MODULE_DIR` はモジュールの生きたツリー、`MODID` はモジュール ID です。
- `rc 0` = OK、`rc != 0` = エラー、理由は stderr に出ます。
- 読み取り動詞（`check`、`status`）は stdout に **1 つの JSON オブジェクト** を出力します。それを解析し、テキストを決してスクレイプしないでください。
- エンジンは toybox（`sha256sum`/`gzip`/`base64`）と組み込みの `ed25519-mini`、そして最初の https 更新時に取得される静的な `curl` だけに依存します。`jq` はゼロです。

開発中は同じスクリプトがこのリポジトリの `engine/update.sh` にあるので、3 つの変数を設定した `sh engine/update.sh <verb>` がステージング用のコピーを同じように操作します。

## 動詞

| 動詞 | すること | 出力 |
|------|------|--------|
| `check` | フィードに対する読み取り専用の DIFF、何も変えない | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`、またはデバイスがフィードより先行している場合は `{"update":false,"ahead":true,"from":N,"to":M}`（ダウングレードはブロック、無害、rc 0） |
| `run` | 完全な LIVE サイクル DIFF -> FETCH -> APPLY -> COMMIT、LIVE ファイルを適用し REBOOT-hard をステージし、`cancel` を尊重する | 進捗は `journal.json` に |
| `resume` | 保留中のトランザクションを現在のフェーズから再開、冪等、`.so` を決して入れ替えない | 更新された `journal.json` |
| `boot` | pre-zygote モード、`resume` に加えてステージ済み `.so` の入れ替え、`PENDING_REBOOT` を `DONE` に閉じる | 更新された `journal.json` |
| `status` | 読み取り専用のスナップショット、何も変えない | `journal.json`、またはトランザクションが未稼働のときは `{"state":"idle"}` |
| `cancel` | 停止を要求、進行中の `run` は次の安全地点で止まる | `$VDLU_DIR/cancel` を作成 |

ヘッドレスなアップデートとは、保留があるかを見る `check`、ライブにできるすべてを適用する `run`、そして次回の起動でステージ済みの `.so` を入れ替える `boot` です（または延期されたフェッチを再試行する `resume`）。どの動詞も再び呼んで安全で、サイクル途中のクラッシュやネットワーク切断は再開可能なジャーナルを残し、決して半適用のモジュールを残しません。

## 状態 JSON

`status`（および `$VDLU_DIR/journal.json` の生きたファイル）は、WebUI とエージェントの双方が読む進捗契約です:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` は固定順で進みます: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`。
- `DONE` はすべての再ハッシュが一致して初めて到達します。ステージ済みの REBOOT-hard ファイルは `PENDING_REBOOT` を生み、決して偽の `DONE` にはなりません。完了するには `boot` を実行します。
- `DEFERRED` は `net_policy` がダウンロードをブロックしたことを意味します。無害で再開可能な状態であり、エラーではありません。プランは残り、次の `check`/`boot` が続行します。
- `ERROR` は理由を `error` に持ち、適用済みの LIVE ファイルは `rollback/` から戻され、モジュールは決して半適用で残りません。
- `cancelled:true` かつ `error:null` はクリーンな停止で、ジャーナルは再開可能なまま残ります。

## シーム契約

あらゆるコンポーネント（エンジン、プロデューサー、WebUI）は収束の法則である [`INTERFACES.md`](INTERFACES.md) に従います。CLI 動詞、`manifest.json` スキーマ、`journal.json` キー、そこで定義された config キーは **不変** です。そのファイルを唯一の真実の源として扱い、いずれかを変える前にそれに合わせてください。エンジン内部（再開可能トランザクション、厳格さの保証、trust-anchor の除外）は [`ENGINE.md`](ENGINE.md) を、フィード側（内容アドレス指定フィードのビルドと署名）は [`PRODUCER.md`](PRODUCER.md) を参照してください。

## エージェントのための規則

- 動詞と JSON を使い、WebUI を決してスクレイプせず、状態ファイルを決して手で編集しないでください。
- `INTERFACES.md` を不変として扱い、変更はまず契約を合わせることを意味します。
- AI エージェントからのパッチは他のどれとも同じレビュー基準を通ります。build は常に release、何も緩めず、何も失わないでください。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
