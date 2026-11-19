> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · 日本語 · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU プロデューサ + 署名レイヤー

モジュールのためのコンテンツアドレス型配信 (manifest + blobs) を構築し、署名する。
[`INTERFACES.md`](INTERFACES.md) §3/§6/§7 に準拠する。

| ツール | 実行場所 | 言語 | 仕事 |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | 最終的なモジュールツリーを走査 -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 鍵ペア (`<id>.pem` 秘密、`<id>.pub` PEM、スリム keyring 用の `<id>.pub.raw` RAW 32B) |
| `producer/vdlu-sign` | PC | sh + openssl | manifest に `key_id` + `sig` をその場で注入する |
| `engine/vdlu-verify` | **デバイス** | sh + ed25519-mini | 組み込みの ed25519-mini 経由で `sig` を検証する。keyring = RAW 32B 公開鍵 (デバイス上に openssl なし) |

## パイプライン

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` はコンテンツアドレス型で重複排除する: `<sha256>` が既に存在する blob は書き直されないため、
公開は増分的で、変更のない / 復帰した内容は決して再プッシュされない。

### `enc` の決定 (vdlu-pack)

`sha256` は**常に**オリジナル (非圧縮) の内容に対するもの。`enc` は blob がどう保存されるかを示すだけ。

- `gz`: `size >= 4096` **かつ** gzip (`-9 -n`、決定論的) が少なくとも 10% 節約する場合 (`comp <= raw*0.90`)。
- それ以外は `raw` (HTTP gzip が既にカバーする小さなテキスト、または既に圧縮不能なデータ)。
- ビルドホストに gzip がない -> すべて `raw` (決して失敗しない)。

blob は 1 つの形式で 1 回だけ保存される: `blobs/<sha256>` (raw) または `blobs/<sha256>.gz` (gz)。デバイスは
toybox `gunzip` (常に存在する) で展開するため、zstd は同梱されない。

### `class` の決定 (vdlu-pack) - reboot 分類

パスから導出される (INTERFACES §3、doc §4)。デフォルトのみ。パスルールは決して `reboot`->`live` にダウングレードしない。

| class | マッチするもの | 適用方法 |
|---|---|---|
| `reboot` | `system/**`、`zygisk/**/*.so`、`*.rule` | `.vdlu-new` としてステージ、boot で swap |
| `soft` | ルートの `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | ライブに書く、次の boot で実行 |
| `live` | それ以外すべて (webroot、bin、lib、confs、module.prop、...) | ライブに書く、アトミック |

シンボリックリンクは**たどらない** (ツリー外の内容、例えば `/etc/shadow` へのリンクを決してリークしない) し、
警告付きでスキップされる。manifest スキーマに symlink 型がないためである。通常ファイルでないもの (ディレクトリ、fifo、
デバイス) はスキップされる。`built` は再現可能な manifest のために `SOURCE_DATE_EPOCH` を尊重する。

### ベースライン (インストール seed) - 署名なし、鍵なし

`baseline.json` (モジュール zip の `vdlu/baseline.json` に出荷される) は新規インストール時に `current.json` を seed し、
デバイスが「current」な状態で生まれるようにする (from:0 なし、再取得なし)。エンジンはこれを**ローカルの信頼された seed** として
扱い (フラッシュされた zip に含まれて届いた。zip はインストールの信頼境界である)、**その署名を検証しない** -
フィードから FETCH された manifest だけが `vdlu-verify` を通る。したがってベースラインには**鍵が不要**である: それは
出荷ツリーに対する単なる `vdlu-pack` の出力 (署名なし。`sig`/`key_id` は空のまま) である。したがって CI は
**鍵なしで**それを生成でき、署名鍵を CI から 100% 外に保てる - 公開される FEED だけが (運用者が、ローカルで) 署名される。
`vdlu-pack` は自身の manifest から `baseline.json` を除外する (自己参照防止)。不在でも致命的ではない: デバイスは
最初の更新で from:0 から始まるだけで、決して壊れない。

## 正規化 (収束点)

`vdlu-sign` と `engine/vdlu-verify` は、2 つの異なるランタイム (PC の openssl 対デバイスの toybox + openssl) で、
manifest から**同じバイト列**を導出しなければならない。このルールは意図的に JSON の再シリアライズではなく
バイト変換であり、デバイス上に JSON ライブラリを必要としない:

1. `vdlu-pack` は `manifest.json` を**コンパクト、キーをソート、UTF-8**で書き
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`)、常にフィールド
   `key_id` と `sig` を含める (署名されるまでは空文字列のプレースホルダ)。これが正規の保存形式である。
2. **正規形 = そのテキストから `"sig"` フィールドを除去したもの。** キーがソートされているため、`sig`
   は常に `,"sig":"<value>",` として現れ、`"schema"` (前) と `"version"` (後) に挟まれる。
   どちらも常に存在する。それを除去すると、整形式の `...,"schema":N,"version":...` が残る。
   JSON は文字列値の中のすべての `"` を `\"` にエスケープするため、構造トークン `"sig":"` は、
   文字どおり `"sig":"` を含むファイル名に対しても曖昧でない (テスト済み)。
3. 署名/検証されるメッセージは正規形の **sha256 16 進** (64 ASCII 文字、改行なし) である。その 16 進に対する ed25519
   (`openssl pkeyutl -sign/-verify -rawin`)。

POSIX sh での除去 (両ツールで同一の関数、`sed`/`jq` なし):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` は正規形の一部である (除去されるのは `sig` のみ)。`vdlu-sign` はハッシュ化の**前に** `key_id` を設定する。
値のプレースホルダが空 (`"sig":""`、署名時) であっても埋まっていても (検証時) 同一の正規バイト列を生むため、
署名と検証は構成上一致する。

Python はそれを `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` の後に sha256 として再現する - 
クロスチェックのためだけに使われる。権威ある生成元は 2 つの sh ツールである。

## 署名 (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (秘密 `0600`) + `openssl pkey -pubout` (公開 **PEM**、
  署名/openssl 用) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER は 12 バイトのプレフィックス + 32 バイトの鍵なので、`tail -c 32` が鍵そのもの)。両方を出力する。
- `vdlu-sign` (PC): 正規 sha256 16 進に対する `openssl pkeyutl -sign -rawin`。署名は base64 で保存される。
- `vdlu-verify` (**デバイス、スリム**): `ed25519-mini <pubkey32> <msg> <sig64>` - keyring を **RAW 32B**
  公開鍵として読む。デバイス上に openssl なし。`key_id` はパスがサニタイズされる (`/`、`.`、`..`、`"` なし)。🚨 keyring は
  **`.pub.raw` (32B)** を出荷し、決して `.pub` PEM (113B) ではない: PEM は PC 側のみで、`ed25519-mini` は読めない。

信頼モデル (INTERFACES §6、doc §11/§13): `profile=hardened` (公開) は検証を必須にする - 署名が
失敗または欠落すると更新を中止する。`profile=trusted` (私的、SSH でステージされたソース) は検証を
ベストエフォートとして扱うが、すべての blob の sha256 は無関係にチェックされる。

## keyring + ローテーション

keyring は `<key_id>.pub` ファイルのディレクトリで、それぞれ **RAW 32B** の ed25519 公開鍵 (`keygen` の
`.pub.raw` 由来) であり、PEM では**ない** - `ed25519-mini` は生の 32 バイトを読む。現在の鍵**と**以前の生公開鍵を
出荷すること (doc §13)。ローテーションされた鍵が古いインストールを壊さないためである。`vdlu-sign` を新しい `key_id` で行い、
デバイスが `<keyring>/<key_id>.pub` (生) を選ぶ、これがローテーション機構のすべてである - エンジンの変更なし。keyring は
リリースをまたいで**安定**している (鍵のローテーションだけが変更する): 再同梱は**コピーではなく検証**すべきであり、
決して PC 側の `.pub` PEM で上書きしてはならない。

`vdlu-pack` は**keyring と `verify/` バイナリをフィードから除外する** (信頼ルートはフラッシュ専用で、決してワイヤ越しに配信されない)。`baseline.json`、インストーラの足場 (`META-INF/`、`customize.sh`)、`.vd/` フラッシュゲート、CI が埋める `update.json`/`update-mmrl.json`、そしてファイルごとの `.sha256` 伴走ファイルも同様である。フィードで更新できるのはモジュール自身のコンテンツだけなので、manifest がデバイス上の信頼アンカーを書き換えることは決してできない。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
