> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · 日本語 · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# セキュリティポリシーと信頼モデル

VDLiveUpdate (VDLU) はライブなモジュールに **flashless root 更新**を適用する: `/data/adb/modules/<mod>` に
書き込み、boot で Zygisk の `.so` を swap する。取得された manifest のすべてのフィールド (`path`、`sha256`、
`delete[]`、`mode`、...) は**敵対的な入力**である - 汚染されたフィードや MITM がそれを配信する。このページは
信頼モデルと責任ある開示ポリシーである。完全な seam 契約については [`INTERFACES.md`](INTERFACES.md) を、
エンジン/プロデューサの内部については [`ENGINE.md`](ENGINE.md) と [`PRODUCER.md`](PRODUCER.md) を参照。wiki
ページの **Security-and-Trust-Model** は、リポジトリ外の読者向けに同じモデルを提供する。

## サポートされるバージョン

セキュリティ修正は最新の `ENGINE_VERSION` に入る。署名された manifest は必要とする最小エンジンを `engine_min`
で宣言し、デバイス上のエンジンは自身が実装するより多くを要求する manifest を拒否する。古い vendor 済みエンジンは、
その場でバックパッチされるのではなく、修正を取り込むために**再 vendor**されることが期待される。

| ENGINE_VERSION | 状態 |
|---|---|
| 7 (現行) | サポート対象 - フィードより先行するモジュールを決して差し戻さない (ライブにインストールされた `versionCode` が "from" バージョンの下限となる)、古い downgrade plan の起動時自己修復 |
| 6 | 置き換え済み - 起動時の自己修復 - 古い `target <= 0` の journal (削除された stub が残した baseline 0 は UI も起動動作も駆動しない) |
| 5 | 置き換え済み - エンジン側の信頼アンカー除外 (フィードが運んでも `vdlu/` ディレクトリは無視される)、128 MiB のファイル単位 / 2 MiB の manifest 上限 |
| 4 | 置き換え済み - `key_id` allowlist、ドットセグメント/末尾スラッシュのパス拒否、サイズ上限、check 時ロック |
| <= 3 | サポート外 - 現行エンジンを再 vendor する |

エンジンの検証または適用ロジックへのいかなる変更も `ENGINE_VERSION` を bump する。

## 脆弱性の報告

非公開で報告すること。セキュリティバグについて、公開の issue、PR、フォーラム投稿を**行わないこと**。プロジェクトの
連絡先を使用する ([`CONTRIBUTING.md`](../CONTRIBUTING.md) 参照):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- チャンネル: **@Priv8_VD** (https://t.me/Priv8_VD)
- E メール: **vd.priv8@pm.me**

エンジンのバージョン、使用中の `profile`、そして問題を再現する manifest またはフィードを含めてほしい。修正は
`CHANGELOG.md` のエントリとともに新しい `ENGINE_VERSION` として出荷される。開示のタイミングは報告スレッドで
調整する。

## 信頼モデル

- **分離された ed25519 署名。** プロデューサは PC 上で正規の manifest に署名する (openssl)。デバイスは組み込みの
  `ed25519-mini` で検証する - **デバイス上に openssl なし**。署名されるメッセージは `sig` フィールドを除いた
  manifest の sha256 16 進 (キーをソート、コンパクト、UTF-8) であるため、署名と検証はデバイス上に JSON
  ライブラリなしで 2 つのランタイム上で同じバイト列を導出する。
- **keyring = RAW 32 バイトの公開鍵**、フラッシュ専用。デバイスの keyring は `<key_id>.pub` を生の 32 バイト鍵
  として出荷する (決して PEM ではない)。`vdlu-pack` は keyring と `verify/` バイナリをフィードから**除外する**ため、
  manifest がワイヤ越しにデバイス上の信頼アンカーを書き換えることは決してできない。
- **エンジン側の信頼アンカー除外 (VDLU#2)。** 上記のプロデューサ側の除外とは独立に、デバイス上のエンジンは
  取得された plan 内のすべての `vdlu/` パス (`update.sh`、`vdlu-verify`、`verify/*`、`keyring/*`、config) を
  **無視する** - フィードがそれらを運んでも、決して取得・適用・削除しない。公開されたフィードは `vdlu/` を含む
  モジュールツリー全体を出荷するため、エンジンは manifest を拒否するのではなく、それらのパスを黙って捨てる:
  モジュールは依然として更新され、信頼アンカーはフルの署名付き再フラッシュを通じてのみ変わる。漏洩した単一の
  署名鍵が、ワイヤ越しに検証器や署名鍵をすり替えて root を永続化することは、もはやできない。
- **module-update の `key_id` allowlist (fail-closed、pubkey 選択の前)。** keyring は正当に複数の鍵を保持する
  ことがある (例えば release 鍵の隣に信頼の低い fingerprint-feed の鍵)。`<key_id>.pub` が選択される前に、
  `verify_manifest` は**両方**の profiles で、`key_id` が設定済みの allowlist にない manifest をすべて拒否し、
  解決された集合を `VDLU_KEYID_ALLOW` 経由で `vdlu-verify` にミラーする。これにより、漏洩した信頼の低い鍵が
  フルの flashless root 更新に署名できてしまうバイパスを塞ぐ。`key_id` が未設定でもデフォルトで安全: **単一鍵**の
  keyring はその 1 つの鍵に自動固定され、**複数鍵**の keyring は `key_id` が固定される (ローテーション用に
  カンマ区切り) まで拒否される。
- **fingerprint-feed の信頼ルートは、独自の鍵を持つ別個の固定されたパスである。** 上記の module-update の
  パスを通じて到達することは決してできない。
- **ベースラインはローカルの信頼された seed である。** `baseline.json` はフラッシュされた zip の中に届く -
  インストールの信頼境界 - ため、署名なし・鍵なしであり、`vdlu-verify` を**通さない**。フィードから**取得された**
  manifest だけが検証される。これにより署名鍵を CI の外に保つ。

## Fail-closed の保証

- **`validate_plan` はあらゆる fetch や apply の前に走る。** `do_diff` の中で fail-closed に、いずれかの `path`
  が絶対パスである、`..` または `.` セグメントを含む、`/` で終わる、または制御文字を保持する場合、いずれかの
  `sha256` が `^[0-9a-f]{64}$` でない場合、あるいはいずれかの `mode`/`class`/`enc` が不正な場合に、manifest
  **全体**を拒否する。敵対的なフィールドがシェルに到達することはなく、`cmd_check` は `system()` の補間を一切
  持たない。
- **パスの封じ込め。** すべての書き込みと削除は `contained()` を介して `MODULE_DIR` に限定される - apply、delete、
  そして reboot の `stage_file` はすべて同じガードを通る。ツリー内のシンボリックリンクはプロデューサによって
  スキップされる (その外部の内容を決してリークしない)。
- **2 つの profiles、反転による fail-closed。** `trusted` (私的、SSH でステージされたソース) はベストエフォート
  検証への**唯一の**オプトインである。**その他の**値は - タイプミス、末尾のスペース/CR、大文字小文字の違いを含め -
  `hardened` として扱われ、そこでは有効な署名が**必須**であり、失敗すると中止する。すべての blob の `sha256` は
  両方の profiles でチェックされる。
- **あらゆるツール実行の前に署名+ハッシュ。** 取得された静的な `curl` は root として走るため、`install-tool` は、
  それがインストール・実行される**前に**、tools-manifest の署名 (ed25519-mini、**どの** profile でも必須) と
  curl のハッシュを検証する - 実行前の sig+hash が RCE を塞ぐ。
- **再開可能で、ピン留めに安全なトランザクション。** 進行中の manifest は `target.json` にピン留めされる。
  クラッシュ、ネットワーク喪失、reboot は、plan を再決定せずに journal から再開する。ダウングレードはブロックされ
  (単調な `version`)、署名された `module` フィールドは `MODID` と等しくなければならず、`delete[]` は
  `finalize_done` でのみ走る (`PENDING_REBOOT` は何も削除しない)。完全な再ハッシュなしに何かが「完了」になる
  ことは決してなく、まず `rollback/<v>/` バックアップなしに何かが上書きされることも決してない。

## ハードニング (多層防御)

- **サイズ上限。** manifest、tools-manifest、そして curl を使わない `wget`/`head -c` のダウンロード経路は
  すべて、読み込まれる前に上限が課される (anti-OOM / anti-flood)。blob は 3 回の試行の後にそのフェーズを
  失敗させる。上限は**ファイルあたり 128 MiB** (`MAX_FILE_BYTES`) と **manifest に対して 2 MiB**
  (`MAX_MANIFEST_BYTES`) であり、`update.sh` で強制され `vdlu-verify` でミラーされる。
- **check 時ロック。** `check` は作業ディレクトリを再構築する前に mkdir-lock を取得するため、並行実行が
  それと競合することはできない。
- **ステージングの封じ込め。** `stage_file` はライブ適用のプリミティブと同じ `contained()` ガードを持つため、
  ステージされた reboot-hard のパスも `MODULE_DIR` から逃れることはできない。
- **TLS は多層防御であって、信頼ルートではない。** 静的な curl は Android の信頼ストアとともに mbedTLS を使う
  (`--capath`、`ca_path` によるオーバーライド)。完全性の保証は ed25519 署名であり、証明書チェックは第 2 層である。

## 関連項目

- [`INTERFACES.md`](INTERFACES.md) - 不変の seam 契約 (§5 config、§6 署名、§11 ツールチェーン)。
- [`ENGINE.md`](ENGINE.md) - デバイス側のエンジンとその状態機械。
- [`PRODUCER.md`](PRODUCER.md) - パッキング、署名、正規化、鍵のローテーション。
- Wiki: **Security-and-Trust-Model**。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
